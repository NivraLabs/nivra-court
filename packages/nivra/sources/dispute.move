module nivra::dispute;

use std::ascii::String;
use sui::linked_table::{Self, LinkedTable};
use sui::clock::Clock;
use seal::bf_hmac_encryption::{
    EncryptedObject,
    parse_encrypted_object,
    VerifiedDerivedKey,
    verify_derived_keys,
    new_public_key,
    PublicKey,
    decrypt
};
use sui::vec_map;
use sui::vec_map::VecMap;
use nivra::constants::max_evidence_limit;
use sui::bls12381::g1_from_bytes;
use nivra::constants::dispute_status_active;
use nivra::constants::dispute_status_tie;
use nivra::constants::dispute_status_tallied;

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

public struct Dispute has key {
    id: UID,
    status: u64,
    initiator: address,
    contract: ID,
    court: ID,
    description: String,
    round: u16,
    timetable: TimeTable,
    max_appeals: u8,
    appeals_used: u8,
    parties: vector<address>,
    evidence: VecMap<address, vector<ID>>,
    voters: LinkedTable<address, VoterDetails>,
    options: vector<String>,
    result: vector<u64>,
    winner_option: Option<u8>,
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
    threshold: u8,
}

public fun finalize_vote(
    dispute: &mut Dispute,
    package_id: address,
    derived_keys: &vector<vector<u8>>,
    key_servers: &vector<address>,
    clock: &Clock,
) {
    let voting_period_end = dispute.timetable.round_init_ms + dispute.timetable.evidence_period_ms
        + dispute.timetable.voting_period_ms;
    let current_time = clock.timestamp_ms();

    assert!(current_time > voting_period_end, EVotingPeriodNotEnded);
    assert!(key_servers.length() == derived_keys.length());
    assert!(derived_keys.length() as u8 >= dispute.threshold, ENotEnoughKeys);
    assert!(dispute.result.length() == 0, EAlreadyFinalized);

    let verified_derived_keys: vector<VerifiedDerivedKey> = verify_derived_keys(
        &derived_keys.map_ref!(|k| g1_from_bytes(k)), 
        package_id, 
        object::id(dispute).to_bytes(), 
        &key_servers
            .map_ref!(|ks1| dispute.key_servers.find_index!(|ks2| ks1 == ks2).destroy_some())
            .map!(|i| new_public_key(dispute.key_servers[i].to_id(), dispute.public_keys[i])),
    );

    let all_public_keys: vector<PublicKey> = dispute
        .key_servers
        .zip_map!(dispute.public_keys, |ks, pk| new_public_key(ks.to_id(), pk));
    
    let mut result = vector::tabulate!(dispute.options.length(), |_| 0);
    let mut i = linked_table::front(&dispute.voters);

    while(i.is_some()) {
        let k = *i.borrow();
        let v = dispute.voters.borrow_mut(k);

        v.vote.do_ref!(|vote| {
            decrypt(vote, &verified_derived_keys, &all_public_keys)
            .do_ref!(|decrypted| {
                if (decrypted.length() == 1 && decrypted[0] as u64 < dispute.options.length()) {
                    let option = decrypted[0];
                    v.decrypted_vote = option::some(option);
                    *&mut result[option as u64] = result[option as u64] + (1 * v.multiplier);
                }
            });
        });

        i = dispute.voters.next(k);
    };

    dispute.result = result;
    tally_votes(dispute);
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

entry fun seal_approve(id: vector<u8>, dispute: &Dispute, clock: &Clock) {
    let voting_period_end = dispute.timetable.round_init_ms + dispute.timetable.evidence_period_ms
        + dispute.timetable.voting_period_ms;
    let current_time = clock.timestamp_ms();

    assert!(current_time > voting_period_end, EVotingPeriodNotEnded);
    assert!(id == object::id(dispute).to_bytes(), EInvalidDispute);
}

public(package) fun add_evidence(
    dispute: &mut Dispute, 
    evidence_id: ID, 
    cap: &PartyCap, 
    clock: &Clock
) {
    let evidence_period_start = dispute.timetable.round_init_ms;
    let evidence_period_end = dispute.timetable.round_init_ms + dispute.timetable.evidence_period_ms;
    let current_time = clock.timestamp_ms();

    assert!(current_time >= evidence_period_start && current_time <= evidence_period_end, ENotEvidencePeriod);
    assert!(dispute.parties.contains(&cap.party), ENotPartyMember);
    assert!(object::id(dispute) == cap.dispute_id, ENotPartyMember);

    if (!dispute.evidence.contains(&cap.party)) {
        dispute.evidence.insert(cap.party, vector[]);
    };

    let evidence = dispute.evidence.get_mut(&cap.party);

    assert!(evidence.length() < max_evidence_limit(), EEvidenceFull);
    evidence.push_back(evidence_id);
}

public(package) fun remove_evidence(
    dispute: &mut Dispute,
    evidence_id: ID,
    cap: &PartyCap, 
    clock: &Clock
) {
    let evidence_period_start = dispute.timetable.round_init_ms;
    let evidence_period_end = dispute.timetable.round_init_ms + dispute.timetable.evidence_period_ms;
    let current_time = clock.timestamp_ms();

    assert!(current_time >= evidence_period_start && current_time <= evidence_period_end, ENotEvidencePeriod);
    assert!(dispute.parties.contains(&cap.party), ENotPartyMember);
    assert!(object::id(dispute) == cap.dispute_id, ENotPartyMember);
    assert!(dispute.evidence.contains(&cap.party), ENoEvidenceFound);

    let evidence = dispute.evidence.get_mut(&cap.party);
    let i = evidence.find_index!(|evidence| evidence == evidence_id);

    assert!(i.is_some(), ENoEvidenceFound);

    evidence.swap_remove(*i.borrow());
}

public(package) fun get_options(dispute: &Dispute): vector<String> {
    dispute.options
}

public(package) fun get_parties(dispute: &Dispute): vector<address> {
    dispute.parties
}

public(package) fun get_voters_mut(dispute: &mut Dispute): &mut LinkedTable<address, VoterDetails> {
    &mut dispute.voters
}

public(package) fun get_voters(dispute: &Dispute): &LinkedTable<address, VoterDetails> {
    &dispute.voters
}

public(package) fun get_initiator(dispute: &Dispute): address {
    dispute.initiator
}

public(package) fun get_contract_id(dispute: &Dispute): ID {
    dispute.contract
}

public(package) fun set_status(dispute: &mut Dispute, status: u64) {
    dispute.status = status;
}

public(package) fun get_nivster_count(dispute: &Dispute): u64 {
    dispute.voters.length()
}

public(package) fun get_winner_option(dispute: &Dispute): Option<u8> {
    dispute.winner_option
}

public(package) fun get_results(dispute: &Dispute): vector<u64> {
    dispute.result
}

public(package) fun increase_appeals(dispute: &mut Dispute) {
    dispute.appeals_used = dispute.appeals_used + 1;
}

public(package) fun has_appeals_left(dispute: &Dispute): bool {
    dispute.appeals_used < dispute.max_appeals
}

public(package) fun is_party_member(dispute: &Dispute, cap: &PartyCap): bool {
    dispute.parties.find_index!(|party| *party == cap.party).is_some()
}

public(package) fun is_completed(dispute: &Dispute, clock: &Clock): bool {
    let appeal_period_end = dispute.timetable.round_init_ms + dispute.timetable.evidence_period_ms
        + dispute.timetable.voting_period_ms + dispute.timetable.evidence_period_ms;
    let current_time = clock.timestamp_ms();

    current_time > appeal_period_end
}

public(package) fun is_appeal_period(dispute: &Dispute, clock: &Clock): bool {
    let appeal_period_start = dispute.timetable.round_init_ms + dispute.timetable.evidence_period_ms
        + dispute.timetable.voting_period_ms;
    let appeal_period_end = appeal_period_start + dispute.timetable.evidence_period_ms;
    let current_time = clock.timestamp_ms();

    current_time >= appeal_period_start && current_time < appeal_period_end
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

public(package) fun get_status(self: &Dispute): u64 {
    self.status
}

public(package) fun get_multiplier(self: &VoterDetails): u64 {
    self.multiplier
}

public(package) fun get_decrypted_vote(self: &VoterDetails): Option<u8> {
    self.decrypted_vote
}

public(package) fun getStake(self: &VoterDetails): u64 {
    self.stake
}

public(package) fun increase_multiplier(self: &mut VoterDetails) {
    self.multiplier = self.multiplier + 1;
}

public(package) fun increase_stake(self: &mut VoterDetails, stake: u64) {
    self.stake = self.stake + stake;
}

public(package) fun create_dispute(
    initiator: address,
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
        status: dispute_status_active(),
        initiator,
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
        appeals_used: 0,
        parties,
        evidence: vec_map::empty(),
        voters,
        options,
        result: vector[],
        winner_option: option::none(),
        key_servers,
        public_keys,
        threshold,
    }
}

public(package) fun start_new_round(dispute: &mut Dispute, clock: &Clock, ctx: &mut TxContext) {
    distribute_voter_caps(dispute, ctx);

    dispute.status = dispute_status_active();
    dispute.round = dispute.round + 1;
    dispute.timetable.round_init_ms = clock.timestamp_ms();
    dispute.result = vector[];
    dispute.winner_option = option::none();

    let mut i = linked_table::front(&dispute.voters);

    while(i.is_some()) {
        let k = *i.borrow();
        let v = dispute.voters.borrow_mut(k);

        v.vote = option::none();
        v.decrypted_vote = option::none();

        i = dispute.voters.next(k);
    };
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

public(package) fun tally_votes(dispute: &mut Dispute) {
    let mut highest = 0;
    let mut second_highest = 0;

    dispute.result.do_ref!(|option_votes| {
        if (*option_votes >= highest) {
            second_highest = highest;
            highest = *option_votes;
        };
    });

    if (second_highest == highest) {
        dispute.status = dispute_status_tie();
    } else {
        dispute.winner_option = dispute.result.find_index!(|res| res == highest).map!(|res| res as u8);
        dispute.status = dispute_status_tallied();
    };
}