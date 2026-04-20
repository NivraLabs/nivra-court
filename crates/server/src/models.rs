use nivra_schema::models::{DisputeDetailsResponse, DisputeOutput, EvidenceOutput};
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
    pub description: String,
    pub dispute_status: i16,
    pub winner_option: Option<String>,
    pub winner_party: Option<String>,
    pub current_round: i16,
    pub last_payer: String,
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

impl PartyDisputeResponse {
    pub fn from(
        court_name: String,
        dispute_details: DisputeDetailsResponse,
    ) -> Self {
        PartyDisputeResponse { 
            dispute_id: dispute_details.dispute_id, 
            contract_id: dispute_details.contract_id, 
            court_id: dispute_details.court_id, 
            court_name,
            description: dispute_details.description,
            dispute_status: dispute_details.dispute_status, 
            winner_option: dispute_details.winner_option, 
            winner_party: dispute_details.winner_party, 
            current_round: dispute_details.current_round,
            last_payer: dispute_details.last_payer,
            appeals_used: dispute_details.appeals_used, 
            options: dispute_details.options
                .into_iter()
                .map(|opt| opt.unwrap())
                .collect(), 
            options_party_mapping: dispute_details.options_party_mapping
                .into_iter()
                .map(|addr| addr.unwrap())
                .collect(), 
            round_init_ms: dispute_details.round_init_ms, 
            response_period_ms: dispute_details.response_period_ms, 
            draw_period_ms: dispute_details.draw_period_ms, 
            evidence_period_ms: dispute_details.evidence_period_ms, 
            voting_period_ms: dispute_details.voting_period_ms, 
            appeal_period_ms: dispute_details.appeal_period_ms, 
            checkpoint_timestamp_ms: dispute_details.checkpoint_timestamp_ms, 
        }
    }
}

#[derive(Serialize, Debug)]
pub struct DisputeResponse {
    pub contract_id: String,
    pub court_id: String,
    pub court_name: String,
    pub description: String,
    pub dispute_status: i16,
    pub vote_result: Option<Vec<i32>>,
    pub winner_option: Option<String>,
    pub winner_party: Option<String>,
    pub current_round: i16,
    pub appeals_used: i16,
    pub max_appeals: i16,
    pub initiator: String,
    pub last_payer: String,
    pub options: Vec<String>,
    pub options_party_mapping: Vec<String>,
    pub timetable: Timetable,
    pub economics: Economics,
    pub evidence: Vec<EvidenceResponse>,
}

impl DisputeResponse {
    pub fn from(
        dispute: DisputeOutput,
        court_name: String,
        evidence: Vec<EvidenceOutput>,
    ) -> Self {
        DisputeResponse { 
            contract_id: dispute.contract_id, 
            court_id: dispute.court_id, 
            court_name, 
            description: dispute.description, 
            dispute_status: dispute.dispute_status, 
            vote_result: dispute.vote_result.map(|v| v.into_iter()
                .map(|opt| opt.unwrap())
                .collect()
            ), 
            winner_option: dispute.winner_option, 
            winner_party: dispute.winner_party, 
            current_round: dispute.current_round, 
            appeals_used: dispute.appeals_used, 
            max_appeals: dispute.max_appeals, 
            initiator: dispute.initiator, 
            last_payer: dispute.last_payer, 
            options: dispute.options
                .into_iter()
                .map(|opt| opt.unwrap())
                .collect(), 
            options_party_mapping: dispute.options_party_mapping
                .into_iter()
                .map(|mapping| mapping.unwrap())
                .collect(), 
            timetable: Timetable { 
                round_init_ms: dispute.round_init_ms, 
                response_period_ms: dispute.response_period_ms, 
                draw_period_ms: dispute.draw_period_ms, 
                evidence_period_ms: dispute.evidence_period_ms, 
                voting_period_ms: dispute.voting_period_ms, 
                appeal_period_ms: dispute.appeal_period_ms, 
            }, 
            economics: Economics { 
                init_nivster_count: dispute.init_nivster_count, 
                sanction_model: dispute.sanction_model, 
                coefficient: dispute.coefficient, 
                dispute_fee: dispute.dispute_fee, 
                treasury_share: dispute.treasury_share, 
                treasury_share_nvr: dispute.treasury_share_nvr, 
                empty_vote_penalty: dispute.empty_vote_penalty, 
            }, 
            evidence: evidence
                .into_iter()
                .map(|ev| EvidenceResponse { 
                    evidence_id: ev.evidence_id, 
                    owner: ev.owner, 
                    description: ev.description, 
                    src: if ev.censored { None } else { ev.src }, 
                    file_name: ev.file_name, 
                    file_type: ev.file_type, 
                    file_subtype: ev.file_subtype, 
                    encrypted: ev.encrypted, 
                    censored: ev.censored, 
                    modified: ev.modified
                        .map(|ndt| ndt.and_utc().timestamp()), 
                    submitted: ev.checkpoint_timestamp_ms, 
                })
                .collect()
        }
    }
}

#[derive(Serialize, Debug)]
pub struct Timetable {
    pub round_init_ms: i64,
    pub response_period_ms: i64,
    pub draw_period_ms: i64,
    pub evidence_period_ms: i64,
    pub voting_period_ms: i64,
    pub appeal_period_ms: i64,
}

#[derive(Serialize, Debug)]
pub struct Economics {
    pub init_nivster_count: i16,
    pub sanction_model: i16,
    pub coefficient: i16,
    pub dispute_fee: i64,
    pub treasury_share: i16,
    pub treasury_share_nvr: i16,
    pub empty_vote_penalty: i16,
}

#[derive(Serialize, Debug)]
pub struct EvidenceResponse {
    pub evidence_id: String,
    pub owner: String,
    pub description: String,
    pub src: Option<String>,
    pub file_name: Option<String>,
    pub file_type: Option<String>,
    pub file_subtype: Option<String>,
    pub encrypted: bool,
    pub censored: bool,
    pub modified: Option<i64>,
    pub submitted: i64,
}