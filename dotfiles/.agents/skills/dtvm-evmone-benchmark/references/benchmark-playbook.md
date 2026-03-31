# DTVM EVM evmone Benchmark Playbook

## Canonical Paths

| Resource | Path |
|----------|------|
| evmone binary | `/home/abmcar/evmone-bench/build/bin/evmone-bench` |
| benchmark suite | `/home/abmcar/evmone-bench/test/evm-benchmarks/benchmarks` |
| baseline lib | `/home/abmcar/dtvm-baseline/build-baseline/lib/libdtvmapi.so` |
| feature lib | `/home/abmcar/DTVM/build/lib/libdtvmapi.so` |

`/home/abmcar/evmone-bench` is a symlink to `evmone-for-test-mulx-adx`.
`/home/abmcar/dtvm-baseline` is a persistent git worktree tracking `upstream/main`.

## Before/After Comparison Workflow

### 1. Refresh baseline to latest upstream/main

```bash
git -C /home/abmcar/dtvm-baseline fetch upstream
git -C /home/abmcar/dtvm-baseline checkout upstream/main
```

Rebuild baseline only if upstream/main changed since last build:

```bash
cmake --build /home/abmcar/dtvm-baseline/build-baseline --target dtvmapi -j$(nproc)
```

### 2. Build feature branch

```bash
cmake --build /home/abmcar/DTVM/build --target dtvmapi -j$(nproc)
```

### 3. Run both

```bash
BENCH=/home/abmcar/evmone-bench/build/bin/evmone-bench
SUITE=/home/abmcar/evmone-bench/test/evm-benchmarks/benchmarks
FILTER="--benchmark_filter='^external/total/(main|micro)/'"
REPS="--benchmark_repetitions=3 --benchmark_report_aggregates_only=true"
FMT="--benchmark_format=json"

$BENCH "/home/abmcar/dtvm-baseline/build-baseline/lib/libdtvmapi.so,mode=multipass,enable_gas_metering=true" \
  $SUITE $FILTER $REPS $FMT > /tmp/bench_baseline.json

$BENCH "/home/abmcar/DTVM/build/lib/libdtvmapi.so,mode=multipass,enable_gas_metering=true" \
  $SUITE $FILTER $REPS $FMT > /tmp/bench_feature.json
```

## Single-Run Commands

Standard run (feature branch):

```bash
/home/abmcar/evmone-bench/build/bin/evmone-bench \
  "/home/abmcar/DTVM/build/lib/libdtvmapi.so,mode=multipass,enable_gas_metering=true" \
  /home/abmcar/evmone-bench/test/evm-benchmarks/benchmarks
```

Interpreter variant:

```bash
/home/abmcar/evmone-bench/build/bin/evmone-bench \
  "/home/abmcar/DTVM/build/lib/libdtvmapi.so,mode=interpreter,enable_gas_metering=true" \
  /home/abmcar/evmone-bench/test/evm-benchmarks/benchmarks
```

External total sweep (single rep):

```bash
/home/abmcar/evmone-bench/build/bin/evmone-bench \
  "/home/abmcar/DTVM/build/lib/libdtvmapi.so,mode=multipass,enable_gas_metering=true" \
  /home/abmcar/evmone-bench/test/evm-benchmarks/benchmarks \
  --benchmark_filter='^external/total/(main|micro)/' \
  --benchmark_repetitions=1
```

## EVMC VM String Rules

- Format: `"/path/to/libdtvmapi.so,mode=multipass,enable_gas_metering=true"`
- `mode` must be `multipass` or `interpreter`
- `enable_gas_metering` uses an underscore
- The VM string is the first positional argument to `evmone-bench`

## When To Use Something Else

- Use `evmc run --bench` only for one-off custom bytecode timing, not as the
  default answer for "how do I use evmone benchmark with DTVM?"
- If a repo-local helper exists for a custom microbench, verify that it is
  present before recommending it.

## Common Failure Modes

- Using `enable-evm-gas` instead of `enable_gas_metering`
- Forgetting to rebuild `libdtvmapi.so` before benchmarking
- Pointing the suite path at the wrong evmone checkout
- Using a stale evmone binary from another experiment
- Passing `--benchmark_min_time=0.001` without a unit suffix; use `0.001s`
- JSON output末尾可能缺 `]\n}` — 解析前手动补全
