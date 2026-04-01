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
    type Value = WorkerPoolEvent;

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
                results.push(event);
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
        let mut rows_affected = 0;

        for worker_pool_event in batch.iter() {
            if worker_pool_event.entry {
                diesel::insert_into(worker_pool::table)
                    .values(WorkerPool { 
                        court: worker_pool_event.court.to_string(), 
                        nivster: worker_pool_event.nivster.to_string(), 
                    })
                    .on_conflict_do_nothing()
                    .execute(conn)
                    .await?;
            } else {
                diesel::delete(worker_pool::table.find((
                    worker_pool_event.court.to_string(),
                    worker_pool_event.nivster.to_string()
                )))
                .execute(conn)
                .await?;
            }

            rows_affected += 1;
        }

        Ok(rows_affected)
    }
}