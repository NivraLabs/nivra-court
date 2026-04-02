use std::sync::Arc;

use async_trait::async_trait;
use diesel::ExpressionMethods;
use nivra_schema::models::DisputeNivster;
use nivra_schema::schema::dispute_nivster;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::pipeline::sequential::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_indexer_alt_framework::postgres::{Connection, Db};
use diesel_async::RunQueryDsl;
use diesel::upsert::excluded;

use crate::NivraEnv;
use crate::handlers::has_nivra_events;
use crate::models::nivra::dispute::NivsterSelectionEvent;
use crate::traits::MoveStruct;


pub struct NivsterSelectionHandler {
    env: NivraEnv,
}

impl NivsterSelectionHandler {
    pub fn new(env: NivraEnv) -> Self {
        Self { env }
    }
}

#[async_trait]
impl Processor for NivsterSelectionHandler {
    const NAME: &'static str = "nivster_selection_handler";
    type Value = DisputeNivster;

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
                if !NivsterSelectionEvent::matches_event_type(&ev.type_, self.env) {
                    continue;
                }

                let event: NivsterSelectionEvent = bcs::from_bytes(&ev.contents)?;
                let data = DisputeNivster { 
                    dispute_id: event.dispute.to_string(), 
                    nivster: event.nivster.to_string(), 
                    votes: 1, 
                    stake: event.locked_amount as i64, 
                };

                results.push(data);
            }
        }

        Ok(results)
    }
}

#[async_trait]
impl Handler for NivsterSelectionHandler {
    type Store = Db;
    type Batch = Vec<Self::Value>;

    fn batch(&self, batch: &mut Self::Batch, values: std::vec::IntoIter<Self::Value>) {
        batch.extend(values);
    }

    async fn commit<'a>(&self, batch: &Self::Batch, conn: &mut Connection<'a>) -> anyhow::Result<usize> {
        let inserted = diesel::insert_into(dispute_nivster::table)
            .values(batch)
            .on_conflict((
                dispute_nivster::dispute_id,
                dispute_nivster::nivster,
            ))
            .do_update()
            .set((
                dispute_nivster::votes.eq(
                    dispute_nivster::votes + excluded(dispute_nivster::votes)
                ),
                dispute_nivster::stake.eq(
                    dispute_nivster::stake + excluded(dispute_nivster::stake)
                ),
            ))
            .execute(conn)
            .await?;

        Ok(inserted)
    }
}