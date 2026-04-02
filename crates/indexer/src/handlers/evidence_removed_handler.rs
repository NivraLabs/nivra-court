use std::sync::Arc;

use async_trait::async_trait;
use nivra_schema::schema::evidence;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::pipeline::sequential::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_indexer_alt_framework::postgres::{Connection, Db};
use diesel_async::RunQueryDsl;
use diesel::prelude::*;

use crate::NivraEnv;
use crate::handlers::has_nivra_events;
use crate::models::nivra::evidence::EvidenceRemovedEvent;
use crate::traits::MoveStruct;


pub struct EvidenceRemovedHandler {
    env: NivraEnv,
}

impl EvidenceRemovedHandler {
    pub fn new(env: NivraEnv) -> Self {
        Self { env }
    }
}

#[async_trait]
impl Processor for EvidenceRemovedHandler {
    const NAME: &'static str = "evidence_removed_handler";
    type Value = String;

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> anyhow::Result<Vec<Self::Value>> {
        let mut results = vec![];

        for tx in &checkpoint.transactions {
            if !has_nivra_events(tx, self.env) {
                continue;
            }
            let Some(events) = &tx.events else {
                continue;
            };

            for ev in events.data.iter() {
                if !EvidenceRemovedEvent::matches_event_type(&ev.type_, self.env) {
                    continue;
                }

                let event: EvidenceRemovedEvent = bcs::from_bytes(&ev.contents)?;
                results.push(event.evidence.to_string());
            }
        }

        Ok(results)
    }
}

#[async_trait]
impl Handler for EvidenceRemovedHandler {
    type Store = Db;
    type Batch = Vec<Self::Value>;

    fn batch(&self, batch: &mut Self::Batch, values: std::vec::IntoIter<Self::Value>) {
        batch.extend(values);
    }

    async fn commit<'a>(&self, batch: &Self::Batch, conn: &mut Connection<'a>) -> anyhow::Result<usize> {
        let mut updated = 0;

        for evidence_id in batch.iter() {
            diesel::delete(evidence::table.find(evidence_id))
                .execute(conn)
                .await?;

            updated += 1;
        }

        Ok(updated)
    }
}