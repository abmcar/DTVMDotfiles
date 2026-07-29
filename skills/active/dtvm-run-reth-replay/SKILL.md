---
name: dtvm-run-reth-replay
description: Operate a maintainable DTVM–Reth replay workflow from exact endpoint readiness through a frozen finalized-tail or explicit fixed-range block capture, offline strict DTVM replay, and checksummed evidence sealing. Use when Codex must validate primary/standby Reth witness endpoints, capture or resume current or historical canonical blocks with execution witnesses, diagnose HA RPC or quorum failures, replay a frozen corpus without network time, or seal reusable DTVM replay evidence.
---

# Run a frozen DTVM–Reth replay

Keep the production chain split explicit: self-hosted Reth primary and standby
produce witnesses; a standard provider may contribute canonical quorum but
never substitutes for `debug_executionWitnessByBlockHash(hash, "canonical")`.
Fail closed if exact capability or canonical identity cannot be proved.

## Restore the versioned suite

Treat this skill directory as the source of truth for the versioned 30-file
adapter slice. The experiment adapter is a restored working copy, not an
editable source. From a clean DTVMDotfiles checkout, restore that slice into a
new directory:

```bash
bash "$SKILL_ROOT/scripts/restore-reth-replay-suite.sh" install "$TARGET"
bash "$SKILL_ROOT/scripts/restore-reth-replay-suite.sh" check "$TARGET"
bash "$SKILL_ROOT/scripts/verify-hermetic-suite.sh" "$TARGET"
export DTVM_RETH_SUITE_ROOT="$TARGET"
```

For an existing disposable adapter working copy, use `sync` and then `check`.
Both modes preflight
[assets/reth-replay-suite.sha256](assets/reth-replay-suite.sha256), reject
symlinked paths, require the exact unique 30-file allowlist, reject unlisted
files that could affect execution, and require byte equality.
Maintain the client and validator under `scripts/`, operational source under
`assets/witness-db-suite/`, config/schema under `assets/`, and the operations
guide under `references/`. Refresh the manifest whenever a listed SSOT file
changes; never patch the restored adapter first.

The slice is not a standalone Rust dependency closure. `Cargo.toml` also
requires the frozen experiment's parent adapter, `reth-transaction`, and Reth
source tree. Run Rust build/test only in that complete frozen layout and report
it blocked when those dependencies or the pinned toolchain are absent. Never
describe the script-only validation hook as a Rust build gate.

## Resolve inputs without exposing secrets

Require these inputs:

| Input | Contract |
|---|---|
| `DTVM_RETH_SUITE_ROOT` | Manifest-verified restored directory containing `reth_rpc_ha.py`, `capture-window.sh`, and `fetch-witness.sh` |
| `RETH_RPC_HA_CONFIG` | Secret-free v1 config; endpoint fields name environment variables only |
| endpoint URL/header variables | Values named by the config; inspect presence only |
| `DTVM_RETH_OUTPUT` | New final corpus path |
| `DTVM_RETH_STATE_DIR` | Private durable resume/metrics/seal directory |
| fixed-range selection | Set both `DTVM_RETH_START_BLOCK` and `DTVM_RETH_END_BLOCK`; unset both for finalized-tail mode |
| pruned-genesis policy | Keep `expectedChain.genesisPolicy` at `require-block` unless an exact fixed range is served by Reth nodes that return error code `4444` for block zero; only then set `allow-reth-pruned-history` |
| `DTVM_IDENTITY_MANIFEST` | Frozen DTVM source-identity manifest |
| `DTVM_REPLAYER_MANIFEST` | Sealed approval whose replayer realpath and SHA-256 are required at capture, replay, and seal |
| replay inputs | `DTVM_VERIFY_CORPUS_SCRIPT`, `DTVM_VERIFY_CORPUS_SHA256`, `DTVM_LIBRARY`, `DTVM_LIBRARY_SHA256`, `DTVM_REPLAY_OUTPUT`, and `DTVM_REPLAY_LABEL` |

Never print, persist, interpolate into a command transcript, or report the
value of a URL, token, authorization header, cookie, or provider header. Do not
put endpoint values in the config. Preserve `PYTHONDONTWRITEBYTECODE=1`.

Read [references/endpoint-policy.md](references/endpoint-policy.md) when
choosing endpoint roles, sizing nodes, classifying a failure, or recovering a
resume. Copy [assets/reth-rpc-ha.example.json](assets/reth-rpc-ha.example.json)
as the secret-free configuration template.

## Run the four phases

Resolve the absolute directory containing this `SKILL.md` as `SKILL_ROOT`;
never assume the current working directory is the skill directory. Use
[scripts/run-frozen-replay.sh](scripts/run-frozen-replay.sh); it keeps
network capture and offline replay as separate processes.

1. Run `readiness`. Require exact chain ID and genesis, `eth_syncing == false`,
   two exact witness-ready Reth roles, and either one finalized number/hash
   quorum or a quorum-frozen ordered fixed range. The default requires the
   genesis block over RPC. Exact fixed-range mode may instead accept Reth error
   code `4444` only when `expectedChain.genesisPolicy` explicitly selects
   `allow-reth-pruned-history`; it still requires Mainnet chain ID, quorum for
   every requested number/hash, and both boundary witness probes. Never apply
   that exception to finalized-tail readiness.
   Treat `-32601`, `-32602`, malformed responses, chain mismatch, genesis
   mismatch, syncing, hash drift, and quorum disagreement as not ready.
2. Run `capture`. In finalized-tail mode, freeze `finalized`. In fixed-range
   mode, require explicit decimal start/end/count, freeze every ordered
   height/hash before capture, and never resolve a moving tag. Use the same
   `capture-window.sh`, verify each bundle, recheck every height, and publish
   only with an atomic no-replace directory rename. Resume only with a matching
   config fingerprint, selection, output and frozen identity.
3. Run `replay`. Stop the gateway first. Remove all configured RPC variables
   from the replay child and require the fail-closed libseccomp launcher to
   deny socket and io_uring network paths. Require strict raw-block/witness
   verification and all DTVM/Reth differential commitments. Bind the report's
   manifest SHA-256, block count, and every block
   number/hash/bundle path/bundle SHA-256 to the frozen capture. Keep replay
   wall time explicitly disqualified from any conclusion that includes
   network capture.
4. Run `seal`. Bind the capture manifest, bundle-set checksums, resume state,
   replay runner and hash, capture-approved replayer binary, verified DTVM
   library and hash, metrics and strict replay result. Require
   `credentialsRecorded == false`. Re-running `seal` must verify and return the
   existing sealed evidence byte-for-byte without rewriting it.

Run one phase:

```bash
bash "$SKILL_ROOT/scripts/run-frozen-replay.sh" readiness
bash "$SKILL_ROOT/scripts/run-frozen-replay.sh" capture
bash "$SKILL_ROOT/scripts/run-frozen-replay.sh" replay
bash "$SKILL_ROOT/scripts/run-frozen-replay.sh" seal
```

For an exact historical range, set both bounds for every readiness/capture
invocation and keep them set for `all`:

```bash
export DTVM_RETH_START_BLOCK=25625000
export DTVM_RETH_END_BLOCK=25625015
export DTVM_RETH_BLOCK_COUNT=16
bash "$SKILL_ROOT/scripts/run-frozen-replay.sh" readiness
bash "$SKILL_ROOT/scripts/run-frozen-replay.sh" capture
```

Unset both bound variables for the backward-compatible finalized-tail v1
workflow. Setting only one bound fails before the HA client runs.

Run the complete sequence with `all` only after all replay inputs exist:

```bash
bash "$SKILL_ROOT/scripts/run-frozen-replay.sh" all
```

## Enforce hard gates

Do not continue or weaken checks when any gate fails:

- Use the hard-coded Mainnet chain ID and genesis hash exactly.
- Keep genesis policy fail-closed by default. Permit Reth's exact pruned-history
  error code `4444` only for an explicit fixed range with
  `allow-reth-pruned-history`; do not accept another code, an invalid block, a
  missing result, or the exception in finalized-tail mode.
- Require one primary plus at least one standby self-hosted Reth.
- Require the exact by-hash canonical witness response on both witness roles.
- Require the sealed approved-replayer manifest and keep its binary realpath
  and SHA-256 continuous through capture, replay report, and seal.
- Never use `eth_getProof`, a number-addressed witness, or a standard provider
  as the production witness source.
- Require at least two matching canonical sources for pin and every height.
- Reject a parent discontinuity, missing height, changed frozen hash, malformed
  result, partial public output, any symlinked corpus path component, or
  checksum mismatch.
- Preserve the existing v1 capture manifest fields and one high-level fetch per
  hash per whole-window attempt. Dispatch fixed capture only through
  `reth-dtvm.atomic-fixed-range-capture.v1`; never reinterpret that schema as
  finalized v1.
- Keep retries bounded. Retry 429 with bounded `Retry-After`; retry/fail over
  timeout, transport and 5xx. Readiness and quorum retry one endpoint within
  budget before recording its single vote; stop authentication and identity
  failures.
- Normalize endpoint origins without DNS lookup, including legacy numeric IPv4
  spellings. Normalize configured header names to lowercase, reject
  case-insensitive duplicates and framing/hop-by-hop headers, and reject
  explicit Authorization combined with URL userinfo.
- Serialize capture, replay and seal on the state-directory workflow lock.
- Require `libseccomp.so.2`; fail with
  `offline_network_isolation_unavailable` unless a filtered probe can run pure
  computation while AF_INET and AF_INET6 socket creation both return EPERM.
  Require every current-architecture socket and io_uring syscall name to
  resolve; only architecture-specific `socketcall` may be absent. Bind the
  launcher realpath, SHA-256, resolved denied socket syscalls, and denied
  `io_uring_setup`, `io_uring_enter`, and `io_uring_register` to state and seal.
- Keep the final corpus no-overwrite and atomically published with Linux
  `RENAME_NOREPLACE`; fail closed when that primitive is unavailable.
- Exclude network acquisition and readiness time from DTVM performance.
- Require strict replay success plus manifest/identity continuity before
  calling the evidence complete.

## Recover from interruption

Reuse the same config, output, state directory and selection. The finalized
state machine revalidates its frozen pin. The fixed-range v2 state machine
revalidates its complete ordered height/hash vector and readiness checksum;
neither schema may resume the other. Both require the configured quorum and
reuse only checksummed immutable hash-addressed cache entries. A
corrupt/truncated cache entry is ignored and atomically replaced.

The workflow lock is non-blocking: another capture, replay, or seal using the
same state directory returns `workflow_already_running`. After a successful
seal, retry only with the same state directory and inputs; the sealed fast path
revalidates every input, pre-seal continuity, state checksum, report identity,
and seal bytes before returning the existing document.

If the config fingerprint, count, output, selection mode or fixed bound changes,
start a new state directory. If any frozen hash loses quorum or has reorged, do
not rewrite the old state into a new claim; preserve it for diagnosis and start
a new capture identity. Use an archive Reth when the resume may fall outside a
full node's recent witness history window.

## Verify before handoff

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 bash \
  "$SKILL_ROOT/scripts/verify-hermetic-suite.sh" "$DTVM_RETH_SUITE_ROOT"
PYTHONDONTWRITEBYTECODE=1 python3 \
  "$DTVM_RETH_SUITE_ROOT/tests/reth_rpc_ha_test.py"
bash "$DTVM_RETH_SUITE_ROOT/tests/capture-window.sh"
bash "$DTVM_RETH_SUITE_ROOT/tests/fetch-witness.sh"
bash "$DTVM_RETH_SUITE_ROOT/tests/replay-tip.sh"
PYTHONDONTWRITEBYTECODE=1 python3 \
  "$SKILL_ROOT/scripts/validate-replay-state.py" "$DTVM_RETH_STATE_DIR"
```

For this skill's SSOT, also run the `skill-creator` quick validator and the
DTVMDotfiles read-only skill validation hook. Do not run `release.sh` as a
validation command. If the shared validation infrastructure and its hook
registry are not merged into the current baseline, run the hook directly,
report that publication integration is pending, and do not claim the shared
gate passed. Keep skill source and any skill commit only in DTVMDotfiles. Keep
the DTVM index untouched and never stage generated `AGENTS.md`.

Report the official capability conclusion, suite/config paths, test counts,
whether the external Rust dependency/toolchain gate actually ran, real endpoint
readiness, output/state/seal paths, and the exact next command. If endpoints
are absent, state that capture is externally blocked and list only the missing
endpoint roles or environment-variable names.
