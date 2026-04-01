use std::sync::Arc;

use async_trait::async_trait;
use nivra_schema::models::NewDisputeEvent;
use nivra_schema::schema::dispute_event;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::pipeline::sequential::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_indexer_alt_framework::postgres::{Connection, Db};
use sui_types::transaction::TransactionDataAPI;
use diesel_async::RunQueryDsl;

use crate::NivraEnv;
use crate::handlers::{has_nivra_events, try_extract_move_call_package};
use crate::models::nivra::dispute::DisputeEvent;
use crate::traits::MoveStruct;


pub struct DisputeEventHandler {
    env: NivraEnv,
}

impl DisputeEventHandler {
    pub fn new(env: NivraEnv) -> Self {
        Self { env }
    }
}

#[async_trait]
impl Processor for DisputeEventHandler {
    const NAME: &'static str = "dispute_event_handler";
    type Value = NewDisputeEvent;

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
                if !DisputeEvent::matches_event_type(&ev.type_, self.env) {
                    continue;
                }

                let event: DisputeEvent = bcs::from_bytes(&ev.contents)?;
                let data = NewDisputeEvent { 
                    dispute_id: event.dispute.to_string(), 
                    event_type: event.event_type as i16, 
                    result: event.result, 
                    votes_per_option: event.votes_per_option.map(|res| 
                        res.iter().map(|val| *val as i32).collect()
                    ), 
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
impl Handler for DisputeEventHandler {
    type Store = Db;
    type Batch = Vec<Self::Value>;

    fn batch(&self, batch: &mut Self::Batch, values: std::vec::IntoIter<Self::Value>) {
        batch.extend(values);
    }

    async fn commit<'a>(&self, batch: &Self::Batch, conn: &mut Connection<'a>) -> anyhow::Result<usize> {
        let inserted = diesel::insert_into(dispute_event::table)
            .values(batch)
            .on_conflict_do_nothing()
            .execute(conn)
            .await?;

        Ok(inserted)
    }
}