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

# --- Pruning with bidirectional guard (spec §Behavior rule 6) ---
# Removes resources/<name>.md not in $KEEP (newline-separated basenames).
# Refuses to delete files that are untracked or externally modified,
# unless --force.
prune_ext() {
    local ext_dir="$1"
    local keep="$2"
    local resdir="$ext_dir/resources"
    [ -d "$resdir" ] || return 0
    while IFS= read -r -d '' f; do
        local existing key h_cur h_rec
        existing="$(basename "$f")"
        # Keep MEMORY.md (written separately in Task 7, not tracked as CC source).
        [ "$existing" = "MEMORY.md" ] && continue
        if grep -qxF "$existing" <<< "$keep"; then
            continue
        fi
        key="resources/$existing"
        h_cur="$(hash_file "$f")"
        h_rec="${HASHES[$key]-}"
        if [ -z "$h_rec" ]; then
            if [ "$FORCE" -eq 1 ]; then
                warn "forced delete of untracked $f"
                rm -- "$f"
            else
                warn "refuse: untracked foreign file $f (--force to delete)"
                return "$EXIT_GUARD_REFUSED"
            fi
        elif [ "$h_cur" != "$h_rec" ]; then
            if [ "$FORCE" -eq 1 ]; then
                warn "forced delete of externally-modified $f"
                rm -- "$f"
                unset 'HASHES[$key]'
            else
                warn "refuse: externally-modified $f (--force to delete)"
                return "$EXIT_GUARD_REFUSED"
            fi
        else
            log "prune: $f"
            rm -- "$f"
            unset 'HASHES[$key]'
        fi
    done < <(find "$resdir" -maxdepth 1 -type f -name '*.md' -print0)
}

# Build KEEP lists (basenames, one per line) for prune.
build_keep_list() {
    local -n arr="$1"
    local item
    for item in "${arr[@]}"; do
        basename "$item"
    done
}

# --- Header stamping (spec §Behavior rule 8) ---
# Emits markdown bullets that describe source snapshot + build info.
emit_stamp() {
    local label="$1" count="$2" src="$3"
    local newest_mtime
    newest_mtime="$(find "$src" -maxdepth 1 -type f -name '*.md' -printf '%T@\n' 2>/dev/null \
        | sort -nr | head -1 | awk '{printf "%d", $1}')"
    local newest_iso gen_iso
    if [ -n "$newest_mtime" ] && [ "$newest_mtime" != "0" ]; then
        newest_iso="$(date -u -d "@$newest_mtime" +%Y-%m-%dT%H:%M:%SZ)"
    else
        newest_iso="unknown"
    fi
    gen_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    cat <<EOF
- Source: $src
- Source count ($label): $count
- Newest source-file mtime: $newest_iso
- Generated: $gen_iso
- Host: $(hostname) ($(uname -s))
- Regenerate: \`bash DTVMDotfiles/codex-dtvm-memory-sync.sh\`
EOF
}

write_instructions() {
    local ext_dir="$1" label="$2" count="$3"
    local target="$ext_dir/instructions.md"
    local tmp="$target.tmp.$$"
    cat > "$tmp" <<EOF
# DTVM Claude Code Project Memory (imported, $label)

This extension mirrors the user's Claude Code project-scoped memory for the
DTVM repo. When the task touches DTVM code, build config, test suites,
benchmarks, or any DTVM-specific workflow, this is likely relevant.

## When to consult this extension

- Any task whose cwd is under \`~/DTVM\` or \`/home/abmcar/DTVM\`.
- Any task mentioning: DTVM, EVM JIT (multipass, singlepass, interpreter),
  dMIR / CgIR / MIR, x86 peephole optimization, evmone benchmarks or
  statetests, gas metering (EIP-3529, gas_register, enable_gas_metering),
  u256 ABI batching, LIBEVM build, WISA paper, ZEN_ENABLE_* CMake flags,
  lazy JIT / OSR, SPP, dotfiles (DTVMDotfiles), claude-sync relationship.
- Any question about user-observed behavior patterns, past incidents,
  or review preferences on this project.

## How to use once consulting

1. Start at \`resources/MEMORY.md\` — a curated index with one-line hooks
   per entry. Scan for relevance to the current task.
2. Fetch specific \`resources/<name>.md\` files only when the MEMORY.md hook
   suggests they apply. Do not bulk-load.
3. Each resource file keeps its YAML frontmatter — the \`description:\`
   field is the canonical one-line summary; \`type:\` is one of
   \`user\` / \`feedback\` / \`project\` / \`reference\`.
4. Prefer \`feedback_*\` files for behavioral guidance, \`reference_*\` for
   pointer-style memories, \`project_*\` for ongoing initiative context.

## Scope & freshness

$(emit_stamp "$label" "$count" "$CC_MEMORY_DIR")

## Machine locality warning

Generated from machine-local CC memory. Mac and WSL2 currently diverge
independently; Phase 1 (DTVMDotfiles-managed project memory source) will
unify them. Until then, entries reflect only one machine's perspective.
EOF
    mv "$tmp" "$target"
    HASHES["instructions.md"]="$(hash_file "$target")"
}

# Copies CC MEMORY.md into extension's resources/, prepending a stamp.
write_memory_index() {
    local ext_dir="$1" label="$2" count="$3"
    local src="$CC_MEMORY_DIR/MEMORY.md"
    local target="$ext_dir/resources/MEMORY.md"
    [ -f "$src" ] || { warn "no MEMORY.md in source — skipping"; return 0; }
    local tmp="$target.tmp.$$"
    mkdir -p "$(dirname "$target")"
    {
        echo "<!-- Auto-generated by DTVMDotfiles/codex-dtvm-memory-sync.sh. Do not edit. -->"
        emit_stamp "$label" "$count" "$CC_MEMORY_DIR" | sed 's/^/<!-- /; s/$/ -->/'
        echo
        cat "$src"
    } > "$tmp"
    mv "$tmp" "$target"
    HASHES["resources/MEMORY.md"]="$(hash_file "$target")"
}

# --- Drift detection in --check mode (spec §Behavior rule 9) ---
# Extracts a labelled bullet field from a stamp in instructions.md.
# Usage: extract_stamp_field <instructions.md> "<field-label>"
extract_stamp_field() {
    local file="$1" label="$2"
    [ -f "$file" ] || { echo ""; return; }
    grep -m1 -E "^- ${label}:.*" "$file" | sed -E "s/^- ${label}:[[:space:]]*//"
}

if [ "$MODE" = "check" ]; then
    # Both extensions must exist.
    for ext_dir in "$EXT_SHARED_DIR" "$EXT_LOCAL_DIR"; do
        if [ ! -f "$ext_dir/instructions.md" ]; then
            log "drift: missing $ext_dir/instructions.md"
            exit "$EXIT_DRIFT"
        fi
    done
    # Shared count + newest mtime.
    stored_count="$(extract_stamp_field "$EXT_SHARED_DIR/instructions.md" 'Source count \(shared\)')"
    if [ "$stored_count" != "${#SHARED_FILES[@]}" ]; then
        log "drift: shared count stored=$stored_count actual=${#SHARED_FILES[@]}"
        exit "$EXIT_DRIFT"
    fi
    stored_mtime="$(extract_stamp_field "$EXT_SHARED_DIR/instructions.md" 'Newest source-file mtime')"
    actual_mtime_raw="$(find "$CC_MEMORY_DIR" -maxdepth 1 -type f -name '*.md' -printf '%T@\n' \
        | sort -nr | head -1 | awk '{printf "%d", $1}')"
    actual_mtime="$(date -u -d "@$actual_mtime_raw" +%Y-%m-%dT%H:%M:%SZ)"
    if [ "$stored_mtime" != "$actual_mtime" ]; then
        log "drift: stored_mtime=$stored_mtime actual=$actual_mtime"
        exit "$EXIT_DRIFT"
    fi
    # Local count.
    stored_local="$(extract_stamp_field "$EXT_LOCAL_DIR/instructions.md" 'Source count \(local\)')"
    if [ "$stored_local" != "${#LOCAL_FILES[@]}" ]; then
        log "drift: local count stored=$stored_local actual=${#LOCAL_FILES[@]}"
        exit "$EXIT_DRIFT"
    fi
    exit "$EXIT_OK"
fi

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
SHARED_KEEP="$(build_keep_list SHARED_FILES)"
prune_ext "$EXT_SHARED_DIR" "$SHARED_KEEP" || exit "$?"
write_instructions "$EXT_SHARED_DIR" shared "${#SHARED_FILES[@]}"
write_memory_index "$EXT_SHARED_DIR" shared "${#SHARED_FILES[@]}"
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
LOCAL_KEEP="$(build_keep_list LOCAL_FILES)"
prune_ext "$EXT_LOCAL_DIR" "$LOCAL_KEEP" || exit "$?"
write_instructions "$EXT_LOCAL_DIR" local "${#LOCAL_FILES[@]}"
save_hashes "$EXT_LOCAL_DIR"

log "sync complete: ${#SHARED_FILES[@]} shared + ${#LOCAL_FILES[@]} local"
