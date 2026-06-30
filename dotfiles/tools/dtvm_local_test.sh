#!/usr/bin/env bash
#
# dtvm_local_test.sh — local EVM inner-loop test runner.
#
# Wraps the four local correctness suites against an ALREADY-BUILT artifact set
# and runs them concurrently:
#
#   unittests   evmone-unittests   (needs libdtvmapi.so + run lists)
#   statetest   evmone-statetest   (needs libdtvmapi.so + a corpus)
#   ctest       built EVM spec tests (needs the build dir)
#   evm_asm     tools/run_evm_tests.py over tests/evm_asm (needs the dtvm CLI)
#
# Building is OUT OF SCOPE — see .claude/rules/dtvm-build-config.md. This script
# only runs tests against what is already built, and refuses (loudly) to run
# when an artifact, corpus, run list, or gtest filter is missing rather than
# emit a false PASS.
#
# Machine-specific paths are env-overridable:
#   EVMONE_BIN_DIR  default ~/evmone/build/bin
#   DTVM_SO         default <repo>/build/lib/libdtvmapi.so
#   DTVM_CLI        default <repo>/build/dtvm
#   FIXTURES_DIR    default <repo>/tests/fixtures/fixtures/state_tests
#   REPLAY_CORPUS   default ~/dtvm-perf-corpora/mainnet-replay/cancun-suite
#   CTEST_JOBS      default 4   (inner ctest -j)
#
# Usage: tools/dtvm_local_test.sh [--auto [--base <ref>]]
#                                 [--mode multipass|interpreter|both]
#                                 [--suite unittests|statetest|ctest|evm_asm|format|all]...
#                                 [--corpus eest|replay|<path>]
#                                 [--jobs N] [--dry-run] [-h|--help]
#
# With no arguments it behaves as --auto.

set -uo pipefail

# ----- bash capability guard ------------------------------------------------
if (( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] < 403 )); then
  echo "FATAL: need bash >= 4.3 (have ${BASH_VERSION}); 'wait -n' is required." >&2
  exit 2
fi

die()  { echo "FATAL: $*" >&2; exit 2; }
warn() { echo "WARN: $*" >&2; }

# ----- locate repo root, run everything from there --------------------------
# Killing the wrong-cwd failure class: every relative path below resolves from
# the repo root regardless of where the caller invoked the script.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) \
  || die "not inside a git repository."
cd "$REPO_ROOT" || die "cannot cd to repo root: $REPO_ROOT"

# ----- env-overridable configuration ----------------------------------------
EVMONE_BIN_DIR=${EVMONE_BIN_DIR:-$HOME/evmone/build/bin}
EVMONE_LIB_DIR=${EVMONE_LIB_DIR:-$EVMONE_BIN_DIR/../lib}
DTVM_SO=${DTVM_SO:-$REPO_ROOT/build/lib/libdtvmapi.so}
DTVM_CLI=${DTVM_CLI:-$REPO_ROOT/build/dtvm}
FIXTURES_DIR=${FIXTURES_DIR:-$REPO_ROOT/tests/fixtures/fixtures/state_tests}
REPLAY_CORPUS=${REPLAY_CORPUS:-$HOME/dtvm-perf-corpora/mainnet-replay/cancun-suite}
CTEST_JOBS=${CTEST_JOBS:-4}

RUNLIST_MULTIPASS=${RUNLIST_MULTIPASS:-tests/evmone_unittests/EVMOneMultipassUnitTestsRunList.txt}
RUNLIST_INTERPRETER=${RUNLIST_INTERPRETER:-tests/evmone_unittests/EVMOneInterpreterUnitTestsRunList.txt}

NPROC=$( (command -v nproc >/dev/null && nproc) || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
(( CTEST_JOBS > NPROC )) && CTEST_JOBS=$NPROC

# ----- argument parsing -----------------------------------------------------
MODE=multipass
CORPUS=eest
AUTO=0
AUTO_BASE=""
DRY_RUN=0
JOBS=0                 # 0 => auto (min(nproc, #tasks))
declare -a SUITES=()
MODE_SET=0
SUITE_SET=0
AUTO_SET=0

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --auto)    AUTO=1; AUTO_SET=1 ;;
    --base)    shift; [ $# -gt 0 ] || die "--base needs a ref"; AUTO_BASE="$1" ;;
    --mode)    shift; [ $# -gt 0 ] || die "--mode needs a value"; MODE="$1"; MODE_SET=1 ;;
    --suite)   shift; [ $# -gt 0 ] || die "--suite needs a value"
               IFS=',' read -ra _s <<< "$1"; SUITES+=("${_s[@]}"); SUITE_SET=1 ;;
    --corpus)  shift; [ $# -gt 0 ] || die "--corpus needs a value"; CORPUS="$1" ;;
    --jobs|-j) shift; [ $# -gt 0 ] || die "--jobs needs a number"; JOBS="$1" ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done

case "$MODE" in multipass|interpreter|both) ;; *) die "bad --mode: $MODE" ;; esac
[[ "$JOBS" =~ ^[0-9]+$ ]] || die "--jobs must be a non-negative integer: $JOBS"

# No explicit intent => auto. --auto wins over --mode/--suite if both given.
if [ "$AUTO_SET" = 0 ] && [ "$MODE_SET" = 0 ] && [ "$SUITE_SET" = 0 ]; then
  AUTO=1
fi
if [ "$AUTO" = 1 ] && { [ "$MODE_SET" = 1 ] || [ "$SUITE_SET" = 1 ]; }; then
  warn "--auto given; ignoring --mode/--suite."
fi

# ----- task command builders ------------------------------------------------
# Each runs in its own subshell during a real run; in --dry-run it prints the
# command instead. A task returns non-zero to mark itself FAILED.

_run_or_print() {   # $@ = argv (already including any `env VAR=val` prefix)
  if [ "$DRY_RUN" = 1 ]; then
    printf '  '; printf '%q ' "$@"; printf '\n'
    return 0
  fi
  "$@"
}

task_unittests() {  # $1 = mode
  local mode="$1" runlist
  case "$mode" in
    multipass)   runlist="$RUNLIST_MULTIPASS" ;;
    interpreter) runlist="$RUNLIST_INTERPRETER" ;;
    *) echo "ERROR: unittests: bad mode '$mode'" >&2; return 3 ;;
  esac
  [ -f "$runlist" ] || { echo "ERROR: run list not found: $runlist" >&2; return 3; }
  local filter
  filter=$(paste -sd: "$runlist") || { echo "ERROR: cannot read $runlist" >&2; return 3; }
  if [ -z "$filter" ]; then
    echo "ERROR: empty gtest filter from $runlist — refusing to run (an empty" \
         "filter selects zero tests and exits 0, a silent false PASS)." >&2
    return 3
  fi
  if [ "$DRY_RUN" = 1 ]; then
    printf '  env LD_LIBRARY_PATH=%q EVMONE_EXTERNAL_OPTIONS=%q %q --gtest_filter="$(paste -sd: %q)"\n' \
      "$EVMONE_LIB_DIR" "$DTVM_SO,mode=$mode" "$EVMONE_BIN_DIR/evmone-unittests" "$runlist"
    return 0
  fi
  env "LD_LIBRARY_PATH=$EVMONE_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
      "EVMONE_EXTERNAL_OPTIONS=$DTVM_SO,mode=$mode" \
    "$EVMONE_BIN_DIR/evmone-unittests" "--gtest_filter=$filter"
}

task_statetest() {  # $1 = mode
  local mode="$1" corpus_path
  local -a cmd
  case "$CORPUS" in
    eest)   corpus_path="$FIXTURES_DIR" ;;
    replay) corpus_path="$REPLAY_CORPUS" ;;
    *)      corpus_path="$CORPUS" ;;        # explicit path: caller owns -k choice
  esac
  cmd=(env "LD_LIBRARY_PATH=$EVMONE_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
       "EVMONE_EXTERNAL_OPTIONS=$DTVM_SO,mode=$mode,enable_gas_metering=true"
       "$EVMONE_BIN_DIR/evmone-statetest" "$corpus_path" --vm external_vm)
  # -k fork_Cancun ONLY for the EEST suite (post-Cancun forks are filtered out);
  # the replay corpus has no fork suffix, so -k would match zero tests.
  [ "$CORPUS" = eest ] && cmd+=(-k fork_Cancun)
  _run_or_print "${cmd[@]}"
}

task_ctest() {      # $1 = mode (feeds SPEC_TESTS_ARGS)
  local mode="$1"
  if [ "$DRY_RUN" = 1 ]; then
    printf '  ( cd %q && env SPEC_TESTS_ARGS=%q ctest -j %q --verbose )\n' \
      "$REPO_ROOT/build" "-m $mode --format evm --enable-evm-gas" "$CTEST_JOBS"
    return 0
  fi
  ( cd "$REPO_ROOT/build" \
    && env "SPEC_TESTS_ARGS=-m $mode --format evm --enable-evm-gas" \
         ctest -j "$CTEST_JOBS" --verbose )
}

task_evm_asm() {    # $1 = mode
  local mode="$1"
  _run_or_print python3 tools/run_evm_tests.py -r "$DTVM_CLI" \
    -m "$mode" --format evm --enable-evm-gas
}

task_format() {     # mode ignored
  _run_or_print ./tools/format.sh check
}

# ----- preflight: assert the union of requirements once ---------------------
preflight() {
  local need_so=0 need_evmone=0 need_unittests=0 need_eest=0 need_replay=0
  local need_cli=0 need_ctest=0 need_format=0 t suite
  for t in "${TASKS[@]}"; do
    suite=${t%%:*}
    case "$suite" in
      unittests) need_so=1; need_evmone=1; need_unittests=1 ;;
      statetest) need_so=1; need_evmone=1
                 case "$CORPUS" in eest) need_eest=1 ;; replay) need_replay=1 ;; esac ;;
      evm_asm)   need_cli=1 ;;
      ctest)     need_ctest=1 ;;
      format)    need_format=1 ;;
    esac
  done

  local missing=0
  _req_file() { [ -f "$1" ] || { echo "MISSING ($2): $1" >&2; missing=1; }; }
  _req_dir()  { [ -d "$1" ] || { echo "MISSING ($2): $1" >&2; missing=1; }; }
  _req_exe()  { [ -x "$1" ] || { echo "MISSING ($2): $1" >&2; missing=1; }; }

  [ "$need_so" = 1 ]        && _req_file "$DTVM_SO" "libdtvmapi.so — build first, see dtvm-build-config.md"
  [ "$need_evmone" = 1 ]    && _req_exe  "$EVMONE_BIN_DIR/evmone-unittests" "evmone binaries — set EVMONE_BIN_DIR"
  [ "$need_evmone" = 1 ]    && _req_exe  "$EVMONE_BIN_DIR/evmone-statetest" "evmone binaries — set EVMONE_BIN_DIR"
  [ "$need_unittests" = 1 ] && _req_file "$RUNLIST_MULTIPASS" "run list"
  [ "$need_unittests" = 1 ] && _req_file "$RUNLIST_INTERPRETER" "run list"
  [ "$need_eest" = 1 ]      && _req_dir  "$FIXTURES_DIR" "EEST state_tests fixtures — download or set FIXTURES_DIR"
  [ "$need_replay" = 1 ]    && _req_dir  "$REPLAY_CORPUS" "replay corpus — set REPLAY_CORPUS"
  [ "$need_cli" = 1 ]       && _req_exe  "$DTVM_CLI" "dtvm CLI — build first, see dtvm-build-config.md"
  [ "$need_ctest" = 1 ]     && _req_file "$REPO_ROOT/build/CTestTestfile.cmake" "build dir — configure/build first"
  [ "$need_format" = 1 ]    && _req_file "$REPO_ROOT/tools/format.sh" "format script"

  if [ "$missing" = 1 ]; then
    if [ "$DRY_RUN" = 1 ]; then
      warn "preflight: artifacts above are missing (allowed in --dry-run)."
    else
      die "preflight failed — required artifacts are missing (see above)."
    fi
  fi
}

# ----- --auto: map the working-tree diff to a task set ----------------------
declare -a TASKS=()

# Pick the commit to diff against: the merge-base with the default branch, so a
# committed feature branch reports its whole diff (plus any uncommitted work).
# Falls back to HEAD (working-tree only) when no base branch is resolvable.
resolve_base() {
  if [ -n "$AUTO_BASE" ]; then
    git rev-parse --verify --quiet "$AUTO_BASE" >/dev/null || die "--base ref not found: $AUTO_BASE"
    git merge-base HEAD "$AUTO_BASE" 2>/dev/null || die "no merge-base between HEAD and $AUTO_BASE"
    return
  fi
  local ref
  for ref in origin/main main origin/master master; do
    if git rev-parse --verify --quiet "$ref" >/dev/null; then
      git merge-base HEAD "$ref" 2>/dev/null && return
    fi
  done
  echo HEAD
}

resolve_auto() {
  local base changed
  base=$(resolve_base)
  if [ "$base" = HEAD ]; then
    warn "--auto: no base branch found; diffing working tree against HEAD only."
    changed=$(git diff --name-only HEAD 2>/dev/null)
  else
    # branch diff (base..HEAD) plus uncommitted changes (vs HEAD)
    changed=$( { git diff --name-only "$base" HEAD; git diff --name-only HEAD; } 2>/dev/null )
  fi
  changed=$(printf '%s\n' "$changed" | sed '/^$/d' | sort -u)

  if [ -z "$changed" ]; then
    warn "--auto: no changed files; using safe default (multipass unittests + statetest)."
    TASKS=("unittests:multipass" "statetest:multipass")
    return
  fi

  echo "# --auto base ${base:0:12} detected changes:" >&2
  printf '%s\n' "$changed" | sed 's/^/    /' >&2

  local want_mp=0 want_interp=0 want_ctest=0 want_docs=0 want_unknown=0 f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
      src/compiler/*|src/runtime/*) want_mp=1 ;;
      src/evm/*)                    want_interp=1 ;;
      src/tests/*)                  want_ctest=1 ;;
      docs/*|.claude/*|CLAUDE.md|*.md) want_docs=1 ;;
      *)                            want_unknown=1 ;;
    esac
  done <<< "$changed"

  local -a t=()
  [ "$want_mp" = 1 ]     && t+=("unittests:multipass" "statetest:multipass" "evm_asm:multipass")
  [ "$want_interp" = 1 ] && t+=("unittests:interpreter" "statetest:interpreter" "evm_asm:interpreter")
  [ "$want_ctest" = 1 ]  && t+=("ctest:multipass")

  if [ ${#t[@]} -eq 0 ]; then
    if [ "$want_docs" = 1 ] && [ "$want_unknown" = 0 ]; then
      echo "# --auto: docs/config-only change -> format check + ctest smoke (evmone skipped per touched-path rule)." >&2
      t+=("format:all" "ctest:multipass")
    else
      echo "# --auto: unknown/mixed change -> safe default (multipass unittests + statetest)." >&2
      t+=("unittests:multipass" "statetest:multipass")
    fi
  fi
  TASKS=("${t[@]}")
}

# ----- manual: expand --mode x --suite --------------------------------------
resolve_manual() {
  local -a modes=()
  case "$MODE" in
    multipass)   modes=(multipass) ;;
    interpreter) modes=(interpreter) ;;
    both)        modes=(multipass interpreter) ;;
  esac
  [ "$SUITE_SET" = 1 ] || SUITES=(all)

  local -a t=() s m
  for s in "${SUITES[@]}"; do
    case "$s" in
      unittests|statetest|evm_asm)
        for m in "${modes[@]}"; do t+=("$s:$m"); done ;;
      ctest)  t+=("ctest:${modes[0]}") ;;
      format) t+=("format:all") ;;
      all)
        for m in "${modes[@]}"; do t+=("unittests:$m" "statetest:$m" "evm_asm:$m"); done
        t+=("ctest:${modes[0]}") ;;
      *) die "unknown suite: $s" ;;
    esac
  done
  TASKS=("${t[@]}")
}

# ----- resolve & dedup tasks ------------------------------------------------
if [ "$AUTO" = 1 ]; then resolve_auto; else resolve_manual; fi
[ ${#TASKS[@]} -gt 0 ] || die "no tasks selected."
mapfile -t TASKS < <(printf '%s\n' "${TASKS[@]}" | awk '!seen[$0]++')

preflight

# ----- dry run: just print the commands -------------------------------------
if [ "$DRY_RUN" = 1 ]; then
  echo "# resolved tasks (${#TASKS[@]}):"
  for t in "${TASKS[@]}"; do
    echo "## ${t%%:*} (${t#*:})"
    "task_${t%%:*}" "${t#*:}"
  done
  exit 0
fi

# ----- real run: bounded-concurrency scheduler ------------------------------
if [ "$JOBS" -le 0 ]; then
  JOBS=${#TASKS[@]}
  (( JOBS > NPROC )) && JOBS=$NPROC
fi

LOG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dtvm_local_test.XXXXXX") || die "cannot create log dir"
echo "running ${#TASKS[@]} suite(s), up to $JOBS concurrent; logs in $LOG_DIR"

declare -A SF
running=0
for t in "${TASKS[@]}"; do
  suite=${t%%:*}; mode=${t#*:}
  log="$LOG_DIR/${suite}_${mode}.log"
  sf="$LOG_DIR/${suite}_${mode}.status"
  SF["$t"]="$sf"
  if (( running >= JOBS )); then wait -n; running=$((running - 1)); fi
  (
    start=$SECONDS
    printf '[start] %s\n' "$t"
    "task_$suite" "$mode" >"$log" 2>&1
    rc=$?
    dur=$((SECONDS - start))
    printf '%d %d\n' "$rc" "$dur" >"$sf"
    if [ "$rc" -eq 0 ]; then
      printf '[pass]  %s (%ss)\n' "$t" "$dur"
    else
      printf '[FAIL]  %s (%ss, rc=%d) -> %s\n' "$t" "$dur" "$rc" "$log"
    fi
  ) &
  running=$((running + 1))
done
wait

# ----- summary --------------------------------------------------------------
echo
echo "==== summary ===="
fail=0
for t in "${TASKS[@]}"; do
  sf="${SF[$t]}"
  if [ -f "$sf" ]; then read -r rc dur < "$sf"; else rc=99; dur=0; fi
  if [ "$rc" -eq 0 ]; then
    printf '  PASS  %-26s %ss\n' "$t" "$dur"
  else
    printf '  FAIL  %-26s %ss (rc=%d)\n' "$t" "$dur" "$rc"
    fail=$((fail + 1))
  fi
done
echo "  logs: $LOG_DIR"

if [ "$fail" -gt 0 ]; then
  echo
  echo "==== $fail/${#TASKS[@]} suite(s) FAILED — tails below ===="
  for t in "${TASKS[@]}"; do
    sf="${SF[$t]}"; [ -f "$sf" ] && read -r rc _ < "$sf" || rc=99
    if [ "$rc" -ne 0 ]; then
      echo "----- $t -----"
      tail -n 30 "${sf%.status}.log" 2>/dev/null || echo "(no log)"
    fi
  done
  exit 1
fi
echo "==== all ${#TASKS[@]} suite(s) passed ===="
exit 0
