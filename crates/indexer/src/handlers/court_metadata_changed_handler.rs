use std::sync::Arc;

use async_trait::async_trait;
use nivra_schema::models::CourtMetadataChangeset;
use nivra_schema::schema::court;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::pipeline::sequential::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_indexer_alt_framework::postgres::{Connection, Db};
use diesel::prelude::*;
use diesel_async::RunQueryDsl;

use crate::NivraEnv;
use crate::handlers::has_nivra_events;
use crate::models::nivra::court::CourtMetadataChanged;
use crate::traits::MoveStruct;


pub struct CourtMetadataChangedHandler {
    env: NivraEnv,
}

impl CourtMetadataChangedHandler {
    pub fn new(env: NivraEnv) -> Self {
        Self { env }
    }
}

#[async_trait]
impl Processor for CourtMetadataChangedHandler {
    const NAME: &'static str = "court_metadata_changed_handler";
    type Value = CourtMetadataChangeset;

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
                if !CourtMetadataChanged::matches_event_type(&ev.type_, self.env) {
                    continue;
                }

                let event: CourtMetadataChanged = bcs::from_bytes(&ev.contents)?;
                let data = CourtMetadataChangeset { 
                    court_id: event.court.to_string(), 
                    name: event.metadata.name, 
                    category: event.metadata.category, 
                    description: event.metadata.description, 
                    ai_court: event.metadata.ai_court, 
                };

                results.push(data);
            }
        }

        Ok(results)
    }
}

#[async_trait]
impl Handler for CourtMetadataChangedHandler {
    type Store = Db;
    type Batch = Vec<Self::Value>;

    fn batch(&self, batch: &mut Self::Batch, values: std::vec::IntoIter<Self::Value>) {
        batch.extend(values);
    }

    async fn commit<'a>(&self, batch: &Self::Batch, conn: &mut Connection<'a>) -> anyhow::Result<usize> {
        let mut updated = 0;

        for metadata_changeset in batch.iter() {
            diesel::update(court::table.find(metadata_changeset.court_id.clone()))
                .set(metadata_changeset)
                .execute(conn)
                .await?;

            updated += 1;
        }

        Ok(updated)
    }
}