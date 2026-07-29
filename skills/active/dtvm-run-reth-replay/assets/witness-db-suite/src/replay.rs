use crate::{WitnessBundle, WitnessDb, WitnessImportError};
use alloy_evm::eth::EthEvmFactory;
use alloy_primitives::B256;
use reth_chainspec::MAINNET;
use reth_consensus::{Consensus, HeaderValidator};
use reth_dtvm_transaction_adapter::DtvmEvmFactory;
use reth_ethereum_consensus::{validate_block_post_execution, EthBeaconConsensus};
use reth_ethereum_primitives::Block;
use reth_evm::execute::{BasicBlockExecutor, Executor};
use reth_evm_ethereum::{revm_spec, EthEvmConfig};
use reth_primitives_traits::{RecoveredBlock, SealedBlock, SealedHeader};
use revm::{database::BundleState, primitives::hardfork::SpecId};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::{
    error::Error,
    ffi::CString,
    fs::File,
    io::{Read, Write},
    os::fd::{AsRawFd, FromRawFd},
    path::{Path, PathBuf},
};
use thiserror::Error;

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PostExecutionCommitments {
    pub gas_used: bool,
    pub receipts_root: bool,
    pub logs_bloom: bool,
    pub requests_hash: bool,
    pub blob_gas_used: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReplayReport {
    pub differential_match: bool,
    pub raw_bound: bool,
    pub pre_execution_commitments: bool,
    pub post_execution_commitments: PostExecutionCommitments,
    pub pre_state_root: B256,
    pub pre_state_root_verified: bool,
    pub post_state_root: B256,
    pub post_state_root_verified: bool,
    pub block_number: u64,
    pub block_hash: B256,
    pub raw_block_bytes: usize,
    pub transaction_count: usize,
    pub receipt_count: usize,
    pub gas_used: u64,
    pub blob_gas_used: u64,
}

#[derive(Debug, Error)]
pub enum ReplayError {
    #[error("invalid witness bundle JSON: {0}")]
    InvalidBundleJson(String),
    #[error("reference witness import failed: {0}")]
    ReferenceWitnessImport(#[source] WitnessImportError),
    #[error("DTVM witness import failed: {0}")]
    DtvmWitnessImport(#[source] WitnessImportError),
    #[error("strict replay requires a verified targetBlock")]
    MissingTargetBlock,
    #[error("raw target block decode failed: {0}")]
    RawBlockDecode(String),
    #[error("raw target block has trailing bytes")]
    RawBlockTrailingBytes,
    #[error("sender recovery failed for at least one transaction")]
    SenderRecovery,
    #[error("adapterUnsupported at transaction {transaction_index}: {reason}")]
    AdapterUnsupported {
        transaction_index: usize,
        reason: &'static str,
    },
    #[error("strict replay requires mainnet Osaka, got {actual:?}")]
    UnsupportedSpec { actual: SpecId },
    #[error("strict replay rejects block access list headers")]
    BlockAccessListUnsupported,
    #[error("strict replay rejects slot-number headers")]
    SlotNumberUnsupported,
    #[error("header consensus preflight failed: {0}")]
    HeaderPreflight(String),
    #[error("header-against-parent consensus preflight failed: {0}")]
    HeaderAgainstParent(String),
    #[error("block body consensus preflight failed: {0}")]
    BlockPreflight(String),
    #[error("DTVM provenance validation failed: {0}")]
    DtvmProvenance(String),
    #[error("referenceWitnessIncomplete after {access_count} database accesses: {message}")]
    ReferenceWitnessIncomplete {
        message: String,
        access_count: usize,
    },
    #[error("reference execution failed after {access_count} database accesses: {message}")]
    ReferenceExecution {
        message: String,
        access_count: usize,
    },
    #[error("dtvmUnprovenExtraAccess after {access_count} database accesses: {message}")]
    DtvmUnprovenExtraAccess {
        message: String,
        access_count: usize,
    },
    #[error("DTVM execution failed after {access_count} database accesses: {message}")]
    DtvmExecution {
        message: String,
        access_count: usize,
    },
    #[error("reference post-execution validation failed: {0}")]
    ReferencePostValidation(String),
    #[error("DTVM post-execution validation failed: {0}")]
    DtvmPostValidation(String),
    #[error("reference post-state root verification failed: {0}")]
    ReferencePostStateRoot(#[source] WitnessImportError),
    #[error("DTVM post-state root verification failed: {0}")]
    DtvmPostStateRoot(#[source] WitnessImportError),
    #[error("reference blob gas mismatch: expected {expected}, got {actual}")]
    ReferenceBlobGasMismatch { expected: u64, actual: u64 },
    #[error("DTVM blob gas mismatch: expected {expected}, got {actual}")]
    DtvmBlobGasMismatch { expected: u64, actual: u64 },
    #[error("stock and DTVM BlockExecutionResult differ")]
    ExecutionResultMismatch,
    #[error("stock and DTVM strict database access sequences differ")]
    AccessSequenceMismatch,
    #[error("stock and DTVM BundleState semantics differ")]
    BundleStateMismatch,
}

pub fn replay_bundle_json(json: &[u8]) -> Result<ReplayReport, ReplayError> {
    let bundle = serde_json::from_slice(json)
        .map_err(|error| ReplayError::InvalidBundleJson(error.to_string()))?;
    replay_bundle(bundle)
}

pub fn replay_bundle(bundle: WitnessBundle) -> Result<ReplayReport, ReplayError> {
    if bundle.target_block.is_none() {
        return Err(ReplayError::MissingTargetBlock);
    }
    let reference_db =
        WitnessDb::from_bundle(bundle.clone()).map_err(ReplayError::ReferenceWitnessImport)?;
    let dtvm_db = WitnessDb::from_bundle(bundle).map_err(ReplayError::DtvmWitnessImport)?;
    let raw = reference_db
        .target_block()
        .cloned()
        .ok_or(ReplayError::MissingTargetBlock)?;
    let expected_hash = reference_db.target_header().hash_slow();
    let expected_number = reference_db.target_header().number;
    let pre_state_root = reference_db.pre_state_root();
    let parent_header = SealedHeader::seal_slow(reference_db.parent_header().clone());

    let mut input = raw.as_ref();
    let sealed = Block::decode_sealed(&mut input)
        .map_err(|error| ReplayError::RawBlockDecode(error.to_string()))?;
    if !input.is_empty() {
        return Err(ReplayError::RawBlockTrailingBytes);
    }
    let sealed: SealedBlock<Block> = sealed.into();

    let recovered =
        RecoveredBlock::try_recover_sealed(sealed).map_err(|_| ReplayError::SenderRecovery)?;
    let transaction_hashes = recovered
        .body()
        .transactions
        .iter()
        .map(|transaction| *transaction.tx_hash())
        .collect::<Vec<_>>();
    let header = recovered.header();
    let spec = revm_spec(MAINNET.as_ref(), header);
    if spec != SpecId::OSAKA {
        return Err(ReplayError::UnsupportedSpec { actual: spec });
    }
    if header.block_access_list_hash.is_some() {
        return Err(ReplayError::BlockAccessListUnsupported);
    }
    if header.slot_number.is_some() {
        return Err(ReplayError::SlotNumberUnsupported);
    }

    let consensus = EthBeaconConsensus::new(MAINNET.clone());
    consensus
        .validate_header(recovered.sealed_block().sealed_header())
        .map_err(|error| ReplayError::HeaderPreflight(error.to_string()))?;
    consensus
        .validate_header_against_parent(recovered.sealed_block().sealed_header(), &parent_header)
        .map_err(|error| ReplayError::HeaderAgainstParent(error.to_string()))?;
    consensus
        .validate_block_pre_execution(recovered.sealed_block())
        .map_err(|error| ReplayError::BlockPreflight(error.to_string()))?;

    let dtvm_library = verified_dtvm_library_from_env()?;

    let reference_config =
        EthEvmConfig::new_with_evm_factory(MAINNET.clone(), EthEvmFactory::default());
    let mut reference_executor = BasicBlockExecutor::new(reference_config, reference_db);
    let reference_result = match reference_executor.execute_one(&recovered) {
        Ok(result) => result,
        Err(error) => {
            let state = reference_executor.into_state();
            return Err(classify_reference_execution(
                &error,
                state.database.strict_db().accesses().len(),
            ));
        }
    };
    let reference_state = reference_executor.into_state();
    let reference_accesses = reference_state.database.strict_db().accesses().to_vec();
    let reference_bundle = reference_state.bundle_state;
    let reference_db = reference_state.database;

    let dtvm_config = EthEvmConfig::new_with_evm_factory(
        MAINNET.clone(),
        DtvmEvmFactory::new(dtvm_library.path()),
    );
    let mut dtvm_executor = BasicBlockExecutor::new(dtvm_config, dtvm_db);
    let dtvm_result = match dtvm_executor.execute_one(&recovered) {
        Ok(result) => result,
        Err(error) => {
            let state = dtvm_executor.into_state();
            return Err(classify_dtvm_execution(
                &error,
                state.database.strict_db().accesses().len(),
                &transaction_hashes,
            ));
        }
    };
    let dtvm_state = dtvm_executor.into_state();
    drop(dtvm_library);
    let dtvm_accesses = dtvm_state.database.strict_db().accesses().to_vec();
    let dtvm_bundle = dtvm_state.bundle_state;
    let dtvm_db = dtvm_state.database;

    let reference_post =
        validate_block_post_execution(&recovered, MAINNET.as_ref(), &reference_result, None, None);
    let dtvm_post =
        validate_block_post_execution(&recovered, MAINNET.as_ref(), &dtvm_result, None, None);
    if let Err(error) = reference_post {
        return Err(ReplayError::ReferencePostValidation(error.to_string()));
    }
    if let Err(error) = dtvm_post {
        return Err(ReplayError::DtvmPostValidation(error.to_string()));
    }

    let expected_blob_gas = header.blob_gas_used.unwrap_or(0);
    if reference_result.blob_gas_used != expected_blob_gas {
        return Err(ReplayError::ReferenceBlobGasMismatch {
            expected: expected_blob_gas,
            actual: reference_result.blob_gas_used,
        });
    }
    if dtvm_result.blob_gas_used != expected_blob_gas {
        return Err(ReplayError::DtvmBlobGasMismatch {
            expected: expected_blob_gas,
            actual: dtvm_result.blob_gas_used,
        });
    }

    if dtvm_result != reference_result {
        return Err(ReplayError::ExecutionResultMismatch);
    }
    if dtvm_accesses != reference_accesses {
        return Err(ReplayError::AccessSequenceMismatch);
    }
    if !bundle_state_semantics_eq(&dtvm_bundle, &reference_bundle) {
        return Err(ReplayError::BundleStateMismatch);
    }

    let reference_post_state_root = reference_db.into_verified_post_state_root(&reference_bundle);
    let dtvm_post_state_root = dtvm_db.into_verified_post_state_root(&dtvm_bundle);
    let reference_post_state_root =
        reference_post_state_root.map_err(ReplayError::ReferencePostStateRoot)?;
    dtvm_post_state_root.map_err(ReplayError::DtvmPostStateRoot)?;

    Ok(ReplayReport {
        differential_match: true,
        raw_bound: true,
        pre_execution_commitments: true,
        post_execution_commitments: PostExecutionCommitments {
            gas_used: true,
            receipts_root: true,
            logs_bloom: true,
            requests_hash: true,
            blob_gas_used: true,
        },
        pre_state_root,
        pre_state_root_verified: true,
        post_state_root: reference_post_state_root,
        post_state_root_verified: true,
        block_number: expected_number,
        block_hash: expected_hash,
        raw_block_bytes: raw.len(),
        transaction_count: recovered.senders().len(),
        receipt_count: reference_result.receipts.len(),
        gas_used: reference_result.gas_used,
        blob_gas_used: reference_result.blob_gas_used,
    })
}

fn bundle_state_semantics_eq(actual: &BundleState, expected: &BundleState) -> bool {
    actual.state == expected.state
        && actual.contracts == expected.contracts
        && actual.reverts.content_eq(&expected.reverts)
}

fn classify_reference_execution(error: &(dyn Error + 'static), access_count: usize) -> ReplayError {
    let message = error.to_string();
    if error_chain_contains_witness(error) || message_contains_witness_error(&message) {
        ReplayError::ReferenceWitnessIncomplete {
            message,
            access_count,
        }
    } else {
        ReplayError::ReferenceExecution {
            message,
            access_count,
        }
    }
}

fn classify_dtvm_execution(
    error: &(dyn Error + 'static),
    access_count: usize,
    transaction_hashes: &[B256],
) -> ReplayError {
    let message = error.to_string();
    if error_chain_contains_witness(error) || message_contains_witness_error(&message) {
        ReplayError::DtvmUnprovenExtraAccess {
            message,
            access_count,
        }
    } else if let Some((transaction_index, reason)) =
        adapter_unsupported(&message, transaction_hashes)
    {
        ReplayError::AdapterUnsupported {
            transaction_index,
            reason,
        }
    } else {
        ReplayError::DtvmExecution {
            message,
            access_count,
        }
    }
}

fn error_chain_contains_witness(mut error: &(dyn Error + 'static)) -> bool {
    loop {
        if error.downcast_ref::<WitnessImportError>().is_some() {
            return true;
        }
        let Some(source) = error.source() else {
            return false;
        };
        error = source;
    }
}

fn message_contains_witness_error(message: &str) -> bool {
    const PREFIXES: &[&str] = &[
        "parent state root ",
        "failed to reconstruct witness multiproof: ",
        "failed to reveal witness multiproof: ",
        "revealed pre-state root mismatch: ",
        "account proof is incomplete for ",
        "account leaf for ",
        "storage manifest names an account that was not resolved: ",
        "storage proof is incomplete for ",
        "storage leaf for ",
        "account is outside the proven witness: ",
        "code is outside the proven witness: ",
        "code witness hash mismatch: ",
        "storage is outside the proven witness: ",
        "an absent account cannot have nonzero proven storage: ",
        "block hash is outside the proven witness: ",
        "account id ",
    ];

    PREFIXES
        .iter()
        .any(|prefix| message_has_prefixed_segment(message, prefix))
}

fn message_has_prefixed_segment(message: &str, prefix: &str) -> bool {
    message.starts_with(prefix)
        || message
            .match_indices(": ")
            .any(|(index, _)| message[index + 2..].starts_with(prefix))
}

fn adapter_unsupported(
    message: &str,
    transaction_hashes: &[B256],
) -> Option<(usize, &'static str)> {
    const PREFIX: &str = "internal EVM error occurred when executing transaction ";
    // Retain exact strings from earlier adapter slices as backwards-compatible
    // classifier cases. This allowlist is not a declaration of the current
    // adapter's capabilities.
    const EXACT_REASONS: &[(&str, &str)] = &[
        (
            "nested frame reached the DTVM first slice",
            "nested frame reached the DTVM first slice",
        ),
        (
            "EIP-8037 reservoir is unsupported",
            "EIP-8037 reservoir is unsupported",
        ),
        (
            "CREATE/empty frame is unsupported",
            "CREATE/empty frame is unsupported",
        ),
        (
            "only a non-static, non-delegated ordinary CALL is supported",
            "only a non-static, non-delegated ordinary CALL is supported",
        ),
        (
            "nested CALL code address differs from its recipient",
            "nested CALL code address differs from its recipient",
        ),
        (
            "SELFDESTRUCT is unsupported until it is bridged to the REVM journal",
            "SELFDESTRUCT is unsupported until it is bridged to the REVM journal",
        ),
        (
            "nested EIP-8037 reservoir is unsupported",
            "nested EIP-8037 reservoir is unsupported",
        ),
    ];

    let (hash, details) = message.strip_prefix(PREFIX)?.split_once(": ")?;
    let transaction_index = transaction_hashes
        .iter()
        .position(|transaction_hash| transaction_hash.to_string() == hash)?;
    if let Some((_, canonical)) = EXACT_REASONS
        .iter()
        .find(|(reason, _)| message_has_exact_segment(details, reason))
    {
        return Some((transaction_index, canonical));
    }
    for (candidate, reason) in [
        (
            "nested call kind is unsupported (kind=3)",
            "nested CREATE is unsupported (kind=3)",
        ),
        (
            "nested call kind is unsupported (kind=4)",
            "nested CREATE2 is unsupported (kind=4)",
        ),
        (
            "nested call kind is unsupported (kind=5)",
            "nested EOFCREATE is unsupported (kind=5)",
        ),
    ] {
        if message_has_exact_segment(details, candidate) {
            return Some((transaction_index, reason));
        }
    }
    if message_has_dynamic_suffix_segment(details, "nested call kind is unsupported (kind=", false)
    {
        return Some((transaction_index, "nested call kind is unsupported"));
    }
    if message_has_dynamic_suffix_segment(
        details,
        "nested CALL flags are unsupported (flags=0x",
        true,
    ) {
        return Some((transaction_index, "nested CALL flags are unsupported"));
    }
    None
}

fn message_has_exact_segment(message: &str, expected: &str) -> bool {
    message == expected
        || message
            .match_indices(": ")
            .any(|(index, _)| &message[index + 2..] == expected)
}

fn message_has_dynamic_suffix_segment(message: &str, prefix: &str, hexadecimal: bool) -> bool {
    error_segments(message).any(|segment| {
        let Some(value) = segment
            .strip_prefix(prefix)
            .and_then(|value| value.strip_suffix(')'))
        else {
            return false;
        };
        !value.is_empty()
            && if hexadecimal {
                value.bytes().all(|byte| byte.is_ascii_hexdigit())
            } else {
                value.parse::<i32>().is_ok()
            }
    })
}

fn error_segments(message: &str) -> impl Iterator<Item = &str> {
    std::iter::once(message).chain(
        message
            .match_indices(": ")
            .map(|(index, _)| &message[index + 2..]),
    )
}

struct VerifiedDtvmLibrary {
    _file: File,
    path: PathBuf,
}

impl VerifiedDtvmLibrary {
    fn path(&self) -> &Path {
        &self.path
    }
}

fn verified_dtvm_library_from_env() -> Result<VerifiedDtvmLibrary, ReplayError> {
    match std::env::var("DTVM_EVM_STRICT_ADDR_CACHE_VALIDATION") {
        Ok(value) if value == "true" => {}
        Ok(_) => {
            return Err(ReplayError::DtvmProvenance(
                "DTVM_EVM_STRICT_ADDR_CACHE_VALIDATION must equal true".to_string(),
            ));
        }
        Err(error) => {
            return Err(ReplayError::DtvmProvenance(format!(
                "DTVM_EVM_STRICT_ADDR_CACHE_VALIDATION is required: {error}"
            )));
        }
    }

    let path = std::env::var_os("DTVM_LIBRARY")
        .map(PathBuf::from)
        .ok_or_else(|| ReplayError::DtvmProvenance("DTVM_LIBRARY is required".to_string()))?;
    let expected = std::env::var("DTVM_LIBRARY_SHA256").map_err(|error| {
        ReplayError::DtvmProvenance(format!("DTVM_LIBRARY_SHA256 is required: {error}"))
    })?;
    if expected.len() != 64 || !expected.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(ReplayError::DtvmProvenance(
            "DTVM_LIBRARY_SHA256 must be exactly 64 hexadecimal characters".to_string(),
        ));
    }
    seal_verified_dtvm_library(&path, &expected)
}

fn seal_verified_dtvm_library(
    source_path: &Path,
    expected_sha256: &str,
) -> Result<VerifiedDtvmLibrary, ReplayError> {
    let mut source = File::open(source_path).map_err(|error| {
        ReplayError::DtvmProvenance(format!("failed to open DTVM_LIBRARY: {error}"))
    })?;
    let name = CString::new("reth-dtvm-verified-library")
        .expect("static memfd name contains no interior NUL");
    // SAFETY: `name` is NUL-terminated and the flags are valid Linux memfd flags.
    let fd =
        unsafe { libc::memfd_create(name.as_ptr(), libc::MFD_CLOEXEC | libc::MFD_ALLOW_SEALING) };
    if fd < 0 {
        return Err(ReplayError::DtvmProvenance(format!(
            "failed to create sealed DTVM memfd: {}",
            std::io::Error::last_os_error()
        )));
    }
    // SAFETY: `memfd_create` returned a new owned file descriptor.
    let mut file = unsafe { File::from_raw_fd(fd) };
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let count = source.read(&mut buffer).map_err(|error| {
            ReplayError::DtvmProvenance(format!("failed to read DTVM_LIBRARY: {error}"))
        })?;
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
        file.write_all(&buffer[..count]).map_err(|error| {
            ReplayError::DtvmProvenance(format!("failed to copy DTVM_LIBRARY to memfd: {error}"))
        })?;
    }
    let actual = hasher
        .finalize()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    if !actual.eq_ignore_ascii_case(expected_sha256) {
        return Err(ReplayError::DtvmProvenance(format!(
            "DTVM library SHA-256 mismatch: expected {expected_sha256}, got {actual}"
        )));
    }

    let seals = libc::F_SEAL_WRITE | libc::F_SEAL_SHRINK | libc::F_SEAL_GROW | libc::F_SEAL_SEAL;
    // SAFETY: `file` owns a valid memfd descriptor and `seals` contains only F_SEAL_* flags.
    if unsafe { libc::fcntl(file.as_raw_fd(), libc::F_ADD_SEALS, seals) } < 0 {
        return Err(ReplayError::DtvmProvenance(format!(
            "failed to seal DTVM memfd: {}",
            std::io::Error::last_os_error()
        )));
    }
    let path = PathBuf::from(format!("/proc/self/fd/{}", file.as_raw_fd()));
    Ok(VerifiedDtvmLibrary { _file: file, path })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::AccessManifest;
    use alloy_consensus::{Header, SignableTransaction, TxEip7702, TxLegacy};
    use alloy_eips::{
        eip2930::AccessList,
        eip7685::EMPTY_REQUESTS_HASH,
        eip7702::{Authorization, SignedAuthorization},
    };
    use alloy_primitives::{Address, Bytes, Signature, TxKind, U256};
    use alloy_rpc_types_debug::ExecutionWitness;
    use alloy_trie::EMPTY_ROOT_HASH;
    use reth_ethereum_primitives::{Transaction, TransactionSigned};

    const TARGET_NUMBER: u64 = 24_000_000;
    const TARGET_TIMESTAMP: u64 = 1_800_000_000;

    /// Covers strict full-block plumbing and empty-code system orchestration.
    ///
    /// The block has no transactions, so this does not claim that the DTVM VM
    /// executes contract bytecode; that remains covered by the signed CALL
    /// differential integration test.
    #[test]
    fn output_valid_empty_osaka_block_passes_strict_executor_orchestration() {
        let bundle = output_valid_empty_osaka_bundle();
        let report = replay_bundle(bundle).expect("strict full-block differential replay");

        assert!(report.differential_match);
        assert!(report.raw_bound);
        assert!(report.pre_execution_commitments);
        assert!(report.post_execution_commitments.gas_used);
        assert!(report.post_execution_commitments.receipts_root);
        assert!(report.post_execution_commitments.logs_bloom);
        assert!(report.post_execution_commitments.requests_hash);
        assert!(report.post_execution_commitments.blob_gas_used);
        assert_eq!(report.pre_state_root, EMPTY_ROOT_HASH);
        assert!(report.pre_state_root_verified);
        assert_eq!(report.post_state_root, EMPTY_ROOT_HASH);
        assert!(report.post_state_root_verified);
        assert_eq!(report.transaction_count, 0);
        assert_eq!(report.receipt_count, 0);
        assert_eq!(report.gas_used, 0);
        assert_eq!(report.blob_gas_used, 0);
    }

    #[test]
    fn legacy_header_only_bundle_is_rejected_before_import() {
        let mut bundle = output_valid_empty_osaka_bundle();
        bundle.target_block = None;
        assert!(matches!(
            replay_bundle(bundle),
            Err(ReplayError::MissingTargetBlock)
        ));
    }

    #[test]
    fn invalid_transaction_signature_is_rejected() {
        let mut bundle = output_valid_empty_osaka_bundle();
        let header = target_block(&bundle).header;
        let transaction = invalid_signed_transaction(TxKind::Call(Address::repeat_byte(0x44)));
        let mut block = Block::from_transactions(header, [transaction]);
        block.body.withdrawals = Some(Default::default());
        block.header.withdrawals_root = block.body.calculate_withdrawals_root();
        bind_target_block(&mut bundle, block);

        assert!(matches!(
            replay_bundle(bundle),
            Err(ReplayError::SenderRecovery)
        ));
    }

    #[test]
    fn invalid_header_fails_consensus_preflight() {
        let mut bundle = output_valid_empty_osaka_bundle();
        let mut block = target_block(&bundle);
        block.header.extra_data = Bytes::from(vec![0u8; 33]);
        bind_target_block(&mut bundle, block);

        assert!(matches!(
            replay_bundle(bundle),
            Err(ReplayError::HeaderPreflight(_))
        ));
    }

    #[test]
    fn base_fee_discontinuity_fails_parent_consensus_preflight() {
        let mut bundle = output_valid_empty_osaka_bundle();
        let mut block = target_block(&bundle);
        block.header.base_fee_per_gas = Some(2);
        bind_target_block(&mut bundle, block);

        assert!(matches!(
            replay_bundle(bundle),
            Err(ReplayError::HeaderAgainstParent(_))
        ));
    }

    #[test]
    fn stringified_system_call_database_error_is_witness_incomplete() {
        let error = OpaqueExecutionError(
            "failed to apply blockhash contract call: database error: \
             account is outside the proven witness: 0x1111111111111111111111111111111111111111"
                .to_string(),
        );

        assert!(matches!(
            classify_reference_execution(&error, 3),
            ReplayError::ReferenceWitnessIncomplete {
                access_count: 3,
                ..
            }
        ));
        assert!(matches!(
            classify_dtvm_execution(&error, 4, &[]),
            ReplayError::DtvmUnprovenExtraAccess {
                access_count: 4,
                ..
            }
        ));
    }

    #[test]
    fn allowlisted_custom_error_is_adapter_unsupported() {
        let transaction_hash = B256::repeat_byte(0x11);
        for (details, expected_reason) in [
            (
                "DTVM execution failed: host callback failed closed: \
                 nested call kind is unsupported (kind=2)",
                "nested call kind is unsupported",
            ),
            (
                "DTVM execution failed: host callback failed closed: \
                 nested call kind is unsupported (kind=3)",
                "nested CREATE is unsupported (kind=3)",
            ),
            (
                "DTVM execution failed: host callback failed closed: \
                 nested call kind is unsupported (kind=4)",
                "nested CREATE2 is unsupported (kind=4)",
            ),
            (
                "DTVM execution failed: host callback failed closed: \
                 nested call kind is unsupported (kind=5)",
                "nested EOFCREATE is unsupported (kind=5)",
            ),
            (
                "DTVM execution failed: host callback failed closed: \
                 nested CALL flags are unsupported (flags=0x4)",
                "nested CALL flags are unsupported",
            ),
            (
                "DTVM execution failed: host callback failed closed: \
                 nested CALL code address differs from its recipient",
                "nested CALL code address differs from its recipient",
            ),
            (
                "DTVM execution failed: host callback failed closed: \
                 SELFDESTRUCT is unsupported until it is bridged to the REVM journal",
                "SELFDESTRUCT is unsupported until it is bridged to the REVM journal",
            ),
            (
                "DTVM execution failed: host callback failed closed: \
                 nested EIP-8037 reservoir is unsupported",
                "nested EIP-8037 reservoir is unsupported",
            ),
        ] {
            let error = OpaqueExecutionError(format!(
                "internal EVM error occurred when executing transaction \
                 {transaction_hash}: {details}"
            ));
            match classify_dtvm_execution(&error, 5, &[transaction_hash]) {
                ReplayError::AdapterUnsupported {
                    transaction_index,
                    reason,
                } => {
                    assert_eq!(transaction_index, 0);
                    assert_eq!(reason, expected_reason);
                }
                other => panic!("expected adapterUnsupported, got {other:?}"),
            }
        }
    }

    #[test]
    fn unknown_custom_error_remains_dtvm_execution() {
        let transaction_hash = B256::repeat_byte(0x22);
        let error = OpaqueExecutionError(format!(
            "internal EVM error occurred when executing transaction {transaction_hash}: \
             unknown adapter failure"
        ));

        assert!(matches!(
            classify_dtvm_execution(&error, 6, &[transaction_hash]),
            ReplayError::DtvmExecution {
                access_count: 6,
                ..
            }
        ));
    }

    #[test]
    fn verified_dtvm_memfd_is_write_sealed() {
        let contents = b"deterministic DTVM library test bytes";
        let source_path = temporary_library_source(contents);
        let expected = sha256(contents);

        let mut library =
            seal_verified_dtvm_library(&source_path, &expected).expect("seal verified library");
        std::fs::remove_file(&source_path).expect("remove temporary library source");
        let error = library
            ._file
            .write_all(b"x")
            .expect_err("F_SEAL_WRITE must reject writes");
        assert_eq!(error.raw_os_error(), Some(libc::EPERM));
    }

    #[test]
    fn replacing_source_does_not_change_verified_memfd_bytes() {
        let original = b"verified original DTVM bytes";
        let source_path = temporary_library_source(original);
        let library = seal_verified_dtvm_library(&source_path, &sha256(original))
            .expect("seal verified library");

        std::fs::write(&source_path, b"replacement bytes").expect("replace original source");
        assert_eq!(
            std::fs::read(library.path()).expect("read sealed DTVM memfd"),
            original
        );
        std::fs::remove_file(source_path).expect("remove temporary library source");
    }

    #[test]
    fn verified_dtvm_memfd_passes_real_loader_gates() {
        let library = verified_dtvm_library_from_env().expect("verify and seal real DTVM library");
        // SAFETY: the loader path names the hash-verified, write-sealed memfd held by `library`.
        let dtvm = unsafe { reth_dtvm_adapter::Dtvm::load(library.path()) }
            .expect("load verified DTVM memfd");
        drop(dtvm);
        drop(library);
    }

    #[test]
    fn bad_receipts_commitment_fails_post_execution_validation() {
        let mut bundle = output_valid_empty_osaka_bundle();
        let mut block = target_block(&bundle);
        block.header.receipts_root = B256::repeat_byte(0x55);
        bind_target_block(&mut bundle, block);

        assert!(matches!(
            replay_bundle(bundle),
            Err(ReplayError::ReferencePostValidation(_))
        ));
    }

    #[test]
    fn create_transaction_reaches_sender_recovery() {
        let mut bundle = output_valid_empty_osaka_bundle();
        let header = target_block(&bundle).header;
        let transaction = invalid_signed_transaction(TxKind::Create);
        let mut block = Block::from_transactions(header, [transaction]);
        block.body.withdrawals = Some(Default::default());
        block.header.withdrawals_root = block.body.calculate_withdrawals_root();
        bind_target_block(&mut bundle, block);

        assert!(matches!(
            replay_bundle(bundle),
            Err(ReplayError::SenderRecovery)
        ));
    }

    #[test]
    fn type4_transaction_reaches_sender_recovery() {
        let mut bundle = output_valid_empty_osaka_bundle();
        let header = target_block(&bundle).header;
        let authorization = SignedAuthorization::new_unchecked(
            Authorization {
                chain_id: U256::from(1),
                address: Address::repeat_byte(0x55),
                nonce: 0,
            },
            0,
            U256::ZERO,
            U256::ZERO,
        );
        let transaction = Transaction::Eip7702(TxEip7702 {
            chain_id: 1,
            nonce: 0,
            gas_limit: 100_000,
            max_fee_per_gas: 2,
            max_priority_fee_per_gas: 0,
            to: Address::repeat_byte(0x44),
            value: U256::ZERO,
            access_list: AccessList::default(),
            authorization_list: vec![authorization],
            input: Bytes::new(),
        })
        .into_signed(Signature::new(U256::ZERO, U256::ZERO, false))
        .into();
        let mut block = Block::from_transactions(header, [transaction]);
        block.body.withdrawals = Some(Default::default());
        block.header.withdrawals_root = block.body.calculate_withdrawals_root();
        bind_target_block(&mut bundle, block);

        assert!(matches!(
            replay_bundle(bundle),
            Err(ReplayError::SenderRecovery)
        ));
    }

    fn output_valid_empty_osaka_bundle() -> WitnessBundle {
        let parent = Header {
            number: TARGET_NUMBER - 1,
            state_root: EMPTY_ROOT_HASH,
            gas_limit: 30_000_000,
            timestamp: TARGET_TIMESTAMP - 12,
            base_fee_per_gas: Some(1),
            withdrawals_root: Some(EMPTY_ROOT_HASH),
            blob_gas_used: Some(0),
            excess_blob_gas: Some(0),
            parent_beacon_block_root: Some(B256::repeat_byte(0x66)),
            requests_hash: Some(EMPTY_REQUESTS_HASH),
            ..Default::default()
        };
        let mut block = Block::from_transactions(
            Header {
                parent_hash: parent.hash_slow(),
                beneficiary: Address::repeat_byte(0x33),
                state_root: EMPTY_ROOT_HASH,
                receipts_root: EMPTY_ROOT_HASH,
                number: TARGET_NUMBER,
                gas_limit: 30_000_000,
                gas_used: 0,
                timestamp: TARGET_TIMESTAMP,
                mix_hash: B256::repeat_byte(0x77),
                base_fee_per_gas: Some(1),
                withdrawals_root: Some(EMPTY_ROOT_HASH),
                blob_gas_used: Some(0),
                excess_blob_gas: Some(0),
                parent_beacon_block_root: Some(B256::repeat_byte(0x88)),
                requests_hash: Some(EMPTY_REQUESTS_HASH),
                block_access_list_hash: None,
                slot_number: None,
                ..Default::default()
            },
            std::iter::empty(),
        );
        block.body.withdrawals = Some(Default::default());
        block.header.withdrawals_root = block.body.calculate_withdrawals_root();
        let raw = alloy_rlp::encode(&block);

        WitnessBundle {
            target_header: alloy_rlp::encode(&block.header).into(),
            target_block_hash: block.header.hash_slow(),
            target_block: Some(raw.into()),
            witness: ExecutionWitness {
                state: Vec::new(),
                codes: Vec::new(),
                keys: Vec::new(),
                headers: vec![Bytes::from(alloy_rlp::encode(parent))],
            },
            access_manifest: AccessManifest::default(),
        }
    }

    fn target_block(bundle: &WitnessBundle) -> Block {
        let mut input = bundle
            .target_block
            .as_ref()
            .expect("raw target block")
            .as_ref();
        let block = Block::decode_sealed(&mut input).expect("decode raw target block");
        assert!(input.is_empty());
        block.into_inner()
    }

    fn bind_target_block(bundle: &mut WitnessBundle, block: Block) {
        bundle.target_header = alloy_rlp::encode(&block.header).into();
        bundle.target_block_hash = block.header.hash_slow();
        bundle.target_block = Some(alloy_rlp::encode(block).into());
    }

    fn invalid_signed_transaction(kind: TxKind) -> TransactionSigned {
        let transaction = Transaction::Legacy(TxLegacy {
            chain_id: Some(1),
            nonce: 0,
            gas_price: 2,
            gas_limit: 21_000,
            to: kind,
            value: U256::ZERO,
            input: Bytes::new(),
        });
        transaction
            .into_signed(Signature::new(U256::ZERO, U256::ZERO, false))
            .into()
    }

    fn temporary_library_source(contents: &[u8]) -> PathBuf {
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("system clock after Unix epoch")
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "reth-dtvm-library-source-{}-{nonce}",
            std::process::id()
        ));
        std::fs::write(&path, contents).expect("write temporary library source");
        path
    }

    fn sha256(contents: &[u8]) -> String {
        Sha256::digest(contents)
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect()
    }

    #[derive(Debug)]
    struct OpaqueExecutionError(String);

    impl std::fmt::Display for OpaqueExecutionError {
        fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            formatter.write_str(&self.0)
        }
    }

    impl Error for OpaqueExecutionError {}
}
