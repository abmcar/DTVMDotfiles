# Endpoint and recovery policy

## Endpoint roles

- Configure exactly one `witness-primary` and at least one
  `witness-standby`. Run Reth v2.1.0 or newer and expose `eth,debug`.
- Configure a `canonical-aux` from a different operational failure domain when
  available. It needs only standard chain/block RPC.
- Require two witness-ready roles at startup and at least two matching
  canonical votes. Two Reth nodes plus one auxiliary preserve capture only
  when the auxiliary fails before readiness, or one Reth fails after readiness
  has already proved both witness roles. Tolerating any Reth loss before cold
  start or resume requires three witness-capable Reth nodes; add an independent
  auxiliary for a separate canonical failure domain.
- Never infer witness support from `rpc_modules`, a general Debug API product,
  or standard `eth_*`. Probe the exact finalized-hash call with `"canonical"`.

`"canonical"` selects the witness construction mode. It does not enforce that
the block hash remains on the canonical chain. Always freeze and recheck the
height/hash separately.

## Failure classification

| Category | Recovery |
|---|---|
| `rate_limited` | Honor bounded `Retry-After`, exponential backoff and jitter |
| `upstream_5xx`, `timeout`, `transport_error` | Retry idempotent read within budget, then rotate |
| `authentication_failed` | Stop immediately; repair secret/config outside logs |
| `capability_missing` | Do not retry the same method as transient |
| `capability_incompatible` | Upgrade Reth or correct the versioned method |
| `malformed_response`, `response_too_large` | Reject; try one other eligible endpoint |
| `chain_mismatch`, `genesis_mismatch`, `endpoint_syncing` | Remove from readiness |
| `finalized_hash_drift`, `canonical_quorum_disagreement` | Stop the frozen window |
| `canonical_quorum_unavailable` | Stop; restore enough matching endpoint votes |
| bundle/verifier failure | Discard private attempt; retain safe RPC cache/state |
| strict replay mismatch | Preserve capture for diagnosis; do not seal success |

Never turn identity, hash, proof, checksum, or replay failures into a warning.
For readiness and canonical quorum, retry a transient failure on the same
endpoint within the configured bound, then record exactly one success or
failure vote for that endpoint. A retry is never an additional quorum vote.

## Resume boundaries

Resume requires the same public config fingerprint, output, count and state
directory. Revalidate chain/genesis and the frozen numbered hash on every
available eligible source, then require the configured canonical and witness
quorums. Reuse only successful immutable hash-addressed responses whose cache
envelope and result checksum match.

Do not cache numbered-height responses: the final full-window lookup must
observe reorgs. Do not reuse an existing public partial corpus. The final
directory remains no-overwrite and appears only after every bundle and
checksum is complete. On Linux, publish with `renameat2(RENAME_NOREPLACE)`;
an existence check followed by replacement is not an atomic substitute. If
the target wins a race or the primitive is unavailable, retain the private
stage and fail closed without changing the target.

Capture, replay, and seal share the state-directory workflow lock. A repeated
seal is a read-only verification operation: require the original replayed
pre-seal state, unchanged seal inputs, matching sealed-state checksum, and
unchanged seal bytes.

A full Reth node documents a recent 10,064-block historical state window.
Choose archive Reth for recovery or historical capture that may exceed it.

## Secret boundary

Keep endpoint values only in environment variables named by the config.
Optional header variables contain a JSON object of string headers. State,
metrics, readiness, cache entries, manifests, failure JSON and reports may
contain endpoint labels but never values.

Normalize header names to lowercase and reject case-insensitive duplicates.
Reject `Host`, `Content-Length`, `Transfer-Encoding`, `Connection`, and all
other framing or hop-by-hop headers. URL userinfo may supply Basic
Authorization only when no explicit Authorization header is configured.
Normalize literal IP origins, including socket-compatible legacy numeric IPv4
spellings, without resolving ordinary DNS names.

Sanitize configured endpoint variables from capture/replay children. The
capture child receives only the ephemeral loopback gateway. Replay receives no
RPC environment at all. Run replay under the manifest-verified HA launcher
with libseccomp denying socket, socketcall, and io_uring setup/enter/register.
Require every current-architecture socket and io_uring syscall name to resolve;
`socketcall` is optional only on architectures that do not expose it. Fail
closed if the filtered AF_INET and AF_INET6 probes do not return EPERM.

The gateway accepts only the exact capture methods and parameter shapes.
Execution-witness calls must contain a 32-byte hash and `"canonical"`; raw
header/block calls must contain the same hash with `requireCanonical: true`.
Reject all legacy witness shapes even on loopback.

Require a sealed approved-replayer manifest during capture. Revalidate its
manifest and binary hashes before replay and seal, and include the approved
binary in sealed inputs. The strict replay wrapper and DTVM library have
independent expected SHA-256 inputs. Require the replay report to repeat the
approved replayer realpath and SHA-256, capture manifest SHA-256 and block
count, and to match every ordered block number/hash/bundle path/bundle SHA-256
from the capture manifest. Reject missing, stale, or extra corpus identity.

Every evidence path is lexical: reject a symlink in the file itself or in any
ancestor component. Resolving the state/output path before checking it would
erase the evidence of an ancestor symlink and is forbidden.

The restored 30-file adapter slice is not a standalone Cargo dependency
closure. Rust build/test additionally needs the frozen experiment parent
adapter, `reth-transaction`, Reth checkout, and pinned toolchain. Treat their
absence as an external build-gate blocker, not a passing hermetic test.

## Capacity baseline

Start with one sequential window, two Reth nodes plus one canonical auxiliary
when cold-start Reth fault tolerance is not required. Use three Reth nodes plus
an independent auxiliary when capture must start or resume after any one Reth
failure. Begin with pool size 4, 8 requests/second and burst 16. Measure actual
witness latency, body size, Reth CPU/database IO and disk growth before
increasing concurrency.
Alert on readiness, failover, 429, 5xx, timeout, quorum disagreement, corrupt
cache, capture age and free disk.

Use archive nodes only when history requirements justify their storage and
operations cost. A standard provider reduces canonical-source operations but
cannot replace either Reth witness node.

## Official sources

- Reth v2.1.0 debug RPC:
  https://github.com/paradigmxyz/reth/blob/v2.1.0/crates/rpc/rpc-api/src/debug.rs
- Witness mode:
  https://github.com/paradigmxyz/reth/blob/v2.1.0/crates/trie/common/src/execution_witness.rs
- RPC namespaces: https://reth.rs/jsonrpc/intro/
- Pruning/history: https://reth.rs/run/storage/pruning/
- Ethereum JSON-RPC:
  https://ethereum.org/developers/docs/apis/json-rpc/
- EIP-1898: https://eips.ethereum.org/EIPS/eip-1898
- EIP-1186: https://eips.ethereum.org/EIPS/eip-1186
- JSON-RPC errors: https://www.jsonrpc.org/specification
