# DTVM EVM evmone Benchmark Playbook

## Canonical Commands

Rebuild the current library:

```bash
cmake --build build-perf -j$(nproc) --target dtvmapi
```

Standard evmone benchmark command:

```bash
/root/evmone/build/bin/evmone-bench \
  "/root/DTVM/build/lib/libdtvmapi.so,mode=multipass,enable_gas_metering=true" \
  /root/evmone/test/evm-benchmarks/benchmarks
```

Interpreter variant:

```bash
/root/evmone/build/bin/evmone-bench \
  "/root/DTVM/build/lib/libdtvmapi.so,mode=interpreter,enable_gas_metering=true" \
  /root/evmone/test/evm-benchmarks/benchmarks
```

Run external total once:

```bash
/root/evmone/build/bin/evmone-bench \
  "/root/DTVM/build/lib/libdtvmapi.so,mode=multipass,enable_gas_metering=true" \
  /root/evmone/test/evm-benchmarks/benchmarks \
  --benchmark_filter='^external/total/(main|micro)/' \
  --benchmark_repetitions=1
```

Use a local evmone-for-test checkout:

```bash
/home/abmcar/evmone-for-test-topic/build/bin/evmone-bench \
  "/home/abmcar/DTVM-topic/build-perf/lib/libdtvmapi.so,mode=multipass,enable_gas_metering=true" \
  /home/abmcar/evmone-for-test-topic/test/evm-benchmarks/benchmarks
```

## EVMC VM String Rules

- Format:
  `"/path/to/libdtvmapi.so,mode=multipass,enable_gas_metering=true"`
- `mode` must be `multipass` or `interpreter`
- `enable_gas_metering` uses an underscore
- The VM string is the first positional argument to `evmone-bench`

## When To Use Something Else

- Use `evmc run --bench` only for one-off custom bytecode timing, not as the
  default answer for “how do I use evmone benchmark with DTVM?”
- If a repo-local helper exists for a custom microbench, verify that it is
  present before recommending it.

## Common Failure Modes

- Using `enable-evm-gas` instead of `enable_gas_metering`
- Forgetting to rebuild `libdtvmapi.so` before benchmarking
- Pointing the suite path at the wrong evmone checkout
- Using a stale evmone binary from another experiment
- Passing `--benchmark_min_time=0.001` without a unit suffix; use `0.001s`
