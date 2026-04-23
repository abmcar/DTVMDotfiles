#!/usr/bin/env bash
# codex-dtvm-memory-sync.sh — Bridge Claude Code DTVM project memory into
# a Codex extension at ~/.codex/memories/memories_extensions/dtvm-cc-memory.
# Spec: DTVM/docs/superpowers/specs/2026-04-23-codex-project-memory-bridge-design.md
# Isolation guarantee: touches no path under ~/claude-sync.
set -euo pipefail

# --- Exit codes (spec §Exit codes) ---
readonly EXIT_OK=0
readonly EXIT_ERR=1
readonly EXIT_DRIFT=2
readonly EXIT_NO_SOURCE=3
readonly EXIT_GUARD_REFUSED=4

# --- Paths (env override allowed for testing; see --help) ---
CC_MEMORY_DIR="${CODEX_DTVM_MEMORY_DIR_OVERRIDE:-${HOME}/.claude/projects/-home-abmcar-DTVM/memory}"
readonly CODEX_EXT_ROOT="${HOME}/.codex/memories/memories_extensions"
readonly EXT_SHARED_DIR="${CODEX_EXT_ROOT}/dtvm-cc-memory"
readonly EXT_LOCAL_DIR="${CODEX_EXT_ROOT}/dtvm-cc-memory-local"

# --- Flag state ---
MODE="sync"   # sync | check
FORCE=0
VERBOSE=0

# --- Logging ---
log()  { [ "$VERBOSE" -eq 1 ] && printf '[sync] %s\n' "$*" >&2 || true; }
warn() { printf '[sync][warn] %s\n' "$*" >&2; }
die()  { printf '[sync][err] %s\n' "$*" >&2; exit "${2:-$EXIT_ERR}"; }

# --- Flag parser ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)      MODE="check"; shift;;
        --force)      FORCE=1;      shift;;
        --verbose|-v) VERBOSE=1;    shift;;
        --help|-h)
            cat <<EOF
Usage: $(basename "$0") [--check] [--force] [--verbose]

Syncs Claude Code DTVM project memory into a Codex extension.

Options:
  --check    Report drift without writing.
  --force    Override hash-guard refusals (overwrite externally-modified
             target files, delete untracked files under resources/).
  --verbose  Log per-file actions to stderr.

Exit codes:
  0  success (in-sync, regen done, or --check reports clean)
  1  script error (bad args, I/O failure)
  2  --check: drift detected
  3  source directory missing (non-fatal; emits warning)
  4  hash-guard refused (target was externally modified; rerun --force)

Environment:
  CODEX_DTVM_MEMORY_DIR_OVERRIDE  Override source dir (for testing).

Spec:
  \$DTVM_ROOT/docs/superpowers/specs/2026-04-23-codex-project-memory-bridge-design.md
EOF
            exit "$EXIT_OK";;
        *) die "unknown arg: $1";;
    esac
done

# --- Bootstrap guard (spec §Behavior rule 1) ---
if [ ! -d "$CC_MEMORY_DIR" ]; then
    warn "skip: no CC memory at $CC_MEMORY_DIR"
    exit "$EXIT_NO_SOURCE"
fi

# --- Snapshot-then-read (spec §Behavior rule 2) ---
SNAP="$(mktemp -d -t dtvm-memory-snapshot.XXXXXX)"
trap 'rm -rf "$SNAP"' EXIT INT TERM HUP
log "snapshot dir: $SNAP"

# -L dereferences symlinks; -a preserves perms/times.
# Trailing /. copies contents, not the parent dir itself.
cp -aL "$CC_MEMORY_DIR/." "$SNAP/"
log "snapshot populated from $CC_MEMORY_DIR"

# --- Filter & route (spec §Behavior rule 3) ---
# - Skip hidden files (.consolidate-lock etc.) and non-*.md.
# - Route *.local.md to the -local extension, others to shared.
declare -a SHARED_FILES=()
declare -a LOCAL_FILES=()

while IFS= read -r -d '' f; do
    name="$(basename "$f")"
    case "$name" in
        .*)          continue;;
        *.local.md)  LOCAL_FILES+=("$f");;
        *.md)        SHARED_FILES+=("$f");;
    esac
done < <(find "$SNAP" -maxdepth 1 -type f -name '*.md' -print0)

log "filtered: ${#SHARED_FILES[@]} shared + ${#LOCAL_FILES[@]} local"

if [ "${#SHARED_FILES[@]}" -eq 0 ] && [ "${#LOCAL_FILES[@]}" -eq 0 ]; then
    warn "source dir contains no *.md files — nothing to sync"
    exit "$EXIT_OK"
fi

# --- Hash helpers (spec §Behavior rule 4) ---
# Usage: hash_file <path>  -> prints 64-char hex sha256, or empty if missing.
hash_file() {
    [ -f "$1" ] || { echo ""; return; }
    sha256sum -- "$1" | awk '{print $1}'
}

# Global associative array for current extension's recorded hashes.
declare -A HASHES

# Usage: load_hashes <ext_dir>  -> populates HASHES from <ext>/.sync-hash.
# Lines: "<relpath>\t<sha256>". Empty/missing file → empty HASHES.
load_hashes() {
    HASHES=()
    local hashfile="$1/.sync-hash"
    [ -f "$hashfile" ] || return 0
    while IFS=$'\t' read -r rel sha; do
        [ -z "$rel" ] && continue
        HASHES["$rel"]="$sha"
    done < "$hashfile"
}

# Usage: save_hashes <ext_dir>  -> writes HASHES atomically to .sync-hash.
save_hashes() {
    local ext_dir="$1"
    local hashfile="$ext_dir/.sync-hash"
    local tmp="$hashfile.tmp.$$"
    : > "$tmp"
    for rel in "${!HASHES[@]}"; do
        printf '%s\t%s\n' "$rel" "${HASHES[$rel]}" >> "$tmp"
    done
    mv "$tmp" "$hashfile"
}

# --- Atomic per-file write (spec §Behavior rule 5) ---
# Same-dir tmp → mv is POSIX-atomic on the same filesystem.
# Usage: _write <src> <target> <hash_key> <hash_value>
_write() {
    local src="$1" target="$2" key="$3" hash="$4"
    mkdir -p "$(dirname "$target")"
    local tmp="$target.tmp.$$"
    cp -a "$src" "$tmp"
    mv "$tmp" "$target"
    HASHES["$key"]="$hash"
    log "wrote $target"
}

# --- Hash-guarded write (spec §Behavior rule 4 decision table) ---
# Returns: 0 on write, 10 on skip-unchanged, 4 on refused (EXIT_GUARD_REFUSED).
guarded_write() {
    local src="$1" ext_dir="$2" rel="$3"
    local target="$ext_dir/resources/$rel"
    local key="resources/$rel"
    local h_new h_target h_recorded
    h_new="$(hash_file "$src")"
    h_target="$(hash_file "$target")"
    h_recorded="${HASHES[$key]-}"

    # Case 1: first run — neither target nor recorded hash exists.
    if [ -z "$h_target" ] && [ -z "$h_recorded" ]; then
        _write "$src" "$target" "$key" "$h_new"
        return 0
    fi
    # Case 2: unchanged — target matches recorded, new content matches target.
    if [ -n "$h_recorded" ] && [ "$h_target" = "$h_recorded" ] && [ "$h_new" = "$h_target" ]; then
        log "skip unchanged: $rel"
        return 10
    fi
    # Case 3: legitimate update — target matches recorded; new content differs.
    if [ -n "$h_recorded" ] && [ "$h_target" = "$h_recorded" ]; then
        _write "$src" "$target" "$key" "$h_new"
        return 0
    fi
    # Case 4/5: externally modified (recorded differs) OR untracked foreign file.
    if [ "$FORCE" -eq 1 ]; then
        warn "forced overwrite of externally-modified $target"
        _write "$src" "$target" "$key" "$h_new"
        return 0
    fi
    warn "refuse: $target was externally modified (rerun with --force to overwrite)"
    return "$EXIT_GUARD_REFUSED"
}

# --- Main sync: shared extension ---
mkdir -p "$EXT_SHARED_DIR/resources"
load_hashes "$EXT_SHARED_DIR"
for f in "${SHARED_FILES[@]}"; do
    rel="$(basename "$f")"
    rc=0
    guarded_write "$f" "$EXT_SHARED_DIR" "$rel" || rc=$?
    case "$rc" in
        0|10) ;;               # write / skip-unchanged
        *) exit "$rc";;        # 4 (refused) or other error
    esac
done
save_hashes "$EXT_SHARED_DIR"

# --- Main sync: local extension ---
mkdir -p "$EXT_LOCAL_DIR/resources"
load_hashes "$EXT_LOCAL_DIR"
for f in "${LOCAL_FILES[@]}"; do
    rel="$(basename "$f")"
    rc=0
    guarded_write "$f" "$EXT_LOCAL_DIR" "$rel" || rc=$?
    case "$rc" in
        0|10) ;;
        *) exit "$rc";;
    esac
done
save_hashes "$EXT_LOCAL_DIR"

log "sync complete: ${#SHARED_FILES[@]} shared + ${#LOCAL_FILES[@]} local"
