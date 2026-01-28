// © 2026 Nivra Labs Ltd.

/// The Dispute module encapsulates the internal logic of a dispute process.
///
/// Responsibilities include:
/// - Tracking dispute deadlines and time-based transitions
/// - Collecting submitted evidence
/// - Managing voting and determining the final outcome
module nivra::dispute;

// === Imports ===
use std::string::String;
use sui::{
    linked_table::{Self, LinkedTable},
    clock::Clock,
    vec_map::{Self, VecMap},
    bls12381::g1_from_bytes,
    event
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
use nivra::constants::{
    dispute_status_response,
    dispute_status_draw,
    dispute_status_active,
    dispute_status_tallied,
    dispute_status_tie
};

// === Constants ===
const MAX_EVIDENCE_LIMIT: u64 = 3;

// === Errors ===
const EEvidenceFull: u64 = 1;
const ENotPartyMember: u64 = 2;
const ENoEvidenceFound: u64 = 3;
const ENotEvidencePeriod: u64 = 4;
const EInvalidVote: u64 = 5;
const ENotVotingPeriod: u64 = 6;
const ENotVoter: u64 = 7;
const ENotAppealPeriodUntallied: u64 = 8;
const ENotEnoughKeys: u64 = 9;
const EAlreadyFinalized: u64 = 10;
const EInvalidDispute: u64 = 11;
const EInvalidDerivedKeyAmount: u64 = 12;

// === Structs ===
public struct DISPUTE has drop {}

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
    votes: u64,
    vote: Option<EncryptedObject>,
    decrypted_vote: Option<u8>,
    decrypted_party_vote: Option<u8>,
    cap_issued: bool,
    reward_collected: bool,
}

public struct TimeTable has copy, drop, store {
    round_init_ms: u64,
    response_period_ms: u64,
    draw_period_ms: u64,
    evidence_period_ms: u64,
    voting_period_ms: u64,
    appeal_period_ms: u64,
    evidence_swap: u64,
}

public struct EconomicParams has copy, drop, store {
    dispute_fee: u64,
    sanction_model: u64,
    coefficient: u64,
    treasury_share: u64,
    treasury_share_nvr: u64,
    empty_vote_penalty: u64,
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
    max_appeals: u8,                            // Max 3 appeals per case.
    appeals_used: u8,
    parties: vector<address>,                   // 2 parties per case.
    evidence: VecMap<address, vector<ID>>,      // Max 3 evidences per party.
    voters: LinkedTable<address, VoterDetails>,
    options: vector<String>,                    // Max 5 + (empty vote) outcomes.
    result: vector<u64>,                        // Vote count of each option.
    party_result: vector<u64>,                  // Vote count of each party.
    winner_option: Option<u8>,
    winner_party: Option<u8>,
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
    threshold: u8,
    serialized_config: vector<u8>,
    economic_params: EconomicParams,
}

// === Events ===

public struct DisputeTalliedTieEvent has copy, drop {
    dispute_id: ID,
}

public struct DisputeTalliedEvent has copy, drop {
    dispute_id: ID,
    winner_option: u8,
    winner_party: u8,
}

// === Public Functions ===
fun init(otw: DISPUTE, ctx: &mut TxContext) {
    let publisher = sui::package::claim(otw, ctx);
    let mut party_cap_display = 
    sui::display::new<PartyCap>(&publisher, ctx);
    let mut voter_cap_display =
    sui::display::new<VoterCap>(&publisher, ctx);

    party_cap_display.add(
        b"name".to_string(),
        b"Nivra Party Capability".to_string()
    );

    voter_cap_display.add(
        b"name".to_string(),
        b"Nivra Voter Capability".to_string()
    );

    party_cap_display.add(
        b"description".to_string(),
        b"You are a party in the nivra case: {dispute_id}.".to_string()
    );

    voter_cap_display.add(
        b"description".to_string(),
        b"You are a juror in the nivra case: {dispute_id}.".to_string()
    );

    // TODO: Add accurate links to the case
    party_cap_display.add(
        b"link".to_string(),
        b"https://nivracourt.io/".to_string()
    );

    voter_cap_display.add(
        b"link".to_string(),
        b"https://nivracourt.io/".to_string()
    );

    party_cap_display.add(
        b"image_url".to_string(),
        b"https://static.nivracourt.io/nivra-party.svg".to_string()
    );

    voter_cap_display.add(
        b"image_url".to_string(),
        b"https://static.nivracourt.io/nivra-nivster.svg".to_string()
    );

    party_cap_display.update_version();
    voter_cap_display.update_version();

    transfer::public_transfer(publisher, ctx.sender());
    transfer::public_transfer(party_cap_display, ctx.sender());
    transfer::public_transfer(voter_cap_display, ctx.sender());
}

public fun finalize_vote(
    dispute: &mut Dispute,
    package_id: address,
    derived_keys: &vector<vector<u8>>,
    key_servers: &vector<address>,
    clock: &Clock,
) {
    assert!(dispute.is_appeal_period_untallied(clock), ENotAppealPeriodUntallied);
    assert!(key_servers.length() == derived_keys.length(), EInvalidDerivedKeyAmount);
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
    let mut party_result = vector::tabulate!(dispute.parties.length(), |_| 0);
    let mut i = linked_table::front(&dispute.voters);

    while(i.is_some()) {
        let k = *i.borrow();
        let v = dispute.voters.borrow_mut(k);

        // Decrypt vote
        v.vote.do_ref!(|vote| {
            decrypt(vote, &verified_derived_keys, &all_public_keys)
            .do_ref!(|decrypted| {
                if (decrypted.length() == 2) {
                    if (decrypted[0] as u64 < dispute.options.length()) {
                        let option = decrypted[0];
                        v.decrypted_vote = option::some(option);
                        *&mut result[option as u64] = result[option as u64] + 
                        v.votes;
                    };

                    if (decrypted[1] as u64 < dispute.parties.length()) {
                        let option = decrypted[1];
                        v.decrypted_party_vote = option::some(option);
                        *&mut party_result[option as u64] = 
                        party_result[option as u64] + v.votes;
                    };
                };
            });
        });

        i = dispute.voters.next(k);
    };

    dispute.result = result;
    dispute.party_result = party_result;
    tally_votes(dispute);
}

public fun cast_vote(
    dispute: &mut Dispute,
    encrypted_vote: vector<u8>,
    cap: &VoterCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(dispute.is_voting_period(clock), ENotVotingPeriod);
    assert!(cap.dispute_id == object::id(dispute), ENotVoter);
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
    assert!(dispute.is_appeal_period_untallied(clock), ENotAppealPeriodUntallied);
    assert!(id == object::id(dispute).to_bytes(), EInvalidDispute);
}

public fun is_response_period(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let response_period_end = dispute.timetable.round_init_ms + 
        dispute.timetable.response_period_ms;

    (current_time <= response_period_end) && 
        (dispute.status == dispute_status_response())
}

public fun is_draw_period(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let draw_period_end = dispute.timetable.round_init_ms + 
        dispute.timetable.draw_period_ms;

    (current_time <= draw_period_end) && 
        (dispute.status == dispute_status_draw())
}

public fun is_evidence_period(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let evidence_period_end = dispute.timetable.round_init_ms + 
    dispute.timetable.evidence_period_ms;

    (current_time <= evidence_period_end) && 
        (dispute.status == dispute_status_active())
}

public fun is_voting_period(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let voting_period_start = dispute.timetable.round_init_ms + 
        dispute.timetable.evidence_period_ms;
    let voting_period_end = voting_period_start + 
        dispute.timetable.voting_period_ms;

    (current_time > voting_period_start) && (current_time <= voting_period_end) 
        && (dispute.status == dispute_status_active())
}

public fun is_appeal_period_untallied(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let appeal_period_start = dispute.timetable.round_init_ms + 
        dispute.timetable.evidence_period_ms + 
        dispute.timetable.voting_period_ms;
    let appeal_period_end = appeal_period_start + 
        dispute.timetable.appeal_period_ms;

    (current_time > appeal_period_start) && (current_time <= appeal_period_end)
        && (dispute.status == dispute_status_active())
}

public fun is_appeal_period_tallied(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let appeal_period_start = dispute.timetable.round_init_ms + 
        dispute.timetable.evidence_period_ms + 
        dispute.timetable.voting_period_ms;
    let appeal_period_end = appeal_period_start + 
        dispute.timetable.appeal_period_ms;

    (current_time > appeal_period_start) && (current_time <= appeal_period_end) 
        && (dispute.status == dispute_status_tallied())
}

public fun is_appeal_period_tie(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let appeal_period_start = dispute.timetable.round_init_ms + 
        dispute.timetable.evidence_period_ms + 
        dispute.timetable.voting_period_ms;
    let appeal_period_end = appeal_period_start + 
        dispute.timetable.appeal_period_ms;

    (current_time > appeal_period_start) && (current_time <= appeal_period_end) 
        && (dispute.status == dispute_status_tie())
}

public fun is_completed(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let timetable_end = dispute.timetable.round_init_ms + 
        dispute.timetable.evidence_period_ms + 
        dispute.timetable.voting_period_ms + 
        dispute.timetable.appeal_period_ms;

    (current_time > timetable_end) && 
        (dispute.status == dispute_status_tallied())
}

public fun is_incomplete(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let draw_period_end = dispute.timetable.round_init_ms +
        dispute.timetable.draw_period_ms;
    let timetable_end = dispute.timetable.round_init_ms + 
        dispute.timetable.evidence_period_ms + 
        dispute.timetable.voting_period_ms + 
        dispute.timetable.appeal_period_ms;

    let untallied_or_unresolved_tie = (current_time > timetable_end) && 
        ((dispute.status == dispute_status_active()) 
            || (dispute.status == dispute_status_tie()));

    let no_nivsters_drawn = (current_time > draw_period_end) && 
        (dispute.status == dispute_status_draw());

    no_nivsters_drawn || untallied_or_unresolved_tie
}

public fun party_failed_payment(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let response_period_end = dispute.timetable.round_init_ms + 
        dispute.timetable.response_period_ms;

    (current_time > response_period_end) && 
        (dispute.status == dispute_status_response())
}

public fun has_appeals_left(dispute: &Dispute): bool {
    dispute.appeals_used < dispute.max_appeals
}

public fun total_stake_sum(dispute: &Dispute): u64 {
    let mut i = dispute.voters.front();
    let mut s = 0;

    while (i.is_some()) {
        let k = *i.borrow();
        let v = dispute.voters.borrow(k);

        s = s + v.stake;
        i = dispute.voters.next(k);
    };

    s
}

// === View Functions ===

public fun serialized_config(dispute: &Dispute): &vector<u8> {
    &dispute.serialized_config
}

public fun winner_option(dispute: &Dispute): Option<u8> {
    dispute.winner_option
}

public fun winner_party(dispute: &Dispute): Option<u8> {
    dispute.winner_party
}

public fun appeals_used(dispute: &Dispute): u8 {
    dispute.appeals_used
}

public fun round(dispute: &Dispute): u64 {
    dispute.round
}

public(package) fun voters_mut(dispute: &mut Dispute): &mut LinkedTable<address, VoterDetails> {
    &mut dispute.voters
}

public(package) fun voters(dispute: &Dispute): &LinkedTable<address, VoterDetails> {
    &dispute.voters
}

public fun dispute_fee(dispute: &Dispute): u64 {
    dispute.economic_params.dispute_fee
}

public fun treasury_share(dispute: &Dispute): u64 {
    dispute.economic_params.treasury_share
}

public fun sanction_model(dispute: &Dispute): u64 {
    dispute.economic_params.sanction_model
}

public fun empty_vote_penalty(dispute: &Dispute): u64 {
    dispute.economic_params.empty_vote_penalty
}

public fun coefficient(dispute: &Dispute): u64 {
    dispute.economic_params.coefficient
}

public fun treasury_share_nvr(dispute: &Dispute): u64 {
    dispute.economic_params.treasury_share_nvr
}

public fun max_appeals(dispute: &Dispute): u8 {
    dispute.max_appeals
}

public fun options(dispute: &Dispute): vector<String> {
    dispute.options
}

public fun inititator(dispute: &Dispute): address {
    dispute.initiator
}

public fun parties(dispute: &Dispute): vector<address> {
    dispute.parties
}

public fun result(dispute: &Dispute): vector<u64> {
    dispute.result
}

public fun response_period_ms(dispute: &Dispute): u64 {
    dispute.timetable.response_period_ms
}

public fun draw_period_ms(dispute: &Dispute): u64 {
    dispute.timetable.draw_period_ms
}

public fun evidence_period_ms(dispute: &Dispute): u64 {
    dispute.timetable.evidence_period_ms
}

public fun voting_period_ms(dispute: &Dispute): u64 {
    dispute.timetable.voting_period_ms
}

public fun key_servers(dispute: &Dispute): vector<address> {
    dispute.key_servers
}

public fun public_keys(dispute: &Dispute): vector<vector<u8>> {
    dispute.public_keys
}

public fun threshold(dispute: &Dispute): u8 {
    dispute.threshold
}

public fun appeal_period_ms(dispute: &Dispute): u64 {
    dispute.timetable.appeal_period_ms
}

public fun description(dispute: &Dispute): String {
    dispute.description
}

public fun court(dispute: &Dispute): ID {
    dispute.court
}

public fun contract(dispute: &Dispute): ID {
    dispute.contract
}

public fun status(dispute: &Dispute): u64 {
    dispute.status
}

public fun dispute_id_voter(cap: &VoterCap): ID {
    cap.dispute_id
}

public fun voter(cap: &VoterCap): address {
    cap.voter
}

public fun dispute_id_party(cap: &PartyCap): ID {
    cap.dispute_id
}

public fun party(cap: &PartyCap): address {
    cap.party
}

public fun votes(voter_details: &VoterDetails): u64 {
    voter_details.votes
}

public fun stake(voter_details: &VoterDetails): u64 {
    voter_details.stake
}

public fun reward_collected(voter_details: &VoterDetails): bool {
    voter_details.reward_collected
}

public fun decrypted_vote(voter_details: &VoterDetails): Option<u8> {
    voter_details.decrypted_vote
}

// === Package Functions ===

public(package) fun increment_votes(voter_details: &mut VoterDetails) {
    voter_details.votes = voter_details.votes + 1;
}

public(package) fun set_reward_collected(voter_details: &mut VoterDetails) {
    voter_details.reward_collected = true;
}

public(package) fun increase_stake(
    voter_details: &mut VoterDetails, 
    amount: u64
) {
    voter_details.stake = voter_details.stake + amount;
}

public(package) fun start_response_period_appeal(self: &mut Dispute, clock: &Clock) {
    self.status = dispute_status_response();
    self.timetable.round_init_ms = clock.timestamp_ms();
    self.appeals_used = self.appeals_used + 1;
}

public(package) fun start_draw_period(self: &mut Dispute, clock: &Clock) {
    self.status = dispute_status_draw();
    self.timetable.round_init_ms = clock.timestamp_ms();
}

public(package) fun start_new_round_tie(self: &mut Dispute, clock: &Clock, ctx: &mut TxContext) {
    self.status = dispute_status_active();
    // Start from the voting period.
    self.timetable.evidence_period_ms = 0;
    self.timetable.round_init_ms = clock.timestamp_ms();
    self.round = self.round + 1;

    // Reset last round's results.
    self.result = vector[];
    self.winner_option = option::none();
    self.party_result = vector[];
    self.winner_party = option::none();

    // Distribute voter caps to the additional nivsters.
    self.distribute_voter_caps(ctx);
}

public(package) fun start_new_round(self: &mut Dispute, clock: &Clock, ctx: &mut TxContext) {
    self.status = dispute_status_active();
    self.timetable.round_init_ms = clock.timestamp_ms();
    self.round = self.round + 1;

    if (self.round > 1) {
        // Evidence period is restored in case a tie round occured in-between.
        self.timetable.evidence_period_ms = self.timetable.evidence_swap;
        // Reset last round's results.
        self.result = vector[];
        self.winner_option = option::none();
        self.party_result = vector[];
        self.winner_party = option::none();
        // Nivsters have to vote again on regular rounds.
        self.reset_votes();
    };

    self.distribute_voter_caps(ctx);
}

public(package) fun tally_votes(dispute: &mut Dispute) {
    // Check winner option.
    let mut highest_option = 0;
    let mut second_highest_option = 0;

    dispute.result.do_ref!(|option_votes| {
        if (*option_votes >= highest_option) {
            second_highest_option = highest_option;
            highest_option = *option_votes;
        };
    });

    // Check winner party.
    let mut highest_party_option = 0;
    let mut second_highest_party_option = 0;

    dispute.party_result.do_ref!(|party_votes| {
        if (*party_votes >= highest_party_option) {
            second_highest_party_option = highest_party_option;
            highest_party_option = *party_votes;
        };
    });

    if (highest_option == second_highest_option || highest_party_option == second_highest_party_option) {
        dispute.status = dispute_status_tie();

        event::emit(DisputeTalliedTieEvent { 
            dispute_id: object::id(dispute),
        });
    } else {
        dispute.winner_option = dispute.result.find_index!(|res| res == highest_option).map!(|res| res as u8);
        dispute.winner_party = dispute.party_result.find_index!(|res| res == highest_party_option).map!(|res| res as u8);
        dispute.status = dispute_status_tallied();

        event::emit(DisputeTalliedEvent {
            dispute_id: object::id(dispute),
            winner_option: dispute.winner_option.extract(),
            winner_party: dispute.winner_party.extract(),
        });
    };
}

public(package) fun remove_evidence(
    dispute: &mut Dispute,
    evidence_id: ID,
    cap: &PartyCap, 
    clock: &Clock
) {
    assert!(dispute.is_evidence_period(clock), ENotEvidencePeriod);
    assert!(object::id(dispute) == cap.dispute_id, ENotPartyMember);
    assert!(dispute.evidence.contains(&cap.party), ENoEvidenceFound);

    let evidence = dispute.evidence.get_mut(&cap.party);
    let i = evidence.find_index!(|evidence| evidence == evidence_id);

    assert!(i.is_some(), ENoEvidenceFound);

    evidence.remove(*i.borrow());
}

public(package) fun add_evidence(
    dispute: &mut Dispute, 
    evidence_id: ID, 
    cap: &PartyCap, 
    clock: &Clock
) {
    assert!(dispute.is_evidence_period(clock), ENotEvidencePeriod);
    assert!(object::id(dispute) == cap.dispute_id, ENotPartyMember);

    if (!dispute.evidence.contains(&cap.party)) {
        dispute.evidence.insert(cap.party, vector[]);
    };

    let evidence = dispute.evidence.get_mut(&cap.party);

    assert!(evidence.length() < MAX_EVIDENCE_LIMIT, EEvidenceFull);
    evidence.push_back(evidence_id);
}

public(package) fun set_status(dispute: &mut Dispute, status: u64) {
    dispute.status = status;
}

public(package) fun create_dispute(
    initiator: address,
    contract: ID,
    court: ID,
    description: String,
    response_period_ms: u64,
    draw_period_ms: u64,
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
    serialized_config: vector<u8>,
    dispute_fee: u64,
    sanction_model: u64,
    coefficient: u64,
    treasury_share: u64,
    treasury_share_nvr: u64,
    empty_vote_penalty: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Dispute {
    Dispute {
        id: object::new(ctx),
        status: dispute_status_response(),
        initiator,
        contract,
        court,
        description,
        round: 0,
        timetable: TimeTable {
            round_init_ms: clock.timestamp_ms(),
            response_period_ms,
            draw_period_ms,
            evidence_period_ms,
            voting_period_ms,
            appeal_period_ms,
            evidence_swap: evidence_period_ms,
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
        serialized_config,
        economic_params: EconomicParams {
            dispute_fee,
            sanction_model,
            coefficient,
            treasury_share,
            treasury_share_nvr,
            empty_vote_penalty,
        },
    }
}

public(package) fun share_dispute(
    self: Dispute,
    ctx: &mut TxContext,
) {
    // Always distribute party caps before sharing.
    self.distribute_party_caps(ctx);
    transfer::share_object(self);
}

public(package) fun distribute_voter_caps(
    self: &mut Dispute,
    ctx: &mut TxContext,
) {
    // Iterate the voters list backwards since new nivsters are always
    // inserted at the back of the list.
    let mut i = linked_table::back(&self.voters);
    let mut first_issued_found = false;

    while(i.is_some() && !first_issued_found) {
        let k = *i.borrow();
        let v = self.voters.borrow_mut(k);

        if (!v.cap_issued) {
            v.cap_issued = true;
            transfer::public_transfer(VoterCap {
                id: object::new(ctx),
                dispute_id: object::id(self),
                voter: k,
            }, k);
        } else {
            first_issued_found = true;
        };

        i = self.voters.prev(k);
    };
}

public(package) fun distribute_party_caps(
    self: &Dispute,
    ctx: &mut TxContext
) {
    let dispute_id = object::id(self);

    self.parties.do_ref!(|party| {
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
        votes: 1,
        vote: std::option::none(),
        decrypted_vote: std::option::none(),
        decrypted_party_vote: std::option::none(),
        cap_issued: false,
        reward_collected: false,
    }
}

// === Private Functions ===
fun reset_votes(self: &mut Dispute) {
    let mut i = linked_table::front(&self.voters);

    while(i.is_some()) {
        let k = *i.borrow();
        let v = self.voters.borrow_mut(k);

        v.vote = option::none();
        v.decrypted_vote = option::none();
        v.decrypted_party_vote = option::none();

        i = self.voters.next(k);
    };
}

// === Test Functions ===
#[test_only]
public(package) fun create_voter_details_test(
    stake: u64,
    votes: u64,
    decrypted_vote: Option<u8>,
    decrypted_party_vote: Option<u8>,
): VoterDetails {
    VoterDetails {
        stake,
        votes,
        vote: std::option::none(),
        decrypted_vote,
        decrypted_party_vote,
        cap_issued: false,
        reward_collected: false,
    }
}