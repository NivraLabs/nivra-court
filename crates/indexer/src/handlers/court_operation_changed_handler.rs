use std::sync::Arc;

use async_trait::async_trait;
use chrono::Utc;
use nivra_schema::models::CourtOperationChangeset;
use nivra_schema::schema::court;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::pipeline::sequential::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_indexer_alt_framework::postgres::{Connection, Db};
use diesel::prelude::*;
use diesel_async::RunQueryDsl;

use crate::NivraEnv;
use crate::handlers::has_nivra_events;
use crate::models::nivra::court::CourtOperationChanged;
use crate::traits::MoveStruct;


pub struct CourtOperationChangedHandler {
    env: NivraEnv,
}

impl CourtOperationChangedHandler {
    pub fn new(env: NivraEnv) -> Self {
        Self { env }
    }
}

#[async_trait]
impl Processor for CourtOperationChangedHandler {
    const NAME: &'static str = "court_operation_changed_handler";
    type Value = CourtOperationChangeset;

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
                if !CourtOperationChanged::matches_event_type(&ev.type_, self.env) {
                    continue;
                }

                let event: CourtOperationChanged = bcs::from_bytes(&ev.contents)?;
                let data = CourtOperationChangeset { 
                    court_id: event.court.to_string(), 
                    status: event.status as i16,
                    modified: Utc::now().naive_utc(),
                };

                results.push(data);
            }
        }

        Ok(results)
    }
}

#[async_trait]
impl Handler for CourtOperationChangedHandler {
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