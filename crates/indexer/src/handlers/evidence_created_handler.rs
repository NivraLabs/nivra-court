use std::sync::Arc;

use async_trait::async_trait;
use nivra_schema::models::Evidence;
use nivra_schema::schema::evidence;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::pipeline::sequential::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_indexer_alt_framework::postgres::{Connection, Db};
use sui_types::transaction::TransactionDataAPI;
use diesel_async::RunQueryDsl;

use crate::NivraEnv;
use crate::handlers::has_nivra_events;
use crate::models::nivra::evidence::EvidenceCreatedEvent;
use crate::traits::MoveStruct;


pub struct EvidenceCreatedHandler {
    env: NivraEnv,
}

impl EvidenceCreatedHandler {
    pub fn new(env: NivraEnv) -> Self {
        Self { env }
    }
}

#[async_trait]
impl Processor for EvidenceCreatedHandler {
    const NAME: &'static str = "evidence_created_handler";
    type Value = Evidence;

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> anyhow::Result<Vec<Self::Value>> {
        let mut results = vec![];

        for tx in &checkpoint.transactions {
            if !has_nivra_events(tx, self.env) {
                continue;
            }
            let Some(events) = &tx.events else {
                continue;
            };

            let checkpoint_timestamp_ms = checkpoint.summary.timestamp_ms as i64;

            for ev in events.data.iter() {
                if !EvidenceCreatedEvent::matches_event_type(&ev.type_, self.env) {
                    continue;
                }

                let event: EvidenceCreatedEvent = bcs::from_bytes(&ev.contents)?;
                let data = Evidence { 
                    evidence_id: event.evidence.to_string(), 
                    dispute_id: event.dispute.to_string(), 
                    owner: event.party.to_string(), 
                    description: event.description, 
                    src: event.src, 
                    file_name: event.file_name, 
                    file_type: event.file_type, 
                    file_subtype: event.file_subtype, 
                    encrypted: event.encrypted, 
                    censored: false, 
                    modified: Option::None, 
                    sender: tx.transaction.sender().to_string(),
                    checkpoint_timestamp_ms, 
                };

                results.push(data);
            }
        }

        Ok(results)
    }
}

#[async_trait]
impl Handler for EvidenceCreatedHandler {
    type Store = Db;
    type Batch = Vec<Self::Value>;

    fn batch(&self, batch: &mut Self::Batch, values: std::vec::IntoIter<Self::Value>) {
        batch.extend(values);
    }

    async fn commit<'a>(&self, batch: &Self::Batch, conn: &mut Connection<'a>) -> anyhow::Result<usize> {
        let inserted = diesel::insert_into(evidence::table)
            .values(batch)
            .on_conflict_do_nothing()
            .execute(conn)
            .await?;

        Ok(inserted)
    }
}