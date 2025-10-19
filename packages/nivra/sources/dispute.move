module nivra::dispute;

use std::ascii::String;
use sui::linked_table::{Self, LinkedTable};
use seal::bf_hmac_encryption::{
    EncryptedObject,
};

public struct VoterDetails has copy, drop, store {
    stake: u64,
    vote: Option<EncryptedObject>,
}

public struct Dispute has key {
    id: UID,
    round: u16,
    max_appeals: u8,
    parties: vector<address>,
    voters: LinkedTable<address, VoterDetails>,
    options: vector<String>,
    evidence_period: u64,
    voting_period: u64,
    appeal_period: u64,
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
}