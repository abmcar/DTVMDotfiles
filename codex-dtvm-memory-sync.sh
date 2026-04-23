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
