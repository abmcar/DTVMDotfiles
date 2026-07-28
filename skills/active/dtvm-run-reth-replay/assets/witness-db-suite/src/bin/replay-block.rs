use reth_dtvm_witness_db::replay::replay_bundle_json;
use std::{env, fs, process::ExitCode};

fn main() -> ExitCode {
    let mut args = env::args_os();
    let program = args
        .next()
        .and_then(|value| value.into_string().ok())
        .unwrap_or_else(|| "replay-block".to_string());
    let Some(path) = args.next() else {
        print_usage(&program);
        return ExitCode::FAILURE;
    };
    if args.next().is_some() {
        print_usage(&program);
        return ExitCode::FAILURE;
    }

    let json = match fs::read(&path) {
        Ok(json) => json,
        Err(error) => {
            eprintln!("failed to read {}: {error}", path.to_string_lossy());
            return ExitCode::FAILURE;
        }
    };
    let report = match replay_bundle_json(&json) {
        Ok(report) => report,
        Err(error) => {
            eprintln!("strict differential replay failed: {error}");
            return ExitCode::FAILURE;
        }
    };
    match serde_json::to_string(&report) {
        Ok(report) => {
            println!("{report}");
            ExitCode::SUCCESS
        }
        Err(error) => {
            eprintln!("failed to serialize replay report: {error}");
            ExitCode::FAILURE
        }
    }
}

fn print_usage(program: &str) {
    eprintln!("usage: {program} BUNDLE.json");
    eprintln!(
        "required environment: DTVM_EVM_STRICT_ADDR_CACHE_VALIDATION=true, \
         DTVM_LIBRARY, DTVM_LIBRARY_SHA256"
    );
}
