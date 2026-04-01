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
}