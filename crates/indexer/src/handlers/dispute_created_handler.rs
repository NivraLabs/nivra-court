use std::collections::HashSet;
use std::sync::Arc;

use async_trait::async_trait;
use chrono::Utc;
use diesel::upsert::excluded;
use nivra_schema::constants::{DISPUTE_OPENED, DISPUTE_OPENING_FEE, DISPUTE_STATUS_RESPONSE, START_RESPONSE_PERIOD};
use nivra_schema::models::{Dispute, DisputeParty, NewDisputeEvent, NewDisputePayment, NewPartyNotification, PartyStats};
use nivra_schema::schema::{dispute, dispute_event, dispute_party, dispute_payment, party_notification, party_stats};
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::pipeline::sequential::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_indexer_alt_framework::postgres::{Connection, Db};
use sui_types::transaction::TransactionDataAPI;
use diesel_async::RunQueryDsl;
use diesel::prelude::*;

use crate::NivraEnv;
use crate::handlers::has_nivra_events;
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

            let checkpoint_timestamp_ms = checkpoint.summary.timestamp_ms as i64;

            for ev in events.data.iter() {
                if !DisputeCreatedEvent::matches_event_type(&ev.type_, self.env) {
                    continue;
                }

                let event: DisputeCreatedEvent = bcs::from_bytes(&ev.contents)?;
                let data = Dispute { 
                    dispute_id: event.dispute.to_string(), 
                    contract_id: event.contract.to_string(), 
                    court_id: event.court.to_string(),
                    dispute_status: DISPUTE_STATUS_RESPONSE,
                    vote_result: None,
                    winner_option: None,
                    winner_party: None,
                    current_round: 0,
                    appeals_used: 0,
                    max_appeals: event.max_appeals as i16, 
                    initiator: event.initiator.to_string(),
                    last_payer: event.initiator.to_string(), 
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
                    checkpoint_timestamp_ms,
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
        let mut dispute_parties: Vec<DisputeParty> = Vec::new();
        let mut party_notifications: Vec<NewPartyNotification> = Vec::new();
        let mut party_stats_updates: Vec<PartyStats> = Vec::new();

        for dispute in batch.iter() {
            dispute_payments.push(NewDisputePayment { 
                dispute_id: dispute.dispute_id.clone(), 
                party: dispute.initiator.clone(), 
                amount: dispute.dispute_fee, 
                payment_type: DISPUTE_OPENING_FEE, 
                sender: dispute.sender.clone(), 
                checkpoint_timestamp_ms: dispute.checkpoint_timestamp_ms,
            });

            dispute_events.push(NewDisputeEvent { 
                dispute_id: dispute.dispute_id.clone(), 
                event_type: START_RESPONSE_PERIOD,
                result: Option::None,
                votes_per_option: Option::None,
                timestamp: dispute.round_init_ms,
                sender: dispute.sender.clone(), 
                checkpoint_timestamp_ms: dispute.checkpoint_timestamp_ms,
            });

            let parties: Vec<DisputeParty> = dispute.options_party_mapping.clone()
                .into_iter()
                .collect::<HashSet<String>>()
                .into_iter()
                .map(|unique_addr| DisputeParty { 
                    dispute_id: dispute.dispute_id.clone(), 
                    party: unique_addr,
                    checkpoint_timestamp_ms: dispute.checkpoint_timestamp_ms,
                })
                .collect();

            let party_b = parties.iter()
                .find(|party| party.party != dispute.initiator)
                .map(|party| &party.party)
                .unwrap()
                .to_owned();

            for party in parties.into_iter() {
                party_stats_updates.push(PartyStats { 
                    party: party.party.clone(), 
                    total_cases: 1, 
                    cases_won: 0, 
                    cases_lost: 0, 
                    cases_cancelled: 0, 
                });
                dispute_parties.push(party);
            }

            party_notifications.push(NewPartyNotification { 
                party: party_b, 
                dispute: Some(dispute.dispute_id.clone()), 
                notification_type: DISPUTE_OPENED, 
                custom_msg: Some(dispute.dispute_fee.to_string()), 
                valid_timestamp_ms: dispute.round_init_ms as i64, 
                expires_timestamp_ms: dispute.round_init_ms as i64 + dispute.response_period_ms as i64, 
                checked: false,
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

        let _ = diesel::insert_into(dispute_party::table)
            .values(dispute_parties)
            .on_conflict_do_nothing()
            .execute(conn)
            .await?;

        let _ = diesel::insert_into(party_notification::table)
            .values(party_notifications)
            .on_conflict_do_nothing()
            .execute(conn)
            .await?;

        let _ = diesel::insert_into(party_stats::table)
            .values(party_stats_updates)
            .on_conflict(party_stats::party)
            .do_update()
            .set((
                party_stats::total_cases.eq(party_stats::total_cases + excluded(party_stats::total_cases)),
                party_stats::modified_at.eq(Utc::now().naive_utc()),
            ))
            .execute(conn)
            .await?;

        Ok(inserted)
    }
}