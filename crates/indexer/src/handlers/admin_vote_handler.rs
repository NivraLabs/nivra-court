use std::sync::Arc;

use async_trait::async_trait;
use nivra_schema::models::AdminVote;
use nivra_schema::schema::admin_vote;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::pipeline::sequential::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_indexer_alt_framework::postgres::{Connection, Db};
use sui_types::transaction::TransactionDataAPI;
use diesel_async::RunQueryDsl;

use crate::NivraEnv;
use crate::handlers::{has_nivra_events, try_extract_move_call_package};
use crate::models::Nivra::Registry::AdminVoteEvent;
use crate::traits::MoveStruct;


pub struct AdminVoteHandler {
    env: NivraEnv,
}

impl AdminVoteHandler {
    pub fn new(env: NivraEnv) -> Self {
        Self { env }
    }
}

#[async_trait]
impl Processor for AdminVoteHandler {
    const NAME: &'static str = "admin_vote_handler";
    type Value = AdminVote;

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> anyhow::Result<Vec<Self::Value>> {
        let mut results = vec![];

        for tx in &checkpoint.transactions {
            if !has_nivra_events(tx, self.env) {
                continue;
            }
            let Some(events) = &tx.events else {
                continue;
            };

            let package = try_extract_move_call_package(tx).unwrap_or_default();
            let checkpoint_timestamp_ms = checkpoint.summary.timestamp_ms as i64;
            let checkpoint_seq = checkpoint.summary.sequence_number as i64;
            let digest = tx.transaction.digest();

            for (index, ev) in events.data.iter().enumerate() {
                if !AdminVoteEvent::matches_event_type(&ev.type_, self.env) {
                    continue;
                }

                let event: AdminVoteEvent = bcs::from_bytes(&ev.contents)?;
                let data = AdminVote { 
                    vote_id: event.vote.to_string(), 
                    vote_type: event.vote_type as i16, 
                    vote_enforced: false, 
                    sender: tx.transaction.sender().to_string(), 
                    checkpoint: checkpoint_seq, 
                    checkpoint_timestamp_ms, 
                    package: package.clone(), 
                    digest: digest.to_string(), 
                    event_digest: format!("{digest}{index}"), 
                };

                results.push(data);
            }
        }

        Ok(results)
    }
}

#[async_trait]
impl Handler for AdminVoteHandler {
    type Store = Db;
    type Batch = Vec<Self::Value>;

    fn batch(&self, batch: &mut Self::Batch, values: std::vec::IntoIter<Self::Value>) {
        batch.extend(values);
    }

    async fn commit<'a>(&self, batch: &Self::Batch, conn: &mut Connection<'a>) -> anyhow::Result<usize> {
        let inserted = diesel::insert_into(admin_vote::table)
            .values(batch)
            .on_conflict_do_nothing()
            .execute(conn)
            .await?;

        Ok(inserted)
    }
}