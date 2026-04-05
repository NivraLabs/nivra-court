use std::sync::Arc;

use async_trait::async_trait;
use nivra_schema::models::NewBalanceEvent;
use nivra_schema::schema::balance_event;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::pipeline::sequential::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_indexer_alt_framework::postgres::{Connection, Db};
use sui_types::transaction::TransactionDataAPI;
use diesel_async::RunQueryDsl;

use crate::NivraEnv;
use crate::handlers::has_nivra_events;
use crate::models::nivra::court::BalanceEvent as BalanceMoveEvent;
use crate::traits::MoveStruct;


pub struct BalanceEventHandler {
    env: NivraEnv,
}

impl BalanceEventHandler {
    pub fn new(env: NivraEnv) -> Self {
        Self { env }
    }
}

#[async_trait]
impl Processor for BalanceEventHandler {
    const NAME: &'static str = "balance_event_handler";
    type Value = NewBalanceEvent;

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
                if !BalanceMoveEvent::matches_event_type(&ev.type_, self.env) {
                    continue;
                }

                let event: BalanceMoveEvent = bcs::from_bytes(&ev.contents)?;
                let data = NewBalanceEvent {  
                    nivster: event.nivster.to_string(), 
                    court: event.court.to_string(), 
                    event_type: event.event_type as i16, 
                    amount_nvr: event.amount_nvr as i64, 
                    amount_sui: event.amount_sui as i64, 
                    lock_nvr: event.lock_nvr as i64, 
                    dispute_id: event.dispute_id.map(|id| id.to_string()), 
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
impl Handler for BalanceEventHandler {
    type Store = Db;
    type Batch = Vec<Self::Value>;

    fn batch(&self, batch: &mut Self::Batch, values: std::vec::IntoIter<Self::Value>) {
        batch.extend(values);
    }

    async fn commit<'a>(&self, batch: &Self::Batch, conn: &mut Connection<'a>) -> anyhow::Result<usize> {
        let inserted = diesel::insert_into(balance_event::table)
            .values(batch)
            .on_conflict_do_nothing()
            .execute(conn)
            .await?;

        Ok(inserted)
    }
}