use std::sync::Arc;

use async_trait::async_trait;
use nivra_schema::models::NewDisputePayment;
use nivra_schema::schema::{dispute, dispute_payment};
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::pipeline::sequential::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_indexer_alt_framework::postgres::{Connection, Db};
use sui_types::transaction::TransactionDataAPI;
use diesel_async::RunQueryDsl;
use diesel::prelude::*;

use crate::NivraEnv;
use crate::handlers::has_nivra_events;
use crate::models::nivra::dispute::DisputePaymentEvent;
use crate::traits::MoveStruct;


pub struct DisputePaymentHandler {
    env: NivraEnv,
}

impl DisputePaymentHandler {
    pub fn new(env: NivraEnv) -> Self {
        Self { env }
    }
}

#[async_trait]
impl Processor for DisputePaymentHandler {
    const NAME: &'static str = "dispute_payment_handler";
    type Value = NewDisputePayment;

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
                if !DisputePaymentEvent::matches_event_type(&ev.type_, self.env) {
                    continue;
                }

                let event: DisputePaymentEvent = bcs::from_bytes(&ev.contents)?;
                let data = NewDisputePayment { 
                    dispute_id: event.dispute.to_string(), 
                    party: event.party.to_string(), 
                    amount: event.amount as i64, 
                    payment_type: event.event_type as i16, 
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
impl Handler for DisputePaymentHandler {
    type Store = Db;
    type Batch = Vec<Self::Value>;

    fn batch(&self, batch: &mut Self::Batch, values: std::vec::IntoIter<Self::Value>) {
        batch.extend(values);
    }

    async fn commit<'a>(&self, batch: &Self::Batch, conn: &mut Connection<'a>) -> anyhow::Result<usize> {

        for payment in batch.iter() {
            diesel::update(dispute::table.find(payment.dispute_id.clone()))
                .set(dispute::last_payer.eq(payment.party.clone()))
                .execute(conn)
                .await?;
        }

        let inserted = diesel::insert_into(dispute_payment::table)
            .values(batch)
            .on_conflict_do_nothing()
            .execute(conn)
            .await?;

        Ok(inserted)
    }
}