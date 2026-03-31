use crate::traits::MoveStruct;
use serde::{Deserialize, Serialize};
use sui_types::base_types::ObjectID;

pub mod Nivra {
    use super::*;

    pub mod Registry {
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
}