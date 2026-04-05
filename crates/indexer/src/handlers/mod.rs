use sui_indexer_alt_framework::types::full_checkpoint_content::ExecutedTransaction;

use crate::NivraEnv;


pub mod admin_vote_handler;
pub mod admin_vote_finalized_handler;
pub mod balance_event_handler;
pub mod court_created_handler;
pub mod court_metadata_changed_handler;
pub mod court_timetable_changed_handler;
pub mod court_economics_changed_handler;
pub mod court_operation_changed_handler;
pub mod dispute_created_handler;
pub mod dispute_event_handler;
pub mod dispute_payment_handler;
pub mod evidence_created_handler;
pub mod evidence_modified_handler;
pub mod evidence_removed_handler;
pub mod nivster_selection_handler;
pub mod worker_pool_event_handler;

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