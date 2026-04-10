use std::sync::Arc;

use async_trait::async_trait;
use chrono::Utc;
use diesel::upsert::excluded;
use nivra_schema::models::NivsterCourtBalance;
use nivra_schema::schema::nivster_court_balance;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::pipeline::sequential::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_indexer_alt_framework::postgres::{Connection, Db};
use diesel_async::RunQueryDsl;
use diesel::prelude::*;

use crate::NivraEnv;
use crate::handlers::has_nivra_events;
use crate::models::nivra::court::WorkerPoolEvent;
use crate::traits::MoveStruct;


pub struct WorkerPoolEventHandler {
    env: NivraEnv,
}

impl WorkerPoolEventHandler {
    pub fn new(env: NivraEnv) -> Self {
        Self { env }
    }
}

#[async_trait]
impl Processor for WorkerPoolEventHandler {
    const NAME: &'static str = "worker_pool_event_handler";
    type Value = NivsterCourtBalance;

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
                if !WorkerPoolEvent::matches_event_type(&ev.type_, self.env) {
                    continue;
                }

                let event: WorkerPoolEvent = bcs::from_bytes(&ev.contents)?;
                let data = NivsterCourtBalance { 
                    court: event.court.to_string(), 
                    nivster: event.nivster.to_string(),
                    nvr: 0,
                    sui: 0,
                    locked_nvr: 0,
                    in_worker_pool: event.entry,
                    modified_at: Utc::now().naive_utc(),
                };

                results.push(data);
            }
        }

        Ok(results)
    }
}

#[async_trait]
impl Handler for WorkerPoolEventHandler {
    type Store = Db;
    type Batch = Vec<Self::Value>;

    fn batch(&self, batch: &mut Self::Batch, values: std::vec::IntoIter<Self::Value>) {
        batch.extend(values);
    }

    async fn commit<'a>(&self, batch: &Self::Batch, conn: &mut Connection<'a>) -> anyhow::Result<usize> {
        let rows_affected = diesel::insert_into(nivster_court_balance::table)
            .values(batch)
            .on_conflict((
                nivster_court_balance::court,
                nivster_court_balance::nivster,
            ))
            .do_update()
            .set((
                nivster_court_balance::in_worker_pool.eq(excluded(nivster_court_balance::in_worker_pool)),
                nivster_court_balance::modified_at.eq(Utc::now().naive_utc()),
            ))
            .execute(conn)
            .await?;

        Ok(rows_affected)
    }
}