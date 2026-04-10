use std::sync::Arc;

use async_trait::async_trait;
use chrono::Utc;
use nivra_schema::models::CourtTimetableChangeset;
use nivra_schema::schema::court;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::pipeline::sequential::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_indexer_alt_framework::postgres::{Connection, Db};
use diesel::prelude::*;
use diesel_async::RunQueryDsl;

use crate::NivraEnv;
use crate::handlers::has_nivra_events;
use crate::models::nivra::court::CourtTimetableChanged;
use crate::traits::MoveStruct;


pub struct CourtTimetableChangedHandler {
    env: NivraEnv,
}

impl CourtTimetableChangedHandler {
    pub fn new(env: NivraEnv) -> Self {
        Self { env }
    }
}

#[async_trait]
impl Processor for CourtTimetableChangedHandler {
    const NAME: &'static str = "court_timetable_changed_handler";
    type Value = CourtTimetableChangeset;

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
                if !CourtTimetableChanged::matches_event_type(&ev.type_, self.env) {
                    continue;
                }

                let event: CourtTimetableChanged = bcs::from_bytes(&ev.contents)?;
                let data = CourtTimetableChangeset { 
                    court_id: event.court.to_string(), 
                    response_period_ms: event.timetable.response_period_ms as i64, 
                    draw_period_ms: event.timetable.draw_period_ms as i64, 
                    evidence_period_ms: event.timetable.evidence_period_ms as i64, 
                    voting_period_ms: event.timetable.voting_period_ms as i64, 
                    appeal_period_ms: event.timetable.appeal_period_ms as i64,
                    modified: Utc::now().naive_utc(), 
                };

                results.push(data);
            }
        }

        Ok(results)
    }
}

#[async_trait]
impl Handler for CourtTimetableChangedHandler {
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