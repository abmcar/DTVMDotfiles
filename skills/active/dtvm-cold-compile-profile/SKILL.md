---
name: dtvm-cold-compile-profile
description: Seal a reproducible Linux perf evidence bundle for one DTVM cold compilation. Use when locating one-shot JIT compile hotspots, separating DTVM compiler cost from synchronous child tools such as objdump, or producing a baseline for compile-time optimization.
---

# DTVM Cold Compile Profile

Produce a **sealed baseline**: one cold compilation whose source, build, corpus,
command, timing, raw samples, and reports remain auditable together.

## 1. Fix the experiment identity

Use a clean DTVM commit and a configured Release build. Identify the exact
corpus files consumed by the command. Keep the subject command to one process
invocation and one JIT compilation; omit warmups and repeated execution.

Locate this skill and preflight the run:

```bash
SKILL_DIR="<installed-skill-directory>/dtvm-cold-compile-profile"
"$SKILL_DIR/scripts/profile_cold_compile.sh" \
  --dry-run \
  --repo "$REPO_ROOT" \
  --build-dir "$BUILD_DIR" \
  --corpus "$CORPUS" \
  --output-dir "$BUNDLE" \
  -- "$DTVM_BIN" <exact arguments>
```

Pass every independent input with another `--corpus`. Use `--work-dir` when the
command depends on a specific working directory.

Completion criterion: the dry run prints canonical repo, build, corpus,
working-directory, perf, and command identities without creating the bundle.

## 2. Capture the baseline

Run the same command without `--dry-run`:

```bash
"$SKILL_DIR/scripts/profile_cold_compile.sh" \
  --repo "$REPO_ROOT" \
  --build-dir "$BUILD_DIR" \
  --corpus "$CORPUS" \
  --output-dir "$BUNDLE" \
  -- "$DTVM_BIN" <exact arguments>
```

The script refuses to reuse an output path. It records inherited child
processes, retains raw `perf.data`, copies new JIT dumps, injects JIT symbols
when available, bundles its own profiling helper, and writes an integrity
manifest. It rejects untracked source and corpus symlinks. Use `--allow-dirty`
only for tracked-source diagnosis; dirty submodules are rejected because their
contents cannot be sealed by the superproject patch. A dirty run is not an
optimization baseline.

Completion criterion: the command and reports exit zero,
`status.txt` says `complete`, and `manifest.sha256` verifies.

## 3. Separate compiler work from instrumentation

Read:

- `perf-report.txt` for hot symbols and call chains;
- `perf-report-comm.txt` and `child-process-signals.txt` for inherited tools;
- `timing.txt` for wall time;
- `metadata/CMakeCache.txt` for the exact build;
- `metadata/identity.txt`, corpus manifests, the bundled helper, and
  `rerun-profile.sh` for identity-guarded reproduction.

Treat `objdump`, `llvm-objdump`, shells, linkers, and similar commands as child
cost until source proves otherwise. In current DTVM sources,
`ZEN_ENABLE_LINUX_PERF` may couple JIT symbol support to a synchronous assembly
dump. Verify that relationship every run:

```bash
rg -n "ZEN_ENABLE_LINUX_PERF|dumpAsm|objdump" \
  src/compiler/compiler.cpp src/compiler/utils/asm_dump.cpp
```

An objdump-heavy instrumented run can reveal a profiling tax; it does not by
itself measure production compiler cost. Pair later optimization timing with a
production-equivalent build.

Completion criterion: every major sample is classified as DTVM compiler,
inherited child, runtime/loader, kernel, or unresolved.

## 4. Report the evidence

Report:

1. source commit, clean state, and tracked patch identity;
2. binary, CMake cache, corpus, and normalized command hashes;
3. wall time and perf sampling configuration;
4. top symbols with command/DSO;
5. inherited-child share, explicitly including any objdump signal;
6. absolute bundle path and exact rerun command;
7. limitations such as low sample count or instrumentation distortion.

The baseline is complete only when another agent can rerun the bundled helper
while the recorded repo/build/corpus paths still exist unchanged, the identity
checks remain stable, and the raw evidence supports every reported hotspot.
