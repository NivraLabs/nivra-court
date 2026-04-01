use std::sync::Arc;

use async_trait::async_trait;
use nivra_schema::constants::{DISPUTE_OPENING_FEE, START_RESPONSE_PERIOD};
use nivra_schema::models::{Dispute, NewDisputeEvent, NewDisputePayment};
use nivra_schema::schema::{dispute, dispute_event, dispute_payment};
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::pipeline::sequential::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_indexer_alt_framework::postgres::{Connection, Db};
use sui_types::transaction::TransactionDataAPI;
use diesel_async::RunQueryDsl;

use crate::NivraEnv;
use crate::handlers::{has_nivra_events, try_extract_move_call_package};
use crate::models::nivra::dispute::DisputeCreatedEvent;
use crate::traits::MoveStruct;


pub struct DisputeCreatedHandler {
    env: NivraEnv,
}

impl DisputeCreatedHandler {
    pub fn new(env: NivraEnv) -> Self {
        Self { env }
    }
}

#[async_trait]
impl Processor for DisputeCreatedHandler {
    const NAME: &'static str = "dispute_created_handler";
    type Value = Dispute;

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> anyhow::Result<Vec<Self::Value>> {
        let mut results = vec![];

        for tx in &checkpoint.transactions {
            if !has_nivra_events(tx, self.env) {
                continue;
            }
            let Some(events) = &tx.events else {
                continue;
            };

            let package = try_extract_move_call_package(tx).unwrap_or_default();
            let checkpoint_timestamp_ms = checkpoint.summary.timestamp_ms as i64;
            let checkpoint_seq = checkpoint.summary.sequence_number as i64;
            let digest = tx.transaction.digest();

            for (index, ev) in events.data.iter().enumerate() {
                if !DisputeCreatedEvent::matches_event_type(&ev.type_, self.env) {
                    continue;
                }

                let event: DisputeCreatedEvent = bcs::from_bytes(&ev.contents)?;
                let data = Dispute { 
                    dispute_id: event.dispute.to_string(), 
                    contract_id: event.contract.to_string(), 
                    court_id: event.court.to_string(),
                    max_appeals: event.max_appeals as i16, 
                    initiator: event.initiator.to_string(), 
                    options: event.options, 
                    options_party_mapping: event.parties.iter().map(|addr| addr.to_string()).collect(), 
                    round_init_ms: event.schedule.round_init_ms as i64, 
                    response_period_ms: event.schedule.response_period_ms as i64, 
                    draw_period_ms: event.schedule.draw_period_ms as i64, 
                    evidence_period_ms: event.schedule.evidence_period_ms as i64, 
                    voting_period_ms: event.schedule.voting_period_ms as i64, 
                    appeal_period_ms: event.schedule.appeal_period_ms as i64, 
                    init_nivster_count: event.economics.init_nivster_count as i16, 
                    sanction_model: event.economics.sanction_model as i16, 
                    coefficient: event.economics.coefficient as i16, 
                    dispute_fee: event.economics.dispute_fee as i64, 
                    treasury_share: event.economics.treasury_share as i16, 
                    treasury_share_nvr: event.economics.treasury_share_nvr as i16, 
                    empty_vote_penalty: event.economics.empty_vote_penalty as i16, 
                    sender: tx.transaction.sender().to_string(), 
                    checkpoint: checkpoint_seq, 
                    checkpoint_timestamp_ms, 
                    package: package.clone(), 
                    digest: digest.to_string(), 
                    event_digest: format!("{digest}{index}"),
                };

                results.push(data);
            }
        }

        Ok(results)
    }
}

#[async_trait]
impl Handler for DisputeCreatedHandler {
    type Store = Db;
    type Batch = Vec<Self::Value>;

    fn batch(&self, batch: &mut Self::Batch, values: std::vec::IntoIter<Self::Value>) {
        batch.extend(values);
    }

    async fn commit<'a>(&self, batch: &Self::Batch, conn: &mut Connection<'a>) -> anyhow::Result<usize> {
        let mut dispute_payments: Vec<NewDisputePayment> = Vec::new();
        let mut dispute_events: Vec<NewDisputeEvent> = Vec::new();

        for dispute in batch.iter() {
            dispute_payments.push(NewDisputePayment { 
                dispute_id: dispute.dispute_id.clone(), 
                party: dispute.initiator.clone(), 
                amount: dispute.dispute_fee, 
                payment_type: DISPUTE_OPENING_FEE, 
                sender: dispute.sender.clone(), 
                checkpoint: dispute.checkpoint, 
                checkpoint_timestamp_ms: dispute.checkpoint_timestamp_ms, 
                package: dispute.package.clone(), 
                digest: dispute.digest.clone(), 
                event_digest: dispute.event_digest.clone(), 
            });

            dispute_events.push(NewDisputeEvent { 
                dispute_id: dispute.dispute_id.clone(), 
                event_type: START_RESPONSE_PERIOD,
                result: Option::None,
                votes_per_option: Option::None,
                sender: dispute.sender.clone(), 
                checkpoint: dispute.checkpoint, 
                checkpoint_timestamp_ms: dispute.checkpoint_timestamp_ms, 
                package: dispute.package.clone(), 
                digest: dispute.digest.clone(), 
                event_digest: dispute.event_digest.clone(), 
            });
        }

        let inserted = diesel::insert_into(dispute::table)
            .values(batch)
            .on_conflict_do_nothing()
            .execute(conn)
            .await?;

        let _ = diesel::insert_into(dispute_payment::table)
            .values(dispute_payments)
            .on_conflict_do_nothing()
            .execute(conn)
            .await?;

        let _ = diesel::insert_into(dispute_event::table)
            .values(dispute_events)
            .on_conflict_do_nothing()
            .execute(conn)
            .await?;

        Ok(inserted)
    }
}