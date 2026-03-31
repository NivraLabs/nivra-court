use sui_indexer_alt_framework::types::full_checkpoint_content::ExecutedTransaction;
use sui_types::transaction::{Command, TransactionDataAPI};

use crate::NivraEnv;


pub mod admin_vote_handler;
pub mod admin_vote_finalized_handler;

pub(crate) fn has_nivra_events(
    tx: &ExecutedTransaction,
    env: NivraEnv,
) -> bool {
    let nivra_addresses = env.package_addresses();

    // Check if transaction has deepbook events from any version
    if let Some(events) = &tx.events {
        let has_nivra_event = events.data.iter().any(|event| {
            nivra_addresses
                .iter()
                .any(|addr| event.type_.address == *addr)
        });

        if has_nivra_event {
            return true;
        }
    }

    false
}

pub(crate) fn try_extract_move_call_package(tx: &ExecutedTransaction) -> Option<String> {
    let txn_kind = tx.transaction.kind();
    let first_command = txn_kind.iter_commands().next()?;
    if let Command::MoveCall(move_call) = first_command {
        Some(move_call.package.to_string())
    } else {
        None
    }
}