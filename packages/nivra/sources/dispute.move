// © 2025 Nivra Labs Ltd.

module nivra::dispute;

// === Imports ===
use std::string::String;
use sui::{
    linked_table::{Self, LinkedTable},
    clock::Clock,
    vec_map::{Self, VecMap},
    bls12381::g1_from_bytes
};
use seal::bf_hmac_encryption::{
    EncryptedObject,
    parse_encrypted_object,
    VerifiedDerivedKey,
    verify_derived_keys,
    new_public_key,
    PublicKey,
    decrypt
};
use nivra::constants::dispute_status_response;
use std::address;
use nivra::constants::dispute_status_active;

// === Errors ===

const EEvidenceFull: u64 = 1;
const ENotPartyMember: u64 = 2;
const ENoEvidenceFound: u64 = 3;
const ENotEvidencePeriod: u64 = 4;
const EInvalidVote: u64 = 5;
const ENotVotingPeriod: u64 = 6;
const ENotVoter: u64 = 7;
const EVotingPeriodNotEnded: u64 = 8;
const ENotEnoughKeys: u64 = 9;
const EAlreadyFinalized: u64 = 10;
const EInvalidDispute: u64 = 11;

// === Structs ===

public struct PartyCap has key, store {
    id: UID,
    dispute_id: ID,
    party: address,
}

public struct VoterCap has key, store {
    id: UID,
    dispute_id: ID,
    voter: address,
}

public struct VoterDetails has copy, drop, store {
    stake: u64,
    vote: Option<EncryptedObject>,
    decrypted_vote: Option<u8>,
    cap_issued: bool,
}

public struct TimeTable has copy, drop, store {
    round_init_ms: u64,
    response_period_ms: u64,
    evidence_period_ms: u64,
    voting_period_ms: u64,
    appeal_period_ms: u64,
}

public struct Dispute has key {
    id: UID,
    status: u64,
    initiator: address,
    contract: ID,
    court: ID,
    description: String,
    round: u64,
    timetable: TimeTable,
    max_appeals: u8,                            // 0-5 appeals per case.
    appeals_used: u8,
    parties: vector<address>,                   // 2 parties per case.
    evidence: VecMap<address, vector<ID>>,      // Max 3 evidences per party.
    voters: LinkedTable<address, VoterDetails>,
    options: vector<String>,                    // Max 10 + (empty vote) outcomes.
    result: vector<u64>,                        // Vote count of each option.
    party_result: vector<u64>,                  // Vote count of each party.
    winner_option: Option<u8>,
    winner_party: Option<u8>,
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
    threshold: u8,
}

// === Public Functions ===

public fun is_response_period(dispute: &Dispute, clock: &Clock): bool {
    let response_period_end = dispute.timetable.round_init_ms + dispute.timetable.response_period_ms;
    let current_time = clock.timestamp_ms();

    current_time <= response_period_end && dispute.status == dispute_status_response()
}

public fun is_evidence_period(dispute: &Dispute, clock: &Clock): bool {
    let tt = dispute.timetable;
    let evidence_period_end = tt.round_init_ms + tt.response_period_ms + tt.evidence_period_ms;
    let current_time = clock.timestamp_ms();

    // Start the evidence period soon as other party has responded (status = active)
    current_time <= evidence_period_end && dispute.status == dispute_status_active()
}

// === View Functions ===

public fun contract(dispute: &Dispute): ID {
    dispute.contract
}

public fun status(dispute: &Dispute): u64 {
    dispute.status
}

public fun dispute_id(cap: &PartyCap): ID {
    cap.dispute_id
}

public fun party(cap: &PartyCap): address {
    cap.party
}

// === Package Functions ===

public(package) fun set_status(dispute: &mut Dispute, status: u64) {
    dispute.status = status;
}

public(package) fun create_dispute(
    initiator: address,
    contract: ID,
    court: ID,
    description: String,
    response_period_ms: u64,
    evidence_period_ms: u64,
    voting_period_ms: u64,
    appeal_period_ms: u64,
    max_appeals: u8,
    parties: vector<address>,
    voters: LinkedTable<address, VoterDetails>,
    options: vector<String>,
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
    threshold: u8,
    clock: &Clock,
    ctx: &mut TxContext,
): ID {
    let mut dispute = Dispute {
        id: object::new(ctx),
        status: dispute_status_response(),
        initiator,
        contract,
        court,
        description,
        round: 1,
        timetable: TimeTable {
            round_init_ms: clock.timestamp_ms(),
            response_period_ms,
            evidence_period_ms,
            voting_period_ms,
            appeal_period_ms,
        },
        max_appeals,
        appeals_used: 0,
        parties,
        evidence: vec_map::empty(),
        voters,
        options,
        result: vector[],
        party_result: vector[],
        winner_option: option::none(),
        winner_party: option::none(),
        key_servers,
        public_keys,
        threshold,
    };

    let dispute_id = object::id(&dispute);

    distribute_party_caps(dispute.parties, dispute_id, ctx);
    distribute_voter_caps(&mut dispute.voters, dispute_id, ctx);
    transfer::share_object(dispute);

    dispute_id
}

public(package) fun distribute_voter_caps(
    voters: &mut LinkedTable<address, VoterDetails>,
    dispute_id: ID,
    ctx: &mut TxContext,
) {
    let mut i = linked_table::front(voters);

    while(i.is_some()) {
        let k = *i.borrow();
        let v = voters.borrow_mut(k);

        if (!v.cap_issued) {
            v.cap_issued = true;
            transfer::public_transfer(VoterCap {
                id: object::new(ctx),
                dispute_id,
                voter: k,
            }, k);
        };

        i = voters.next(k);
    };
}

public(package) fun distribute_party_caps(
    parties: vector<address>, 
    dispute_id: ID, 
    ctx: &mut TxContext
) {
    parties.do_ref!(|party| {
        transfer::public_transfer(PartyCap {
            id: object::new(ctx),
            dispute_id,
            party: *party,
        }, *party)
    });
}

public(package) fun create_voter_details(stake: u64): VoterDetails {
    VoterDetails {
        stake,
        vote: std::option::none(),
        decrypted_vote: std::option::none(),
        cap_issued: false,
    }
}