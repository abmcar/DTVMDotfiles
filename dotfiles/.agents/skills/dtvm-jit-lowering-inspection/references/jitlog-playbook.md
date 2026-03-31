# DTVM Multipass JIT Log Playbook

## Build a Logging Variant

Use a separate build directory to avoid polluting the performance build:

```bash
cmake -S . -B build-jitlog \
  -DCMAKE_BUILD_TYPE=Debug \
  -DZEN_ENABLE_MULTIPASS_JIT=ON \
  -DZEN_ENABLE_SINGLEPASS_JIT=OFF \
  -DZEN_ENABLE_EVM=ON \
  -DZEN_ENABLE_LIBEVM=ON \
  -DZEN_ENABLE_SPEC_TEST=OFF \
  -DZEN_ENABLE_JIT_LOGGING=ON \
  -DFETCHCONTENT_SOURCE_DIR_spdlog=<perf-build>/_deps/spdlog-src \
  -DFETCHCONTENT_SOURCE_DIR_cli11=<perf-build>/_deps/cli11-src \
  -DFETCHCONTENT_SOURCE_DIR_intx=<perf-build>/_deps/intx-src \
  -DFETCHCONTENT_SOURCE_DIR_rapidjson=<perf-build>/_deps/rapidjson-src \
  -G Ninja
cmake --build build-jitlog -j$(nproc) --target dtvmapi
```

## Capture One EVM Case

Example for one `single-mul` style case:

```bash
LOG=/tmp/dtvm-case-jitlog.txt
/home/abmcar/evmone-bench/build/bin/evmc \
  --vm /home/abmcar/DTVM/build-jitlog/lib/libdtvmapi.so,mode=multipass \
  run <bytecode> \
  --input <hex> \
  > "$LOG" 2>&1
```

## Useful Searches

Quick counts:

```bash
rg -n "Frame Objects:|MULX64rr|ADCX64rr|ADOX64rr|%stack\\.|COPY" "$LOG"
```

Focused comparison script:

```bash
python3 - <<'PY'
from pathlib import Path
text = Path("/tmp/dtvm-case-jitlog.txt").read_text(errors="replace").splitlines()
print("frame_objects", sum(1 for line in text if line.strip().startswith("fi#")))
print("stack_moves", sum(1 for line in text if "MOV64mr %stack." in line or "MOV64rm %stack." in line))
print("mulx", sum(1 for line in text if "MULX64rr" in line))
print("adx_ops", sum(1 for line in text if "ADCX64rr" in line or "ADOX64rr" in line))
PY
```

## Interpretation Shortcut

- Large spill reduction plus loop benchmark improvement: keep the change.
- Similar spill profile plus noisy benchmark delta: do not keep the change.
- More spills after a schedule rewrite: revert quickly and stop guessing.
