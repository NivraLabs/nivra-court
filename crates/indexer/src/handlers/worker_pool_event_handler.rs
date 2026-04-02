use std::sync::Arc;

use async_trait::async_trait;
use nivra_schema::models::WorkerPool;
use nivra_schema::schema::worker_pool;
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
    type Value = WorkerPool;

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
                let data = WorkerPool { 
                    court: event.court.to_string(), 
                    nivster: event.nivster.to_string(), 
                    active: true, 
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
        let rows_affected = diesel::insert_into(worker_pool::table)
            .values(batch)
            .on_conflict((
                worker_pool::court,
                worker_pool::nivster,
            ))
            .do_update()
            .set(
                worker_pool::active.eq(diesel::dsl::not(worker_pool::active))
            )
            .execute(conn)
            .await?;

        Ok(rows_affected)
    }
}