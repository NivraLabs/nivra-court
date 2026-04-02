use std::sync::Arc;

use async_trait::async_trait;
use chrono::DateTime;
use nivra_schema::models::EvidenceModified;
use nivra_schema::schema::evidence;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::pipeline::sequential::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_indexer_alt_framework::postgres::{Connection, Db};
use diesel_async::RunQueryDsl;
use diesel::prelude::*;

use crate::NivraEnv;
use crate::handlers::has_nivra_events;
use crate::models::nivra::evidence::EvidenceModifiedEvent;
use crate::traits::MoveStruct;


pub struct EvidenceModifiedHandler {
    env: NivraEnv,
}

impl EvidenceModifiedHandler {
    pub fn new(env: NivraEnv) -> Self {
        Self { env }
    }
}

#[async_trait]
impl Processor for EvidenceModifiedHandler {
    const NAME: &'static str = "evidence_modified_handler";
    type Value = EvidenceModified;

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
                if !EvidenceModifiedEvent::matches_event_type(&ev.type_, self.env) {
                    continue;
                }

                let event: EvidenceModifiedEvent = bcs::from_bytes(&ev.contents)?;
                let data = EvidenceModified { 
                    evidence_id: event.evidence.to_string(), 
                    description: event.description, 
                    src: event.src, 
                    file_name: event.file_name, 
                    file_type: event.file_type, 
                    file_subtype: event.file_subtype, 
                    encrypted: event.encrypted,
                    modified: DateTime::from_timestamp_millis(checkpoint_timestamp_ms)
                        .map(|datetime| datetime.naive_utc()),
                };

                results.push(data);
            }
        }

        Ok(results)
    }
}

#[async_trait]
impl Handler for EvidenceModifiedHandler {
    type Store = Db;
    type Batch = Vec<Self::Value>;

    fn batch(&self, batch: &mut Self::Batch, values: std::vec::IntoIter<Self::Value>) {
        batch.extend(values);
    }

    async fn commit<'a>(&self, batch: &Self::Batch, conn: &mut Connection<'a>) -> anyhow::Result<usize> {
        let mut updated = 0;

        for changeset in batch.iter() {
            diesel::update(evidence::table.find(changeset.evidence_id.clone()))
                .set(changeset)
                .execute(conn)
                .await?;

            updated += 1;
        }

        Ok(updated)
    }
}