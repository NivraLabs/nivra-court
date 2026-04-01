use chrono::NaiveDateTime;
use diesel::{AsChangeset, Identifiable, Insertable, Queryable, Selectable};
use serde::Deserialize;
use sui_field_count::FieldCount;

use crate::schema::{admin_vote, balance_event, court, dispute, dispute_event, dispute_nivster, dispute_payment, evidence, worker_pool};

#[derive(Queryable, Selectable, Insertable, Identifiable, FieldCount, Debug)]
#[diesel(table_name = admin_vote, primary_key(vote_id))]
pub struct AdminVote {
    pub vote_id: String,
    pub vote_type: i16,
    pub vote_enforced: bool,
    pub sender: String,
    pub checkpoint: i64,
    pub checkpoint_timestamp_ms: i64,
    pub package: String,
    pub digest: String,
    pub event_digest: String,
}

#[derive(Queryable, Selectable, Insertable, Identifiable, FieldCount, Debug)]
#[diesel(table_name = court, primary_key(court_id))]
pub struct Court {
    pub court_id: String,
    pub name: String,
    pub category: String,
    pub description: String,
    pub ai_court: bool,
    pub response_period_ms: i64,
    pub draw_period_ms: i64,
    pub evidence_period_ms: i64,
    pub voting_period_ms: i64,
    pub appeal_period_ms: i64,
    pub min_stake: i64,
    pub reputation_requirement: i16,
    pub init_nivster_count: i16,
    pub sanction_model: i16,
    pub coefficient: i16,
    pub dispute_fee: i64,
    pub treasury_share: i16,
    pub treasury_share_nvr: i16,
    pub empty_vote_penalty: i16,
    pub status: i16,
    pub sender: String,
    pub checkpoint: i64,
    pub checkpoint_timestamp_ms: i64,
    pub package: String,
    pub digest: String,
    pub event_digest: String,
}

#[derive(AsChangeset)]
#[diesel(table_name = court, primary_key(court_id))]
pub struct CourtMetadataChangeset {
    pub court_id: String,
    pub name: String,
    pub category: String,
    pub description: String,
    pub ai_court: bool,
}

#[derive(AsChangeset)]
#[diesel(table_name = court, primary_key(court_id))]
pub struct CourtTimetableChangeset {
    pub court_id: String,
    pub response_period_ms: i64,
    pub draw_period_ms: i64,
    pub evidence_period_ms: i64,
    pub voting_period_ms: i64,
    pub appeal_period_ms: i64,
}

#[derive(AsChangeset)]
#[diesel(table_name = court, primary_key(court_id))]
pub struct CourtEconomicsChangeset {
    pub court_id: String,
    pub min_stake: i64,
    pub reputation_requirement: i16,
    pub init_nivster_count: i16,
    pub sanction_model: i16,
    pub coefficient: i16,
    pub dispute_fee: i64,
    pub treasury_share: i16,
    pub treasury_share_nvr: i16,
    pub empty_vote_penalty: i16,
}

#[derive(AsChangeset)]
#[diesel(table_name = court, primary_key(court_id))]
pub struct CourtOperationChangeset {
    pub court_id: String,
    pub status: i16,
}

#[derive(Queryable, Selectable, Insertable, Identifiable, FieldCount, Debug)]
#[diesel(table_name = dispute, primary_key(dispute_id))]
pub struct Dispute {
    pub dispute_id: String,
    pub contract_id: String,
    pub court_id: String,
    pub status: i16,
    pub round: i16,
    pub appeals_used: i16,
    pub result: Option<Vec<i32>>,
    pub winner_option: Option<String>,
    pub cancellation_reason: Option<i16>,
    pub max_appeals: i16,
    pub initiator: String,
    pub options: Vec<String>,
    pub options_party_mapping: Vec<String>,
    pub round_init_ms: i64,
    pub response_period_ms: i64,
    pub draw_period_ms: i64,
    pub evidence_period_ms: i64,
    pub voting_period_ms: i64,
    pub appeal_period_ms: i64,
    pub init_nivster_count: i16,
    pub sanction_model: i16,
    pub coefficient: i16,
    pub dispute_fee: i64,
    pub treasury_share: i16,
    pub treasury_share_nvr: i16,
    pub empty_vote_penalty: i16,
    pub sender: String,
    pub checkpoint: i64,
    pub checkpoint_timestamp_ms: i64,
    pub package: String,
    pub digest: String,
    pub event_digest: String,
}

#[derive(Queryable, Selectable, Identifiable, Debug)]
#[diesel(table_name = dispute_event, primary_key(id))]
pub struct DisputeEvent {
    pub id: i64,
    pub dispute_id: String,
    pub event_type: i16,
    pub sender: String,
    pub checkpoint: i64,
    pub checkpoint_timestamp_ms: i64,
    pub package: String,
    pub digest: String,
    pub event_digest: String,
}

#[derive(Deserialize, Insertable)]
#[diesel(table_name = dispute_event)]
pub struct NewDisputeEvent {
    pub dispute_id: String,
    pub event_type: i16,
    pub sender: String,
    pub checkpoint: i64,
    pub checkpoint_timestamp_ms: i64,
    pub package: String,
    pub digest: String,
    pub event_digest: String,
}

#[derive(Queryable, Selectable, Insertable, Identifiable, Debug)]
#[diesel(table_name = dispute_nivster)]
#[diesel(primary_key(dispute_id, nivster))]
pub struct DisputeNivster {
    pub dispute_id: String,
    pub nivster: String,
    pub votes: i16,
    pub stake: i64,
}

#[derive(Queryable, Selectable, Identifiable, Debug)]
#[diesel(table_name = dispute_payment, primary_key(id))]
pub struct DisputePayment {
    pub id: i64,
    pub dispute_id: String,
    pub party: String,
    pub amount: i64,
    pub payment_type: i16,
    pub sender: String,
    pub checkpoint: i64,
    pub checkpoint_timestamp_ms: i64,
    pub package: String,
    pub digest: String,
    pub event_digest: String,
}

#[derive(Deserialize, Insertable)]
#[diesel(table_name = dispute_payment)]
pub struct NewDisputePayment {
    pub dispute_id: String,
    pub party: String,
    pub amount: i64,
    pub payment_type: i16,
    pub sender: String,
    pub checkpoint: i64,
    pub checkpoint_timestamp_ms: i64,
    pub package: String,
    pub digest: String,
    pub event_digest: String,
}

#[derive(Queryable, Selectable, Identifiable, Debug)]
#[diesel(table_name = balance_event, primary_key(id))]
pub struct BalanceEvent {
    pub id: i64,
    pub nivster: String,
    pub court: String,
    pub event_type: i16,
    pub amount_nvr: i64,
    pub amount_sui: i64,
    pub lock_nvr: i64,
    pub dispute_id: Option<String>,
    pub sender: String,
    pub checkpoint: i64,
    pub checkpoint_timestamp_ms: i64,
    pub package: String,
    pub digest: String,
    pub event_digest: String,
}

#[derive(Deserialize, Insertable)]
#[diesel(table_name = balance_event)]
pub struct NewBalanceEvent {
    pub nivster: String,
    pub court: String,
    pub event_type: i16,
    pub amount_nvr: i64,
    pub amount_sui: i64,
    pub lock_nvr: i64,
    pub dispute_id: Option<String>,
    pub sender: String,
    pub checkpoint: i64,
    pub checkpoint_timestamp_ms: i64,
    pub package: String,
    pub digest: String,
    pub event_digest: String,
}

#[derive(Queryable, Selectable, Insertable, Identifiable, Debug)]
#[diesel(table_name = worker_pool)]
#[diesel(primary_key(court, nivster))]
pub struct WorkerPool {
    pub court: String,
    pub nivster: String,
    pub active: bool,
}

#[derive(Queryable, Selectable, Insertable, Identifiable, Debug)]
#[diesel(table_name = evidence, primary_key(evidence_id))]
pub struct Evidence {
    pub evidence_id: String,
    pub dispute_id: String,
    pub owner: String,
    pub description: String,
    pub src: Option<String>,
    pub file_name: Option<String>,
    pub file_type: Option<String>,
    pub file_subtype: Option<String>,
    pub encrypted: bool,
    pub censored: bool,
    pub modified: Option<NaiveDateTime>,
    pub sender: String,
    pub checkpoint: i64,
    pub checkpoint_timestamp_ms: i64,
    pub package: String,
    pub digest: String,
    pub event_digest: String,
}