use diesel::{Identifiable, Insertable, Queryable, Selectable, deserialize::FromSqlRow, expression::AsExpression, sql_types::SmallInt};

use crate::schema::{admin_vote, court};

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
    key_servers: Vec<Option<String>>,
    public_keys: Vec<Option<String>>,
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