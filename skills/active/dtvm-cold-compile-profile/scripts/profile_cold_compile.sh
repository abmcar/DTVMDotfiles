#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  profile_cold_compile.sh [options] -- <command> [args...]

Required:
  --build-dir DIR       Configured DTVM build directory
  --corpus PATH         Input file or directory; repeat for multiple inputs
  --output-dir DIR      New evidence-bundle path

Options:
  --repo DIR            DTVM git worktree (default: current git root)
  --work-dir DIR        Subject command working directory (default: current dir)
  --perf PATH           perf executable (default: perf from PATH)
  --event EVENT         perf sampling event (default: cpu-clock)
  --frequency HZ        perf sampling frequency (default: 999)
  --call-graph MODE     perf call-graph mode (default: dwarf,8192)
  --allow-dirty         Permit tracked changes and preserve their patch
  --expect-corpus-manifest FILE
                        Require current corpus identity to match FILE
  --expect-binary-sha256 SHA256
                        Require the subject binary to match SHA256
  --expect-build-artifacts FILE
                        Require current DTVM build artifacts to match FILE
  --expect-cache-sha256 SHA256
                        Require CMakeCache.txt to match SHA256
  --expect-source-commit COMMIT
                        Require the repository HEAD to match COMMIT
  --expect-source-status FILE
                        Require tracked status to match FILE exactly
  --expect-source-patch-sha256 SHA256
                        Require the tracked patch to match SHA256
  --dry-run             Validate and print the sealed run without writing
  -h, --help            Show this help

The output path must not already exist. A clean source tree is required unless
--allow-dirty is explicit.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

need_value() {
  [[ $# -ge 2 ]] || die "$1 requires a value"
}

canonical_dir() {
  local value=$1
  [[ -d "$value" ]] || die "directory does not exist: $value"
  (
    cd "$value"
    pwd -P
  )
}

canonical_path() {
  local value=$1
  [[ -e "$value" ]] || die "path does not exist: $value"
  local parent base
  parent=$(dirname "$value")
  base=$(basename "$value")
  parent=$(canonical_dir "$parent")
  printf '%s/%s\n' "$parent" "$base"
}

quote_command() {
  local arg
  for arg in "$@"; do
    printf '%q ' "$arg"
  done
  printf '\n'
}

hash_stream() {
  sha256sum | awk '{print $1}'
}

emit_corpus_manifest() {
  local corpus item relative
  for corpus in "$@"; do
    if [[ -f "$corpus" ]]; then
      printf 'corpus-file  %s\n' "$corpus"
      sha256sum "$corpus"
    elif [[ -d "$corpus" ]]; then
      printf 'corpus-directory  %s\n' "$corpus"
      while IFS= read -r -d '' item; do
        relative=${item#"$corpus"/}
        if [[ -L "$item" ]]; then
          die "corpus trees must not contain symlinks: $corpus/$relative"
        elif [[ -f "$item" ]]; then
          sha256sum "$item"
        fi
      done < <(find "$corpus" -mindepth 1 \( -type f -o -type l \) -print0 |
        sort -z)
    else
      die "unsupported corpus path: $corpus"
    fi
  done
}

write_corpus_manifest() {
  local destination=$1
  shift
  emit_corpus_manifest "$@" >"$destination"
}

emit_build_artifact_roots() {
  local argument candidate name

  find "$BUILD_DIR" -maxdepth 4 \( -type f -o -type l \) \
    \( -name dtvm -o -name libdtvmapi.so -o -name 'libdtvmapi.so.*' \) \
    -print0

  for argument in "${COMMAND[@]:1}"; do
    candidate=$argument
    if [[ "$candidate" != /* ]]; then
      candidate="$WORK_DIR/$candidate"
    fi
    if [[ -e "$candidate" || -L "$candidate" ]]; then
      name=$(basename "$candidate")
      if [[ "$name" == libdtvmapi.so || "$name" == libdtvmapi.so.* ]]; then
        candidate=$(canonical_path "$candidate")
        printf '%s\0' "$candidate"
      fi
    fi
  done
}

emit_artifact_identity() {
  local logical=$1
  local current target final hash
  declare -A visited=()

  logical=$(canonical_path "$logical")
  printf 'artifact\tlogical=%q\n' "$logical"
  current=$logical
  while [[ -L "$current" ]]; do
    [[ -z "${visited[$current]+present}" ]] ||
      die "build artifact symlink loop: $logical"
    visited["$current"]=true
    target=$(readlink -- "$current") ||
      die "cannot read build artifact symlink: $current"
    printf 'symlink\tpath=%q\ttarget=%q\n' "$current" "$target"
    if [[ "$target" == /* ]]; then
      current=$target
    else
      current="$(dirname "$current")/$target"
    fi
    current=$(realpath --canonicalize-missing --no-symlinks -- "$current")
  done

  final=$(realpath --canonicalize-existing -- "$logical") ||
    die "cannot resolve build artifact: $logical"
  [[ -f "$final" ]] || die "build artifact does not resolve to a file: $logical"
  hash=$(sha256sum "$final" | awk '{print $1}')
  printf 'realpath\tpath=%q\n' "$final"
  printf 'sha256\thash=%s\n' "$hash"
}

emit_build_artifact_identity() {
  local artifact
  printf 'format=dtvm-build-artifacts-v1\n'
  while IFS= read -r -d '' artifact; do
    emit_artifact_identity "$artifact"
  done < <(emit_build_artifact_roots | LC_ALL=C sort -zu)
}

emit_build_artifact_hashes() {
  local artifact resolved
  while IFS= read -r -d '' artifact; do
    resolved=$(realpath --canonicalize-existing -- "$artifact")
    printf '%s\0' "$resolved"
  done < <(emit_build_artifact_roots | LC_ALL=C sort -zu) |
    LC_ALL=C sort -zu |
    while IFS= read -r -d '' artifact; do
      sha256sum "$artifact"
    done
}

dirty_submodules() {
  local repo="$1"
  GIT_OPTIONAL_LOCKS=0 git -C "$repo" submodule foreach --quiet --recursive '
    if test -n "$(git status --porcelain=v1 --untracked-files=normal --ignore-submodules=none)"; then
      printf "%s\n" "$displaypath"
    fi
  '
}

REPO=""
BUILD_DIR=""
WORK_DIR="$PWD"
PERF_BIN="perf"
EVENT="cpu-clock"
FREQUENCY="999"
CALL_GRAPH="dwarf,8192"
OUTPUT_DIR=""
ALLOW_DIRTY=false
DRY_RUN=false
CORPORA=()
EXPECTED_CORPUS_MANIFEST=""
EXPECTED_BINARY_SHA256=""
EXPECTED_BUILD_ARTIFACTS=""
EXPECTED_CACHE_SHA256=""
EXPECTED_SOURCE_COMMIT=""
EXPECTED_SOURCE_STATUS=""
EXPECTED_SOURCE_PATCH_SHA256=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --repo)
    need_value "$@"
    REPO=$2
    shift 2
    ;;
  --build-dir)
    need_value "$@"
    BUILD_DIR=$2
    shift 2
    ;;
  --work-dir)
    need_value "$@"
    WORK_DIR=$2
    shift 2
    ;;
  --perf)
    need_value "$@"
    PERF_BIN=$2
    shift 2
    ;;
  --event)
    need_value "$@"
    EVENT=$2
    shift 2
    ;;
  --frequency)
    need_value "$@"
    FREQUENCY=$2
    shift 2
    ;;
  --call-graph)
    need_value "$@"
    CALL_GRAPH=$2
    shift 2
    ;;
  --corpus)
    need_value "$@"
    CORPORA+=("$2")
    shift 2
    ;;
  --output-dir)
    need_value "$@"
    OUTPUT_DIR=$2
    shift 2
    ;;
  --allow-dirty)
    ALLOW_DIRTY=true
    shift
    ;;
  --expect-corpus-manifest)
    need_value "$@"
    EXPECTED_CORPUS_MANIFEST=$2
    shift 2
    ;;
  --expect-binary-sha256)
    need_value "$@"
    EXPECTED_BINARY_SHA256=$2
    shift 2
    ;;
  --expect-build-artifacts)
    need_value "$@"
    EXPECTED_BUILD_ARTIFACTS=$2
    shift 2
    ;;
  --expect-cache-sha256)
    need_value "$@"
    EXPECTED_CACHE_SHA256=$2
    shift 2
    ;;
  --expect-source-commit)
    need_value "$@"
    EXPECTED_SOURCE_COMMIT=$2
    shift 2
    ;;
  --expect-source-status)
    need_value "$@"
    EXPECTED_SOURCE_STATUS=$2
    shift 2
    ;;
  --expect-source-patch-sha256)
    need_value "$@"
    EXPECTED_SOURCE_PATCH_SHA256=$2
    shift 2
    ;;
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    break
    ;;
  *)
    die "unknown option: $1"
    ;;
  esac
done

[[ $# -gt 0 ]] || die "missing subject command after --"
[[ -n "$BUILD_DIR" ]] || die "--build-dir is required"
[[ ${#CORPORA[@]} -gt 0 ]] || die "at least one --corpus is required"
[[ -n "$OUTPUT_DIR" ]] || die "--output-dir is required"
[[ "$FREQUENCY" =~ ^[1-9][0-9]*$ ]] ||
  die "--frequency must be a positive integer"
[[ -z "$EXPECTED_BINARY_SHA256" ||
  "$EXPECTED_BINARY_SHA256" =~ ^[0-9a-fA-F]{64}$ ]] ||
  die "--expect-binary-sha256 must be a SHA-256 value"
[[ -z "$EXPECTED_CACHE_SHA256" ||
  "$EXPECTED_CACHE_SHA256" =~ ^[0-9a-fA-F]{64}$ ]] ||
  die "--expect-cache-sha256 must be a SHA-256 value"
[[ -z "$EXPECTED_SOURCE_COMMIT" ||
  "$EXPECTED_SOURCE_COMMIT" =~ ^([0-9a-fA-F]{40}|[0-9a-fA-F]{64})$ ]] ||
  die "--expect-source-commit must be a full Git object ID"
[[ -z "$EXPECTED_SOURCE_PATCH_SHA256" ||
  "$EXPECTED_SOURCE_PATCH_SHA256" =~ ^[0-9a-fA-F]{64}$ ]] ||
  die "--expect-source-patch-sha256 must be a SHA-256 value"

if [[ -z "$REPO" ]]; then
  REPO=$(git rev-parse --show-toplevel 2>/dev/null) ||
    die "--repo is required outside a git worktree"
fi

REPO=$(canonical_dir "$REPO")
BUILD_DIR=$(canonical_dir "$BUILD_DIR")
WORK_DIR=$(canonical_dir "$WORK_DIR")
GIT_OPTIONAL_LOCKS=0 git -C "$REPO" rev-parse --is-inside-work-tree \
  >/dev/null 2>&1 ||
  die "not a git worktree: $REPO"
SOURCE_COMMIT=$(GIT_OPTIONAL_LOCKS=0 git -C "$REPO" rev-parse HEAD)
[[ -z "$EXPECTED_SOURCE_COMMIT" ||
  "$SOURCE_COMMIT" == "$EXPECTED_SOURCE_COMMIT" ]] ||
  die "source commit differs from the expected commit"
[[ -f "$BUILD_DIR/CMakeCache.txt" ]] ||
  die "missing CMakeCache.txt in build directory: $BUILD_DIR"
CMAKE_SOURCE_DIR=$(
  awk -F= '$1 == "CMAKE_HOME_DIRECTORY:INTERNAL" {print $2}' \
    "$BUILD_DIR/CMakeCache.txt"
)
[[ -n "$CMAKE_SOURCE_DIR" ]] ||
  die "CMakeCache.txt has no CMAKE_HOME_DIRECTORY"
CMAKE_SOURCE_DIR=$(canonical_dir "$CMAKE_SOURCE_DIR")
[[ "$CMAKE_SOURCE_DIR" == "$REPO" ]] ||
  die "build directory belongs to $CMAKE_SOURCE_DIR, not $REPO"

if [[ "$PERF_BIN" == */* ]]; then
  PERF_BIN=$(canonical_path "$PERF_BIN")
else
  PERF_BIN=$(command -v "$PERF_BIN") || die "perf executable not found"
fi
[[ -x "$PERF_BIN" ]] || die "perf executable is not executable: $PERF_BIN"
command -v sha256sum >/dev/null || die "sha256sum is required"
command -v realpath >/dev/null || die "realpath is required"
command -v /usr/bin/time >/dev/null || die "/usr/bin/time is required"

CANONICAL_CORPORA=()
for corpus in "${CORPORA[@]}"; do
  if [[ "$corpus" != /* ]]; then
    corpus="$WORK_DIR/$corpus"
  fi
  corpus="$(canonical_path "$corpus")"
  [[ ! -L "$corpus" ]] || die "corpus paths must not be symlinks: $corpus"
  if [[ -d "$corpus" ]]; then
    corpus_symlink=$(find "$corpus" -mindepth 1 -type l -print -quit)
    [[ -z "$corpus_symlink" ]] ||
      die "corpus trees must not contain symlinks: $corpus_symlink"
  fi
  CANONICAL_CORPORA+=("$corpus")
done

if [[ -n "$EXPECTED_CORPUS_MANIFEST" ]]; then
  EXPECTED_CORPUS_MANIFEST=$(canonical_path "$EXPECTED_CORPUS_MANIFEST")
  cmp "$EXPECTED_CORPUS_MANIFEST" \
    <(emit_corpus_manifest "${CANONICAL_CORPORA[@]}") ||
    die "corpus identity differs from expected manifest"
fi

COMMAND=("$@")
if [[ "${COMMAND[0]}" == */* ]]; then
  if [[ "${COMMAND[0]}" != /* ]]; then
    COMMAND[0]="$WORK_DIR/${COMMAND[0]}"
  fi
  COMMAND[0]=$(canonical_path "${COMMAND[0]}")
else
  COMMAND[0]=$(command -v "${COMMAND[0]}") ||
    die "subject executable not found: ${COMMAND[0]}"
fi
[[ -x "${COMMAND[0]}" ]] ||
  die "subject executable is not executable: ${COMMAND[0]}"

SUBJECT_BINARY_SHA256=$(sha256sum "${COMMAND[0]}" | awk '{print $1}')
BUILD_CACHE_SHA256=$(sha256sum "$BUILD_DIR/CMakeCache.txt" | awk '{print $1}')
BUILD_ARTIFACT_IDENTITY=$(emit_build_artifact_identity)
BUILD_ARTIFACT_IDENTITY_SHA256=$(
  printf '%s\n' "$BUILD_ARTIFACT_IDENTITY" | hash_stream
)
[[ -z "$EXPECTED_BINARY_SHA256" ||
  "$SUBJECT_BINARY_SHA256" == "$EXPECTED_BINARY_SHA256" ]] ||
  die "subject binary differs from the expected SHA-256"
if [[ -n "$EXPECTED_BUILD_ARTIFACTS" ]]; then
  EXPECTED_BUILD_ARTIFACTS=$(canonical_path "$EXPECTED_BUILD_ARTIFACTS")
  cmp "$EXPECTED_BUILD_ARTIFACTS" \
    <(printf '%s\n' "$BUILD_ARTIFACT_IDENTITY") ||
    die "DTVM build artifacts differ from the expected identity"
fi
[[ -z "$EXPECTED_CACHE_SHA256" ||
  "$BUILD_CACHE_SHA256" == "$EXPECTED_CACHE_SHA256" ]] ||
  die "CMake cache differs from the expected SHA-256"

UNTRACKED_STATUS=$(
  GIT_OPTIONAL_LOCKS=0 git -C "$REPO" ls-files --others --exclude-standard
)
if [[ -n "$UNTRACKED_STATUS" ]]; then
  die "untracked source files are not supported; commit, ignore, or remove them"
fi
DIRTY_SUBMODULES=$(dirty_submodules "$REPO")
[[ -z "$DIRTY_SUBMODULES" ]] ||
  die "dirty submodules are not supported: $DIRTY_SUBMODULES"
TRACKED_STATUS=$(
  GIT_OPTIONAL_LOCKS=0 git -C "$REPO" status --porcelain=v1 --untracked-files=no \
    --ignore-submodules=none
)
if [[ -n "$TRACKED_STATUS" && "$ALLOW_DIRTY" != true ]]; then
  die "tracked source or submodules are dirty; commit first or use --allow-dirty"
fi
SOURCE_PATCH_SHA256=$(
  GIT_OPTIONAL_LOCKS=0 git -C "$REPO" diff --binary HEAD | hash_stream
)
if [[ -n "$EXPECTED_SOURCE_STATUS" ]]; then
  EXPECTED_SOURCE_STATUS=$(canonical_path "$EXPECTED_SOURCE_STATUS")
  cmp "$EXPECTED_SOURCE_STATUS" <(printf '%s\n' "$TRACKED_STATUS") ||
    die "tracked source status differs from expected status"
fi
[[ -z "$EXPECTED_SOURCE_PATCH_SHA256" ||
  "$SOURCE_PATCH_SHA256" == "$EXPECTED_SOURCE_PATCH_SHA256" ]] ||
  die "tracked source patch differs from the expected SHA-256"

if [[ -e "$OUTPUT_DIR" ]]; then
  die "output path already exists: $OUTPUT_DIR"
fi

printf 'repo=%s\n' "$REPO"
printf 'build_dir=%s\n' "$BUILD_DIR"
printf 'work_dir=%s\n' "$WORK_DIR"
printf 'perf=%s\n' "$PERF_BIN"
printf 'event=%s\n' "$EVENT"
printf 'frequency=%s\n' "$FREQUENCY"
printf 'call_graph=%s\n' "$CALL_GRAPH"
printf 'output_dir=%s\n' "$OUTPUT_DIR"
printf 'allow_dirty=%s\n' "$ALLOW_DIRTY"
printf 'source_commit=%s\n' "$SOURCE_COMMIT"
printf 'source_patch_sha256=%s\n' "$SOURCE_PATCH_SHA256"
printf 'subject_binary_sha256=%s\n' "$SUBJECT_BINARY_SHA256"
printf 'build_artifact_identity_sha256=%s\n' \
  "$BUILD_ARTIFACT_IDENTITY_SHA256"
printf 'build_cache_sha256=%s\n' "$BUILD_CACHE_SHA256"
if [[ -n "$EXPECTED_CORPUS_MANIFEST" ]]; then
  printf 'expected_corpus_manifest=%s\n' "$EXPECTED_CORPUS_MANIFEST"
fi
if [[ -n "$EXPECTED_BUILD_ARTIFACTS" ]]; then
  printf 'expected_build_artifacts=%s\n' "$EXPECTED_BUILD_ARTIFACTS"
fi
printf 'corpus=\n'
printf '  %s\n' "${CANONICAL_CORPORA[@]}"
printf 'command='
quote_command "${COMMAND[@]}"

if [[ "$DRY_RUN" == true ]]; then
  printf 'dry_run=validated; no files written\n'
  exit 0
fi

mkdir -p "$(dirname "$OUTPUT_DIR")"
mkdir "$OUTPUT_DIR"
OUTPUT_DIR=$(canonical_dir "$OUTPUT_DIR")
mkdir "$OUTPUT_DIR/metadata" "$OUTPUT_DIR/jit"
BUNDLE_COMPLETE=false

finish() {
  local rc=$?
  if [[ "$BUNDLE_COMPLETE" != true ]]; then
    {
      printf 'status=failed\n'
      printf 'exit_code=%d\n' "$rc"
    } >"$OUTPUT_DIR/status.txt"
  fi
}
trap finish EXIT

PROFILE_SCRIPT_DIR=$(
  cd "$(dirname "${BASH_SOURCE[0]}")"
  pwd -P
)
PROFILE_SCRIPT_PATH="$PROFILE_SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
PROFILE_SCRIPT_SHA256=$(sha256sum "$PROFILE_SCRIPT_PATH" | awk '{print $1}')

{
  printf 'created_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'repo=%s\n' "$REPO"
  printf 'source_commit=%s\n' "$SOURCE_COMMIT"
  printf 'source_branch=%s\n' \
    "$(git -C "$REPO" symbolic-ref --quiet --short HEAD || printf 'detached')"
  printf 'source_clean=%s\n' "$([[ -z "$TRACKED_STATUS" ]] && printf true || printf false)"
  printf 'build_dir=%s\n' "$BUILD_DIR"
  printf 'build_cache_sha256=%s\n' "$BUILD_CACHE_SHA256"
  printf 'subject_binary=%s\n' "${COMMAND[0]}"
  printf 'subject_binary_sha256=%s\n' "$SUBJECT_BINARY_SHA256"
  printf 'build_artifact_identity_sha256=%s\n' \
    "$BUILD_ARTIFACT_IDENTITY_SHA256"
  printf 'profile_script_sha256=%s\n' "$PROFILE_SCRIPT_SHA256"
  printf 'work_dir=%s\n' "$WORK_DIR"
  printf 'perf=%s\n' "$PERF_BIN"
  printf 'event=%s\n' "$EVENT"
  printf 'frequency=%s\n' "$FREQUENCY"
  printf 'call_graph=%s\n' "$CALL_GRAPH"
  printf 'command_sha256=%s\n' "$(quote_command "${COMMAND[@]}" | hash_stream)"
} >"$OUTPUT_DIR/metadata/identity.txt"

printf '%s\n' "$TRACKED_STATUS" >"$OUTPUT_DIR/metadata/source-status.txt"
git -C "$REPO" submodule status --recursive \
  >"$OUTPUT_DIR/metadata/submodules.txt"
git -C "$REPO" diff --binary HEAD >"$OUTPUT_DIR/metadata/source.patch"
WRITTEN_SOURCE_PATCH_SHA256=$(
  sha256sum "$OUTPUT_DIR/metadata/source.patch" | awk '{print $1}'
)
[[ "$WRITTEN_SOURCE_PATCH_SHA256" == "$SOURCE_PATCH_SHA256" ]] ||
  die "tracked source changed while the evidence bundle was being created"
cp "$BUILD_DIR/CMakeCache.txt" "$OUTPUT_DIR/metadata/CMakeCache.txt"
if [[ -f "$BUILD_DIR/compile_commands.json" ]]; then
  sha256sum "$BUILD_DIR/compile_commands.json" \
    >"$OUTPUT_DIR/metadata/compile_commands.sha256"
fi
uname -a >"$OUTPUT_DIR/metadata/uname.txt"
"$PERF_BIN" version >"$OUTPUT_DIR/metadata/perf-version.txt"
quote_command "${COMMAND[@]}" >"$OUTPUT_DIR/metadata/command.txt"

write_corpus_manifest "$OUTPUT_DIR/metadata/corpus.before.sha256" \
  "${CANONICAL_CORPORA[@]}"
printf 'corpus_manifest_sha256=%s\n' \
  "$(sha256sum "$OUTPUT_DIR/metadata/corpus.before.sha256" | awk '{print $1}')" \
  >>"$OUTPUT_DIR/metadata/identity.txt"
printf 'source_patch_sha256=%s\n' \
  "$(sha256sum "$OUTPUT_DIR/metadata/source.patch" | awk '{print $1}')" \
  >>"$OUTPUT_DIR/metadata/identity.txt"

printf '%s\n' "$BUILD_ARTIFACT_IDENTITY" \
  >"$OUTPUT_DIR/metadata/build-artifacts.identity"
emit_build_artifact_hashes \
  >"$OUTPUT_DIR/metadata/build-artifacts.sha256"

find "$WORK_DIR" -maxdepth 1 -type f -name 'jit-*.dump' -print0 |
  sort -z |
  while IFS= read -r -d '' item; do
    sha256sum "$item"
  done >"$OUTPUT_DIR/metadata/jit.before.sha256"

cp "$PROFILE_SCRIPT_PATH" "$OUTPUT_DIR/metadata/profile_cold_compile.sh"
chmod +x "$OUTPUT_DIR/metadata/profile_cold_compile.sh"
{
  printf '#!/usr/bin/env bash\nset -euo pipefail\n'
  printf '%s\n' 'BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"'
  printf '%s\n' \
    '(cd "$BUNDLE_DIR" && sha256sum -c manifest.sha256 >/dev/null)'
  printf 'exec "$BUNDLE_DIR/metadata/profile_cold_compile.sh"'
  printf ' %q %q' --repo "$REPO"
  printf ' %q %q' --build-dir "$BUILD_DIR"
  printf ' %q %q' --work-dir "$WORK_DIR"
  printf ' %q %q' --perf "$PERF_BIN"
  printf ' %q %q' --event "$EVENT"
  printf ' %q %q' --frequency "$FREQUENCY"
  printf ' %q %q' --call-graph "$CALL_GRAPH"
  for corpus in "${CANONICAL_CORPORA[@]}"; do
    printf ' %q %q' --corpus "$corpus"
  done
  printf ' %q %q' --expect-binary-sha256 "$SUBJECT_BINARY_SHA256"
  printf ' --expect-build-artifacts'
  printf ' "$BUNDLE_DIR/metadata/build-artifacts.identity"'
  printf ' %q %q' --expect-cache-sha256 "$BUILD_CACHE_SHA256"
  printf ' %q %q' --expect-source-commit "$SOURCE_COMMIT"
  printf ' --expect-source-status "$BUNDLE_DIR/metadata/source-status.txt"'
  printf ' %q %q' --expect-source-patch-sha256 "$SOURCE_PATCH_SHA256"
  printf ' --expect-corpus-manifest "$BUNDLE_DIR/metadata/corpus.before.sha256"'
  if [[ "$ALLOW_DIRTY" == true ]]; then
    printf ' %q' --allow-dirty
  fi
  printf ' --output-dir "${1:?provide a new output directory}" --'
  printf ' %q' "${COMMAND[@]}"
  printf '\n'
} >"$OUTPUT_DIR/rerun-profile.sh"
chmod +x "$OUTPUT_DIR/rerun-profile.sh"

PERF_DATA="$OUTPUT_DIR/perf.data"
PERF_JIT_DATA="$OUTPUT_DIR/perf.jit.data"
TIMING="$OUTPUT_DIR/timing.txt"
RUN_LOG="$OUTPUT_DIR/perf-record.log"

(
  cd "$WORK_DIR"
  /usr/bin/time -f \
    'wall_seconds=%e\nuser_seconds=%U\nsystem_seconds=%S\nmax_rss_kb=%M\nexit_status=%x' \
    -o "$TIMING" \
    "$PERF_BIN" record \
    --event "$EVENT" \
    --freq "$FREQUENCY" \
    --call-graph "$CALL_GRAPH" \
    --output "$PERF_DATA" \
    -- "${COMMAND[@]}"
) 2>&1 | tee "$RUN_LOG"

find "$WORK_DIR" -maxdepth 1 -type f -name 'jit-*.dump' -print0 |
  sort -z |
  while IFS= read -r -d '' item; do
    sha256sum "$item"
  done >"$OUTPUT_DIR/metadata/jit.after.sha256"

while IFS= read -r post_line; do
  [[ -n "$post_line" ]] || continue
  post_hash=${post_line%% *}
  post_path=${post_line#*  }
  if ! grep -Fqx "$post_line" "$OUTPUT_DIR/metadata/jit.before.sha256"; then
    jit_name=$(basename "$post_path")
    cp "$post_path" "$OUTPUT_DIR/jit/${post_hash}-${jit_name}"
  fi
done <"$OUTPUT_DIR/metadata/jit.after.sha256"

REPORT_INPUT="$PERF_DATA"
if find "$OUTPUT_DIR/jit" -type f -name '*jit-*.dump' -print -quit |
  grep -q .; then
  (
    cd "$WORK_DIR"
    "$PERF_BIN" inject --jit --input "$PERF_DATA" --output "$PERF_JIT_DATA"
  )
  REPORT_INPUT="$PERF_JIT_DATA"
fi

"$PERF_BIN" report --input "$REPORT_INPUT" --stdio --no-children \
  --sort=comm,dso,symbol >"$OUTPUT_DIR/perf-report.txt"
"$PERF_BIN" report --input "$REPORT_INPUT" --stdio --no-children \
  --sort=comm >"$OUTPUT_DIR/perf-report-comm.txt"

{
  printf '# Inherited child-process signals from perf report\n'
  grep -Ei \
    'objdump|llvm-objdump|(^|[^[:alnum:]_])(ld|lld|as|sh|bash|c\\+\\+filt)([^[:alnum:]_]|$)' \
    "$OUTPUT_DIR/perf-report.txt" || true
} >"$OUTPUT_DIR/child-process-signals.txt"

write_corpus_manifest "$OUTPUT_DIR/metadata/corpus.after.sha256" \
  "${CANONICAL_CORPORA[@]}"
cmp "$OUTPUT_DIR/metadata/corpus.before.sha256" \
  "$OUTPUT_DIR/metadata/corpus.after.sha256"

POST_STATUS=$(
  GIT_OPTIONAL_LOCKS=0 git -C "$REPO" status --porcelain=v1 --untracked-files=no \
    --ignore-submodules=none
)
[[ "$POST_STATUS" == "$TRACKED_STATUS" ]] ||
  die "tracked source state changed during profiling"
POST_SOURCE_COMMIT=$(GIT_OPTIONAL_LOCKS=0 git -C "$REPO" rev-parse HEAD)
[[ "$POST_SOURCE_COMMIT" == "$SOURCE_COMMIT" ]] ||
  die "source commit changed during profiling"
POST_SOURCE_PATCH_SHA256=$(
  GIT_OPTIONAL_LOCKS=0 git -C "$REPO" diff --binary HEAD | hash_stream
)
[[ "$POST_SOURCE_PATCH_SHA256" == "$SOURCE_PATCH_SHA256" ]] ||
  die "tracked source patch changed during profiling"
POST_DIRTY_SUBMODULES=$(dirty_submodules "$REPO")
[[ -z "$POST_DIRTY_SUBMODULES" ]] ||
  die "a submodule became dirty during profiling: $POST_DIRTY_SUBMODULES"
POST_UNTRACKED_STATUS=$(
  GIT_OPTIONAL_LOCKS=0 git -C "$REPO" ls-files --others --exclude-standard
)
[[ -z "$POST_UNTRACKED_STATUS" ]] ||
  die "untracked source files appeared during profiling"
CURRENT_BINARY_HASH=$(sha256sum "${COMMAND[0]}" | awk '{print $1}')
[[ "$CURRENT_BINARY_HASH" == "$SUBJECT_BINARY_SHA256" ]] ||
  die "subject binary changed during profiling"
cmp "$OUTPUT_DIR/metadata/build-artifacts.identity" \
  <(emit_build_artifact_identity) ||
  die "DTVM build artifacts changed during profiling"
CURRENT_CACHE_HASH=$(sha256sum "$BUILD_DIR/CMakeCache.txt" | awk '{print $1}')
[[ "$CURRENT_CACHE_HASH" == "$BUILD_CACHE_SHA256" ]] ||
  die "CMake cache changed during profiling"

printf 'status=complete\n' >"$OUTPUT_DIR/status.txt"
(
  cd "$OUTPUT_DIR"
  find . -type f ! -name manifest.sha256 -print0 |
    sort -z |
    xargs -0 sha256sum >manifest.sha256
)

BUNDLE_COMPLETE=true
printf 'bundle=%s\n' "$OUTPUT_DIR"
printf 'report_input=%s\n' "$REPORT_INPUT"
