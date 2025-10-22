module nivra::dispute;

use std::ascii::String;
use sui::linked_table::{Self, LinkedTable};
use sui::clock::Clock;
use seal::bf_hmac_encryption::{
    EncryptedObject,
    parse_encrypted_object,
};
use sui::vec_map;
use sui::vec_map::VecMap;
use nivra::evidence::Evidence;
use nivra::evidence::create_evidence;
use nivra::constants::max_evidence_limit;

const EEvidenceFull: u64 = 1;
const ENotPartyMember: u64 = 2;
const ENoEvidenceFound: u64 = 3;
const ENotEvidencePeriod: u64 = 4;
const EInvalidVote: u64 = 5;
const ENotVotingPeriod: u64 = 6;
const ENotVoter: u64 = 7;

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
    multiplier: u64,
    cap_issued: bool,
}

public struct TimeTable has copy, drop, store {
    round_init_ms: u64,
    evidence_period_ms: u64,
    voting_period_ms: u64,
    appeal_period_ms: u64,
}

public struct EvidenceEnvelope has store {
    evidence: vector<Evidence>,
}

public struct Dispute has key {
    id: UID,
    contract: ID,
    court: ID,
    description: String,
    round: u16,
    timetable: TimeTable,
    max_appeals: u8,
    parties: vector<address>,
    evidence: VecMap<address, EvidenceEnvelope>,
    voters: LinkedTable<address, VoterDetails>,
    options: vector<String>,
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
    threshold: u8,
}

public fun cast_vote(
    dispute: &mut Dispute,
    encrypted_vote: vector<u8>,
    cap: &VoterCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let voting_period_start = dispute.timetable.round_init_ms + dispute.timetable.evidence_period_ms;
    let voting_period_end = voting_period_start + dispute.timetable.voting_period_ms;
    let current_time = clock.timestamp_ms();

    assert!(current_time >= voting_period_start && current_time <= voting_period_end, ENotVotingPeriod);
    assert!(dispute.voters.contains(cap.voter), ENotVoter);

    let encrypted_vote = parse_encrypted_object(encrypted_vote);

    assert!(encrypted_vote.aad().borrow() == ctx.sender().to_bytes(), EInvalidVote);
    assert!(encrypted_vote.services() == dispute.key_servers, EInvalidVote);
    assert!(encrypted_vote.threshold() == dispute.threshold, EInvalidVote);
    assert!(encrypted_vote.id() == object::id(dispute).to_bytes(), EInvalidVote);

    let v = dispute.voters.borrow_mut(cap.voter);
    v.vote = option::some(encrypted_vote);
}

public fun add_evidence(
    dispute: &mut Dispute,
    description: String,
    blob_id: Option<String>,
    file_type: Option<String>,
    file_subtype: Option<String>,
    cap: &PartyCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let evidence_period_start = dispute.timetable.round_init_ms;
    let evidence_period_end = dispute.timetable.round_init_ms + dispute.timetable.evidence_period_ms;
    let current_time = clock.timestamp_ms();

    assert!(current_time >= evidence_period_start && current_time <= evidence_period_end, ENotEvidencePeriod);
    assert!(dispute.parties.contains(&cap.party), ENotPartyMember);

    if (!dispute.evidence.contains(&cap.party)) {
        dispute.evidence.insert(cap.party, EvidenceEnvelope { 
            evidence: vector[],
        });
    };

    let evidence_envelope = dispute.evidence.get_mut(&cap.party);

    assert!(evidence_envelope.evidence.length() < max_evidence_limit(), EEvidenceFull);

    evidence_envelope.evidence.push_back(create_evidence(
        description, 
        blob_id, 
        file_type, 
        file_subtype, 
        ctx
    ));
}

public fun modify_evidence(
    dispute: &mut Dispute,
    evidence_id: ID,
    description: String,
    blob_id: Option<String>,
    file_type: Option<String>,
    file_subtype: Option<String>,
    clock: &Clock,
    cap: &PartyCap,
) {
    let evidence_period_start = dispute.timetable.round_init_ms;
    let evidence_period_end = dispute.timetable.round_init_ms + dispute.timetable.evidence_period_ms;
    let current_time = clock.timestamp_ms();

    assert!(current_time >= evidence_period_start && current_time <= evidence_period_end, ENotEvidencePeriod);
    assert!(dispute.parties.contains(&cap.party), ENotPartyMember);
    assert!(dispute.evidence.contains(&cap.party), ENoEvidenceFound);

    let evidence_envelope = dispute.evidence.get_mut(&cap.party);
    let i = evidence_envelope.evidence.find_index!(|evidence| object::id(evidence) == evidence_id);

    assert!(i.is_some(), ENoEvidenceFound);

    evidence_envelope.evidence[*i.borrow()].modify_evidence(
        description, 
        blob_id, 
        file_type, 
        file_subtype
    );
}

public fun remove_evidence(
    dispute: &mut Dispute,
    evidence_id: ID,
    clock: &Clock,
    cap: &PartyCap,
) {
    let evidence_period_start = dispute.timetable.round_init_ms;
    let evidence_period_end = dispute.timetable.round_init_ms + dispute.timetable.evidence_period_ms;
    let current_time = clock.timestamp_ms();

    assert!(current_time >= evidence_period_start && current_time <= evidence_period_end, ENotEvidencePeriod);
    assert!(dispute.parties.contains(&cap.party), ENotPartyMember);
    assert!(dispute.evidence.contains(&cap.party), ENoEvidenceFound);

    let evidence_envelope = dispute.evidence.get_mut(&cap.party);
    let i = evidence_envelope.evidence.find_index!(|evidence| object::id(evidence) == evidence_id);

    assert!(i.is_some(), ENoEvidenceFound);

    evidence_envelope.evidence.swap_remove(*i.borrow()).destruct_evidence();
}

public(package) fun create_voter_details(stake: u64): VoterDetails {
    VoterDetails {
        stake,
        vote: std::option::none(),
        decrypted_vote: std::option::none(),
        multiplier: 1,
        cap_issued: false,
    }
}

public(package) fun increase_multiplier(self: &mut VoterDetails) {
    self.multiplier = self.multiplier + 1;
}

public(package) fun increase_stake(self: &mut VoterDetails, stake: u64) {
    self.stake = self.stake + stake;
}

public(package) fun create_dispute(
    contract: ID,
    court: ID,
    description: String,
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
): Dispute {
    Dispute {
        id: object::new(ctx),
        contract,
        court,
        description,
        round: 1,
        timetable: TimeTable {
            round_init_ms: clock.timestamp_ms(),
            evidence_period_ms,
            voting_period_ms,
            appeal_period_ms,
        },
        max_appeals,
        parties,
        evidence: vec_map::empty(),
        voters,
        options,
        key_servers,
        public_keys,
        threshold,
    }
}

public(package) fun distribute_voter_caps(dispute: &mut Dispute, ctx: &mut TxContext) {
    let mut i = linked_table::front(&dispute.voters);

    while(i.is_some()) {
        let k = *i.borrow();
        let v = dispute.voters.borrow_mut(k);

        if (!v.cap_issued) {
            v.cap_issued = true;
            transfer::public_transfer(VoterCap {
                id: object::new(ctx),
                dispute_id: object::id(dispute),
                voter: k,
            }, k);
        };

        i = dispute.voters.next(k);
    };
}

public(package) fun share_dispute(dispute: Dispute, ctx: &mut TxContext) {
    dispute.parties.do_ref!(|party| {
        transfer::public_transfer(PartyCap {
            id: object::new(ctx),
            dispute_id: object::id(&dispute),
            party: *party,
        }, *party)
    });

    let mut dispute = dispute;
    distribute_voter_caps(&mut dispute, ctx);

    transfer::share_object(dispute);
}