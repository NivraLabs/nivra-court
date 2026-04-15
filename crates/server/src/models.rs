use serde::Serialize;


#[derive(Serialize, Debug)]
pub struct CourtOverviewResponse {
    pub status: i16,
    pub name: String,
    pub ai_court: bool,
    pub response_period_ms: i64,
    pub evidence_period_ms: i64,
    pub voting_period_ms: i64,
    pub appeal_period_ms: i64,
    pub init_nivster_count: i16,
    pub dispute_fee: i64,
    pub worker_pool_count: i64,
}

#[derive(Serialize, Debug)]
pub struct PartyDisputesByAddressResponse {
    pub active_disputes: Vec<PartyDisputeResponse>,
    pub active_disputes_count: i64,
    pub resolved_disputes: Vec<PartyDisputeResponse>,
    pub resolved_disputes_count: i64,
}

#[derive(Serialize, Debug)]
pub struct PartyDisputeResponse {
    pub dispute_id: String,
    pub contract_id: String,
    pub court_id: String,
    pub court_name: String,
    pub dispute_status: i16,
    pub winner_option: Option<String>,
    pub winner_party: Option<String>,
    pub current_round: i16,
    pub appeals_used: i16,
    pub options: Vec<String>,
    pub options_party_mapping: Vec<String>,
    pub round_init_ms: i64,
    pub response_period_ms: i64,
    pub draw_period_ms: i64,
    pub evidence_period_ms: i64,
    pub voting_period_ms: i64,
    pub appeal_period_ms: i64,
    pub checkpoint_timestamp_ms: i64,
}