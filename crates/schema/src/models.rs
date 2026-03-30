use diesel::{Identifiable, Insertable, Queryable, Selectable, deserialize::FromSqlRow, expression::AsExpression, sql_types::SmallInt};

use crate::schema::{admin_vote, court, dispute, dispute_event, dispute_nivster, dispute_payment, nivster};

#[derive(Queryable, Selectable, Insertable, Identifiable, Debug)]
#[diesel(table_name = admin_vote, primary_key(vote_id))]
pub struct AdminVote {
    vote_id: String,
    vote_type: AdminVoteType,
    vote_enforced: bool,
    sender: String,
    checkpoint: i64,
    checkpoint_timestamp_ms: i64,
    package: String,
    digest: String,
    event_digest: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, AsExpression, FromSqlRow)]
#[diesel(sql_type = SmallInt)]
#[repr(i16)]
pub enum AdminVoteType {
    AddAdmin = 1,
    BlacklistAdmin = 2,
    ChangeTreasury = 3,
    ChangeTreshold = 4,
}

#[derive(Queryable, Selectable, Insertable, Identifiable, Debug)]
#[diesel(table_name = court, primary_key(court_id))]
pub struct Court {
    court_id: String,
    name: String,
    category: String,
    description: String,
    ai_court: bool,
    response_period_ms: i64,
    draw_period_ms: i64,
    voting_period_ms: i64,
    appeal_period_ms: i64,
    min_stake: i64,
    reputation_requirement: i16,
    init_nivster_count: i16,
    sanction_model: i16,
    coefficient: i16,
    dispute_fee: i64,
    treasury_share: i16,
    treasury_share_nvr: i16,
    empty_vote_penalty: i16,
    status: CourtStatus,
    key_servers: Vec<String>,
    public_keys: Vec<String>,
    threshold: i16,
    sender: String,
    checkpoint: i64,
    checkpoint_timestamp_ms: i64,
    package: String,
    digest: String,
    event_digest: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, AsExpression, FromSqlRow)]
#[diesel(sql_type = SmallInt)]
#[repr(i16)]
pub enum CourtStatus {
    Active = 0,
    Halted = 1,
}

#[derive(Queryable, Selectable, Insertable, Identifiable, Debug)]
#[diesel(table_name = nivster, primary_key(address))]
pub struct Nivster {
    address: String,
}

#[derive(Queryable, Selectable, Insertable, Identifiable, Debug)]
#[diesel(table_name = dispute, primary_key(dispute_id))]
pub struct Dispute {
    pub dispute_id: String,
    pub contract_id: String,
    pub court_id: String,
    pub status: DisputeStatus,
    pub round: i16,
    pub appeals_used: i16,
    pub result: Option<Vec<i32>>,
    pub winner_option: Option<String>,
    pub cancellation_reason: Option<DisputeCancellationReason>,
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
    pub key_servers: Vec<String>,
    pub public_keys: Vec<String>,
    pub threshold: i16,
    pub sender: String,
    pub checkpoint: i64,
    pub checkpoint_timestamp_ms: i64,
    pub package: String,
    pub digest: String,
    pub event_digest: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, AsExpression, FromSqlRow)]
#[diesel(sql_type = SmallInt)]
#[repr(i16)]
pub enum DisputeStatus {
    Response = 1,
    Draw = 2,
    Active = 3,
    Tie = 4,
    Tallied = 5,
    Completed = 6,
    CompletedOneSided = 7,
    Cancelled = 8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, AsExpression, FromSqlRow)]
#[diesel(sql_type = SmallInt)]
#[repr(i16)]
pub enum DisputeCancellationReason {
    NivstersNotDrawn = 1,
    VotesNotCounted = 2,
    UnresolvedTie = 3,
}

#[derive(Queryable, Selectable, Insertable, Identifiable, Debug)]
#[diesel(table_name = dispute_event, primary_key(id))]
pub struct DisputeEvent {
    pub id: i64,
    pub dispute_id: String,
    pub event_type: DisputeEventType,
    pub sender: String,
    pub checkpoint: i64,
    pub checkpoint_timestamp_ms: i64,
    pub package: String,
    pub digest: String,
    pub event_digest: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, AsExpression, FromSqlRow)]
#[diesel(sql_type = SmallInt)]
#[repr(i16)]
pub enum DisputeEventType {
    ResponsePeriodStarted = 1,
    DrawPeriodStarted = 2,
    NewRoundStarted = 3,
    TieRoundStarted = 4,
    VoteFinalized = 5,
    DisputeCancelled = 6,
    DisputeResolvedOnesided = 7,
    DisputeCompleted = 8,
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

#[derive(Queryable, Selectable, Insertable, Identifiable, Debug)]
#[diesel(table_name = dispute_payment, primary_key(id))]
pub struct DisputePayment {
    pub id: i64,
    pub dispute_id: String,
    pub party: String,
    pub amount: i64,
    pub payment_type: DisputePaymentType,
    pub sender: String,
    pub checkpoint: i64,
    pub checkpoint_timestamp_ms: i64,
    pub package: String,
    pub digest: String,
    pub event_digest: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, AsExpression, FromSqlRow)]
#[diesel(sql_type = SmallInt)]
#[repr(i16)]
pub enum DisputePaymentType {
    OpeningFee = 1,
    AppealFee = 2,
    Refund = 3,
}