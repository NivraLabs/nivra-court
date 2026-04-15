use crate::traits::MoveStruct;
use serde::{Deserialize, Serialize};
use sui_types::base_types::ObjectID;
use sui_sdk_types::Address;

pub mod nivra {
    use super::*;

    pub mod registry {
        use super::*;

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct AdminVoteEvent {
            pub vote: ObjectID,
            pub vote_type: u8,
        }

        impl MoveStruct for AdminVoteEvent {
            const MODULE: &'static str = "registry";
            const NAME: &'static str = "AdminVoteEvent";
        }

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct AdminVoteFinalizedEvent {
            pub vote: ObjectID,
        }

        impl MoveStruct for AdminVoteFinalizedEvent {
            const MODULE: &'static str = "registry";
            const NAME: &'static str = "AdminVoteFinalizedEvent";
        }
    }

    pub mod court {
        use super::*;

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct Metadata {
            pub name: String,
            pub category: String,
            pub description: String,
            pub ai_court: bool,
        }

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct Timetable {
            pub response_period_ms: u64,
            pub draw_period_ms: u64,
            pub evidence_period_ms: u64,
            pub voting_period_ms: u64,
            pub appeal_period_ms: u64,
        }

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct Economics {
            pub min_stake: u64,
            pub reputation_requirement: u64,
            pub init_nivster_count: u64,
            pub sanction_model: u64,
            pub coefficient: u64,
            pub dispute_fee: u64,
            pub treasury_share: u64,
            pub treasury_share_nvr: u64,
            pub empty_vote_penalty: u64,
        }

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct CourtCreatedEvent {
            pub court: ObjectID,
            pub metadata: Metadata,
            pub timetable: Timetable,
            pub economics: Economics,
            pub status: u8,
        }

        impl MoveStruct for CourtCreatedEvent {
            const MODULE: &'static str = "court";
            const NAME: &'static str = "CourtCreatedEvent";
        }

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct CourtMetadataChanged {
            pub court: ObjectID,
            pub metadata: Metadata,
        }

        impl MoveStruct for CourtMetadataChanged {
            const MODULE: &'static str = "court";
            const NAME: &'static str = "CourtMetadataChanged";
        }

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct CourtTimetableChanged {
            pub court: ObjectID,
            pub timetable: Timetable,
        }

        impl MoveStruct for CourtTimetableChanged {
            const MODULE: &'static str = "court";
            const NAME: &'static str = "CourtTimetableChanged";
        }

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct CourtEconomicsChanged {
            pub court: ObjectID,
            pub economics: Economics,
        }

        impl MoveStruct for CourtEconomicsChanged {
            const MODULE: &'static str = "court";
            const NAME: &'static str = "CourtEconomicsChanged";
        }

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct CourtOperationChanged {
            pub court: ObjectID,
            pub status: u8,
        }

        impl MoveStruct for CourtOperationChanged {
            const MODULE: &'static str = "court";
            const NAME: &'static str = "CourtOperationChanged";
        }

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct BalanceEvent {
            pub nivster: Address,
            pub court: ObjectID,
            pub event_type: u8,
            pub amount_nvr: u64,
            pub amount_sui: u64,
            pub lock_nvr: u64,
            pub dispute_id: Option<ObjectID>,              
        }

        impl MoveStruct for BalanceEvent {
            const MODULE: &'static str = "court";
            const NAME: &'static str = "BalanceEvent";
        }

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct WorkerPoolEvent {
            pub court: ObjectID,
            pub nivster: Address,
            pub entry: bool,
        }

        impl MoveStruct for WorkerPoolEvent {
            const MODULE: &'static str = "court";
            const NAME: &'static str = "WorkerPoolEvent";
        }
    }

    pub mod dispute {
        use super::*;

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct Schedule {
            pub round_init_ms: u64,
            pub response_period_ms: u64,
            pub draw_period_ms: u64,
            pub evidence_period_ms: u64,
            pub voting_period_ms: u64,
            pub appeal_period_ms: u64,
            pub evidence_swap: u64,
        }

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct Economics {
            pub init_nivster_count: u64,
            pub sanction_model: u64,
            pub coefficient: u64,
            pub dispute_fee: u64,
            pub treasury_share: u64,
            pub treasury_share_nvr: u64,
            pub empty_vote_penalty: u64,
        }

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct DisputeCreatedEvent {
            pub dispute: ObjectID,
            pub contract: ObjectID,
            pub court: ObjectID,
            pub description: String,
            pub max_appeals: u8,
            pub initiator: Address,
            pub options: Vec<String>,
            pub parties: Vec<Address>,
            pub schedule: Schedule,
            pub economics: Economics,
        }

        impl MoveStruct for DisputeCreatedEvent {
            const MODULE: &'static str = "dispute";
            const NAME: &'static str = "DisputeCreatedEvent";
        }

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct DisputePaymentEvent {
            pub dispute: ObjectID,
            pub amount: u64,
            pub party: Address,
            pub event_type: u64,
        }

        impl MoveStruct for DisputePaymentEvent {
            const MODULE: &'static str = "dispute";
            const NAME: &'static str = "DisputePaymentEvent";
        }

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct NivsterSelectionEvent {
            pub dispute: ObjectID,
            pub nivster: Address,
            pub locked_amount: u64,
        }

        impl MoveStruct for NivsterSelectionEvent {
            const MODULE: &'static str = "dispute";
            const NAME: &'static str = "NivsterSelectionEvent";
        }

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct DisputeEvent {
            pub dispute: ObjectID,
            pub event_type: u64,
            pub result: Option<String>,
            pub votes_per_option: Option<Vec<u64>>,
            pub timestamp: u64,
        }

        impl MoveStruct for DisputeEvent {
            const MODULE: &'static str = "dispute";
            const NAME: &'static str = "DisputeEvent";
        }
    }

    pub mod evidence {
        use super::*;

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct EvidenceCreatedEvent {
            pub dispute: ObjectID,
            pub evidence: ObjectID,
            pub party: Address,
            pub description: String,
            pub src: Option<String>,
            pub file_name: Option<String>,
            pub file_type: Option<String>,
            pub file_subtype: Option<String>,
            pub encrypted: bool,
        }

        impl MoveStruct for EvidenceCreatedEvent {
            const MODULE: &'static str = "evidence";
            const NAME: &'static str = "EvidenceCreatedEvent";
        }

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct EvidenceModifiedEvent {
            pub evidence: ObjectID,
            pub description: String,
            pub src: Option<String>,
            pub file_name: Option<String>,
            pub file_type: Option<String>,
            pub file_subtype: Option<String>,
            pub encrypted: bool,
        }

        impl MoveStruct for EvidenceModifiedEvent {
            const MODULE: &'static str = "evidence";
            const NAME: &'static str = "EvidenceModifiedEvent";
        }

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct EvidenceRemovedEvent {
            pub evidence: ObjectID,
        }

        impl MoveStruct for EvidenceRemovedEvent {
            const MODULE: &'static str = "evidence";
            const NAME: &'static str = "EvidenceRemovedEvent";
        }
    }
}