module nivra::dispute;

use std::ascii::String;
use sui::linked_table::LinkedTable;
use sui::clock::Clock;
use seal::bf_hmac_encryption::{
    EncryptedObject,
};

public struct VoterDetails has copy, drop, store {
    stake: u64,
    vote: Option<EncryptedObject>,
}

public struct TimeTable has copy, drop, store {
    round_init_ms: u64,
    evidence_period_ms: u64,
    voting_period_ms: u64,
    appeal_period_ms: u64,
}

public struct Dispute has key {
    id: UID,
    contract: ID,
    round: u16,
    timetable: TimeTable,
    max_appeals: u8,
    parties: vector<address>,
    voters: LinkedTable<address, VoterDetails>,
    options: vector<String>,
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
}

public(package) fun create_voter_details(stake: u64): VoterDetails {
    VoterDetails {
        stake,
        vote: std::option::none(),
    }
}

public(package) fun create_dispute(
    contract: ID,
    evidence_period_ms: u64,
    voting_period_ms: u64,
    appeal_period_ms: u64,
    max_appeals: u8,
    parties: vector<address>,
    voters: LinkedTable<address, VoterDetails>,
    options: vector<String>,
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
    clock: &Clock,
    ctx: &mut TxContext,
): Dispute {
    Dispute {
        id: object::new(ctx),
        contract,
        round: 1,
        timetable: TimeTable {
            round_init_ms: clock.timestamp_ms(),
            evidence_period_ms,
            voting_period_ms,
            appeal_period_ms,
        },
        max_appeals,
        parties,
        voters,
        options,
        key_servers,
        public_keys,
    }
}

public(package) fun share_dispute(dispute: Dispute) {
    transfer::share_object(dispute);
}