## 1. Baseline and triage
- [x] 1.1 Re-run Cancun static state tests in multipass and capture a baseline failure list.
- [x] 1.2 Summarize failures by suite and select representative failing cases for each top cluster (static call/precompile, wallet, random, SSTORE/logs).
- [x] 1.3 Run the same representative cases in interpreter mode to confirm expected behavior and provide a comparison baseline.

## 2. Static call and precompile parity
- [x] 2.1 Trace multipass execution for representative static call/precompile failures and compare gas usage, return data, and state updates.
- [x] 2.2 Fix mismatches in static call/precompile handling for Cancun and validate the representative subset.
- [x] 2.3 Expand validation to the full `stStaticCall` and `stPreCompiledContracts2` suites.

## 3. SSTORE and log hashing parity
- [x] 3.1 Investigate `stSStoreTest`, `stLogTests`, and log hash mismatches in random tests to identify the first divergence point.
- [x] 3.2 Fix Cancun SSTORE gas/refund or log emission differences in multipass and validate representative cases.
- [x] 3.3 Re-run the full `stSStoreTest` and `stLogTests` suites.

## 4. Wallet and random test stabilization
- [x] 4.1 Investigate `stWalletTest` failures and map them to opcode/host behavior differences.
- [x] 4.2 Fix the highest-frequency root cause and validate a larger wallet subset.
- [x] 4.3 Triage remaining `stRandom`/`stRandom2` failures and address the dominant mismatch.

## 5. Full regression and exit criteria
- [x] 5.1 Re-run all Cancun static state tests in multipass.
- [x] 5.2 Ensure failure count reaches zero (or record remaining blockers with a follow-up plan).
- [x] 5.3 Run format check and document the final test results.
