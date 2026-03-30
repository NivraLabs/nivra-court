// © 2026 Nivra Labs Ltd.

module nivra::dispute;

// === Imports ===
use sui::vec_map::{Self, VecMap};
use std::string::String;
use seal::bf_hmac_encryption::EncryptedObject;
use nivra::constants::dispute_status_response;
use sui::clock::Clock;
use sui::event;
use nivra::constants::dispute_status_draw;
use nivra::constants::dispute_opening_fee;
use nivra::constants::dispute_appeal_fee;
use nivra::vec_map_unsafe::{Self, VecMapUnsafe};
use nivra::constants::dispute_status_active;
use nivra::constants::max_evidence_per_party;
use seal::bf_hmac_encryption::parse_encrypted_object;
use seal::bf_hmac_encryption::VerifiedDerivedKey;
use seal::bf_hmac_encryption::verify_derived_keys;
use sui::bls12381::g1_from_bytes;
use seal::bf_hmac_encryption::new_public_key;
use seal::bf_hmac_encryption::PublicKey;
use seal::bf_hmac_encryption::decrypt;
use nivra::constants::dispute_status_tie;
use nivra::constants::dispute_status_tallied;
use nivra::constants::dispute_status_cancelled;
use nivra::constants::dispute_refund;
use nivra::constants::dispute_status_completed_one_sided;
use nivra::constants::dispute_status_completed;

// === Constants ===
// Dispute cancellation reasons.
const NIVSTERS_NOT_DRAWN: u64 = 1;
const VOTES_NOT_COUNTED: u64 = 2;
const UNRESOLVED_TIE: u64 = 3;

// === Errors ===
const EMaxEvidenceReached: u64 = 1;
const EEvidenceNotFound: u64 = 2;
const EEvidenceAlreadyRegistered: u64 = 3;
const ENotVotingPeriod: u64 = 4;
const ENotVoter: u64 = 5;
const EInvalidVote: u64 = 6;
const ENotAppealPeriodUntallied: u64 = 7;
const EInvalidDispute: u64 = 8;
const EInvalidDerivedKeyAmount: u64 = 9;
const ENotEnoughKeys: u64 = 10;
const EAlreadyFinalized: u64 = 11;
const EInvalidOption: u64 = 12;

// === Structs ===
public struct Dispute has key {
    id: UID,
    contract: ID,
    court: ID,
    status: u64,
    round: u64,
    max_appeals: u8,
    appeals_used: u8,
    initiator: address,
    last_payer: address,
    payments: VecMap<address, vector<PaymentDetails>>,
    options: VecMap<String, address>,
    evidence: VecMap<address, vector<ID>>,
    voters: VecMapUnsafe<address, VoterDetails>,
    result: vector<u64>,
    winner_option: Option<u64>,
    total_stake_locked: u64,
    schedule: Schedule,
    economics: Economics,
    operation: Operation,
    config_hash: vector<u8>,
}

public struct VoterDetails has copy, drop, store {
    stake: u64,
    votes: u64,
    vote: Option<EncryptedObject>,
    decrypted_vote: Option<u8>,
}

public struct PaymentDetails has copy, drop, store {
    amount: u64,
    event_type: u64,
    timestamp: u64,
}

public struct Schedule has copy, drop, store {
    round_init_ms: u64,
    response_period_ms: u64,
    draw_period_ms: u64,
    evidence_period_ms: u64,
    voting_period_ms: u64,
    appeal_period_ms: u64,
    evidence_swap: u64,
}

public struct Economics has copy, drop, store {
    init_nivster_count: u64,
    sanction_model: u64,
    coefficient: u64,
    dispute_fee: u64,
    treasury_share: u64,
    treasury_share_nvr: u64,
    empty_vote_penalty: u64,
}

public struct Operation has copy, drop, store {
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
    threshold: u8,
}

// === Events ===
/// Dispute creation event.
/// 
/// The indexer of the `DisputeCreatedEvent` shall implicitly cover the 
/// initial `DisputePaymentEvent` and `ResponsePeriodEvent`.
public struct DisputeCreatedEvent has copy, drop {
    dispute: ID,
    contract: ID,
    court: ID,
    max_appeals: u8,
    initiator: address,
    options: vector<String>,
    parties: vector<address>,
    schedule: Schedule,
    economics: Economics,
    operation: Operation,
}

/// Dispute payment logging event.
public struct DisputePaymentEvent has copy, drop {
    dispute: ID,
    amount: u64,
    party: address,
    event_type: u64,
    timestamp: u64,
}

public struct NivsterSelectionEvent has copy, drop {
    dispute: ID,
    nivster: address,
    reselected: bool,
    locked_amount: u64,
}

public struct ResponsePeriodEvent has copy, drop {
    dispute: ID,
}

public struct DrawPeriodEvent has copy, drop {
    dispute: ID,
}

public struct NewRoundEvent has copy, drop {
    dispute: ID,
    timestamp: u64,
    tie_round: bool,
}

public struct VoteFinalizedEvent has copy, drop {
    dispute: ID,
    result: Option<String>,
    options: vector<String>,
    votes_per_option: vector<u64>,
}

public struct DisputeCancelledEvent has copy, drop {
    dispute: ID,
    reason: u64,
}

public struct DisputeResolvedOneSided has copy, drop {
    dispute: ID,
    winner_option: String,
}

public struct DisputeCompleted has copy, drop {
    dispute: ID,
    winner_option: String,
}

// === Method Aliases ===
use fun nivra::vec_map::most_significant_option_idx as VecMap.mso_idx;
use fun nivra::vec_map::unique_values as VecMap.unique_values;

// === Public Functions ===
public fun finalize_vote(
    dispute: &mut Dispute,
    package_id: address,
    derived_keys: &vector<vector<u8>>,
    key_servers: &vector<address>,
    clock: &Clock,
) {
    assert!(
        dispute.is_appeal_period_untallied(clock), 
        ENotAppealPeriodUntallied
    );

    assert!(
        key_servers.length() == derived_keys.length(), 
        EInvalidDerivedKeyAmount
    );

    assert!(
        derived_keys.length() as u8 >= dispute.operation.threshold, 
        ENotEnoughKeys
    );

    assert!(dispute.result.length() == 0, EAlreadyFinalized);

    let verified_derived_keys: vector<VerifiedDerivedKey> = verify_derived_keys(
        &derived_keys.map_ref!(|k| g1_from_bytes(k)), 
        package_id, 
        object::id(dispute).to_bytes(), 
        &key_servers
            .map_ref!(|ks1| {
                dispute
                    .operation
                    .key_servers
                    .find_index!(|ks2| ks1 == ks2)
                    .destroy_some()
            })
            .map!(|i| new_public_key(
                dispute.operation.key_servers[i].to_id(), 
                dispute.operation.public_keys[i])
            ),
    );

    let all_public_keys: vector<PublicKey> = dispute
        .operation
        .key_servers
        .zip_map!(
            dispute.operation.public_keys, 
            |ks, pk| new_public_key(ks.to_id(), pk)
        );
    
    let mut result = vector::tabulate!(dispute.options.length(), |_| 0);

    dispute.voters.for_each!(|_, v| {
        v.vote.do_ref!(|vote| {
            decrypt(vote, &verified_derived_keys, &all_public_keys)
            .do_ref!(|decrypted| {
                if (
                    decrypted.length() == 1 && 
                    decrypted[0] as u64 < dispute.options.length()
                ) {
                    let opt = decrypted[0];
                    v.decrypted_vote = option::some(opt);

                    *&mut result[opt as u64] = result[opt as u64] + v.votes;
                };
            });
        });
    });

    let mut highest_opt = 0;
    let mut second_highest_opt = 0;

    dispute.result = result;
    dispute.result.do!(|vote_count| {
        if (vote_count > highest_opt) {
            second_highest_opt = highest_opt;
            highest_opt = vote_count;
        } else if (vote_count > second_highest_opt) {
            second_highest_opt = vote_count;
        };
    });
    
    let winner_option_idx = if (second_highest_opt == highest_opt) {
        dispute.status = dispute_status_tie();
        option::none()
    } else {
        dispute.status = dispute_status_tallied();
        dispute
            .result
            .find_index!(|count| count == highest_opt)
    };

    dispute.winner_option = winner_option_idx;

    event::emit(VoteFinalizedEvent {
        dispute: object::id(dispute),
        result: winner_option_idx.map!(|idx| {
            let (k, _) = dispute.options.get_entry_by_idx(idx);
            *k
        }),
        options: dispute.options.keys(),
        votes_per_option: dispute.result,
    });
}

public fun cast_vote(
    dispute: &mut Dispute,
    encrypted_vote: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(dispute.is_voting_period(clock), ENotVotingPeriod);

    let voter_idx = dispute.voters.get_idx_opt(&ctx.sender());

    assert!(voter_idx.is_some(), ENotVoter);

    let encrypted_vote = parse_encrypted_object(encrypted_vote);

    assert!(
        encrypted_vote.aad().borrow() == ctx.sender().to_bytes(), 
        EInvalidVote
    );

    assert!(
        encrypted_vote.services() == dispute.operation.key_servers, 
        EInvalidVote
    );

    assert!(
        encrypted_vote.threshold() == dispute.operation.threshold, 
        EInvalidVote
    );

    assert!(
        encrypted_vote.id() == object::id(dispute).to_bytes(), 
        EInvalidVote
    );

    let v = dispute.voters.get_value_by_idx_mut(*voter_idx.borrow());
    v.vote = option::some(encrypted_vote);
}

entry fun seal_approve(id: vector<u8>, dispute: &Dispute, clock: &Clock) {
    assert!(dispute.is_appeal_period_untallied(clock), ENotAppealPeriodUntallied);
    assert!(id == object::id(dispute).to_bytes(), EInvalidDispute);
}

public fun is_response_period(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let response_period_end = dispute.schedule.round_init_ms + 
        dispute.schedule.response_period_ms;

    (current_time <= response_period_end) && 
        (dispute.status == dispute_status_response())
}

public fun is_draw_period(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let draw_period_end = dispute.schedule.round_init_ms + 
        dispute.schedule.draw_period_ms;

    (current_time <= draw_period_end) && 
        (dispute.status == dispute_status_draw())
}

public fun is_evidence_period(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let evidence_period_end = dispute.schedule.round_init_ms + 
    dispute.schedule.evidence_period_ms;

    (current_time <= evidence_period_end) && 
        (dispute.status == dispute_status_active())
}

public fun is_voting_period(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let voting_period_start = dispute.schedule.round_init_ms + 
        dispute.schedule.evidence_period_ms;
    let voting_period_end = voting_period_start + 
        dispute.schedule.voting_period_ms;

    (current_time > voting_period_start) && (current_time <= voting_period_end) 
        && (dispute.status == dispute_status_active())
}

public fun is_appeal_period_untallied(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let appeal_period_start = dispute.schedule.round_init_ms + 
        dispute.schedule.evidence_period_ms + 
        dispute.schedule.voting_period_ms;
    let appeal_period_end = appeal_period_start + 
        dispute.schedule.appeal_period_ms;

    (current_time > appeal_period_start) && (current_time <= appeal_period_end)
        && (dispute.status == dispute_status_active())
}

public fun is_appeal_period_tallied(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let appeal_period_start = dispute.schedule.round_init_ms + 
        dispute.schedule.evidence_period_ms + 
        dispute.schedule.voting_period_ms;
    let appeal_period_end = appeal_period_start + 
        dispute.schedule.appeal_period_ms;

    (current_time > appeal_period_start) && (current_time <= appeal_period_end) 
        && (dispute.status == dispute_status_tallied())
}

public fun is_appeal_period_tie(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let appeal_period_start = dispute.schedule.round_init_ms + 
        dispute.schedule.evidence_period_ms + 
        dispute.schedule.voting_period_ms;
    let appeal_period_end = appeal_period_start + 
        dispute.schedule.appeal_period_ms;

    (current_time > appeal_period_start) && (current_time <= appeal_period_end) 
        && (dispute.status == dispute_status_tie())
}

public fun is_completed(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let timetable_end = dispute.schedule.round_init_ms + 
        dispute.schedule.evidence_period_ms + 
        dispute.schedule.voting_period_ms + 
        dispute.schedule.appeal_period_ms;

    (current_time > timetable_end) && 
        (dispute.status == dispute_status_tallied())
}

public fun is_incomplete(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let draw_period_end = dispute.schedule.round_init_ms +
        dispute.schedule.draw_period_ms;
    let timetable_end = dispute.schedule.round_init_ms + 
        dispute.schedule.evidence_period_ms + 
        dispute.schedule.voting_period_ms + 
        dispute.schedule.appeal_period_ms;

    let untallied_or_unresolved_tie = (current_time > timetable_end) && 
        ((dispute.status == dispute_status_active()) 
            || (dispute.status == dispute_status_tie()));

    let no_nivsters_drawn = (current_time > draw_period_end) && 
        (dispute.status == dispute_status_draw());

    no_nivsters_drawn || untallied_or_unresolved_tie
}

public fun party_failed_payment(dispute: &Dispute, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    let response_period_end = dispute.schedule.round_init_ms + 
        dispute.schedule.response_period_ms;

    (current_time > response_period_end) && 
        (dispute.status == dispute_status_response())
}

public fun is_party(dispute: &Dispute, addr: address): bool {
    dispute.payments.contains(&addr)
}

public fun is_voter(dispute: &Dispute, addr: address): bool {
    dispute.voters.contains(&addr)
}

public fun has_appeals_left(dispute: &Dispute): bool {
    dispute.appeals_used < dispute.max_appeals
}

public fun decrypted_vote_party(
    voter_details: &VoterDetails,
    dispute: &Dispute,
): Option<address> {
    voter_details.decrypted_vote.map!(|idx| {
        let (_, v) = dispute.options.get_entry_by_idx(idx as u64);
        *v
    })
}

public fun votes_for_party(
    dispute: &Dispute,
    party: address,
): u64 {
    let mut i = 0;
    let mut count = 0;

    while (i < dispute.result.length()) {
        let (_, v) = dispute.options.get_entry_by_idx(i);

        if (*v == party) {
            count = count + dispute.result[i];
        };

        i = i + 1;
    };

    count
}

public fun votes_for_option(
    dispute: &Dispute,
    option_idx: u64,
): u64 {
    assert!(option_idx < dispute.result.length(), EInvalidOption);
    dispute.result[option_idx]
}

public fun total_votes_casted(dispute: &Dispute): u64 {
    dispute.result.fold!(0, |votes, i| votes + i)
}

public fun winner_party(dispute: &Dispute): Option<address> {
    dispute.winner_option.map!(|idx| {
        let (_, party) = dispute.options.get_entry_by_idx(idx);
        *party
    })
}

public fun winner_option(dispute: &Dispute): Option<String> {
    dispute.winner_option.map!(|idx| {
        let (option, _) = dispute.options.get_entry_by_idx(idx);
        *option
    })
}

// === View Functions ===
public fun status(dispute: &Dispute): u64 {
    dispute.status
}

public fun last_payer(dispute: &Dispute): address {
    dispute.last_payer
}

public fun appeals_used(dispute: &Dispute): u8 {
    dispute.appeals_used
}

public fun dispute_fee(dispute: &Dispute): u64 {
    dispute.economics.dispute_fee
}

public fun empty_vote_penalty(dispute: &Dispute): u64 {
    dispute.economics.empty_vote_penalty
}

public fun sanction_model(dispute: &Dispute): u64 {
    dispute.economics.sanction_model
}

public fun coefficient(dispute: &Dispute): u64 {
    dispute.economics.coefficient
}

public fun treasury_share(dispute: &Dispute): u64 {
    dispute.economics.treasury_share
}

public fun treasury_share_nvr(dispute: &Dispute): u64 {
    dispute.economics.treasury_share_nvr
}

public fun court(dispute: &Dispute): ID {
    dispute.court
}

public fun init_nivster_count(dispute: &Dispute): u64 {
    dispute.economics.init_nivster_count
}

public fun config_hash(dispute: &Dispute): vector<u8> {
    dispute.config_hash
}

public fun payments(
    dispute: &Dispute
): VecMap<address, vector<PaymentDetails>> {
    dispute.payments
}

public fun amount(payment_details: PaymentDetails): u64 {
    payment_details.amount
}

public fun is_refund(payment_details: PaymentDetails): bool {
    payment_details.event_type == dispute_refund()
}

public fun stake(voter_details: &VoterDetails): u64 {
    voter_details.stake
}

public fun decrypted_vote(voter_details: &VoterDetails): Option<u8> {
    voter_details.decrypted_vote
}

public fun voters(dispute: &Dispute): &VecMapUnsafe<address, VoterDetails> {
    &dispute.voters
}

public fun parties(dispute: &Dispute): vector<address> {
    dispute.payments.keys()
}

public fun winner_option_idx(dispute: &Dispute): Option<u64> {
    dispute.winner_option
}

// === Package Functions ===
public(package) fun create_dispute(
    contract: ID,
    court: ID,
    max_appeals: u8,
    options: VecMap<String, address>,
    schedule: Schedule,
    economics: Economics,
    operation: Operation,
    config_hash: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
): Dispute {
    let parties = options.unique_values!();

    let mut dispute = Dispute {
        id: object::new(ctx),
        contract,
        court,
        status: dispute_status_response(),
        round: 0,
        max_appeals,
        appeals_used: 0,
        initiator: ctx.sender(),
        last_payer: ctx.sender(),
        payments: vec_map::from_keys_values(
            parties, 
            parties.map!(|_| vector[]),
        ),
        options,
        evidence: vec_map::from_keys_values(
            parties, 
            parties.map!(|_| vector[]),
        ),
        voters: vec_map_unsafe::empty(),
        result: vector[],
        winner_option: option::none(),
        total_stake_locked: 0,
        schedule,
        economics,
        operation,
        config_hash,
    };

    // Silently register the intial payment.
    let amount = dispute.economics.dispute_fee;
    let payments = dispute.payments.get_mut(&ctx.sender());

    payments.push_back(PaymentDetails {
        amount,
        event_type: dispute_opening_fee(),
        timestamp: clock.timestamp_ms(),
    });

    dispute
}

public(package) fun share_dispute(
    dispute: Dispute,
) {
    let (options, parties) = dispute.options.into_keys_values();

    event::emit(DisputeCreatedEvent {
        dispute: object::id(&dispute),
        contract: dispute.contract,
        court: dispute.court,
        max_appeals: dispute.max_appeals,
        initiator: dispute.initiator,
        options,
        parties,
        schedule: dispute.schedule,
        economics: dispute.economics,
        operation: dispute.operation,
    });

    transfer::share_object(dispute);
}

public(package) fun create_dispute_schedule(
    round_init_ms: u64,
    response_period_ms: u64,
    draw_period_ms: u64,
    evidence_period_ms: u64,
    voting_period_ms: u64,
    appeal_period_ms: u64,
): Schedule {
    Schedule {
        round_init_ms,
        response_period_ms,
        draw_period_ms,
        evidence_period_ms,
        voting_period_ms,
        appeal_period_ms,
        evidence_swap: evidence_period_ms,
    }
}

public(package) fun create_dispute_economics(
    init_nivster_count: u64,
    sanction_model: u64,
    coefficient: u64,
    dispute_fee: u64,
    treasury_share: u64,
    treasury_share_nvr: u64,
    empty_vote_penalty: u64,
): Economics {
    Economics {
        init_nivster_count,
        sanction_model,
        coefficient,
        dispute_fee,
        treasury_share,
        treasury_share_nvr,
        empty_vote_penalty,
    }
}

public(package) fun create_dispute_operation(
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
    threshold: u8,
): Operation {
    Operation {
        key_servers,
        public_keys,
        threshold,
    }
}

public(package) fun register_payment(
    dispute: &mut Dispute,
    amount: u64,
    party: address,
    clock: &Clock,
) {
    let payments = dispute.payments.get_mut(&party);
    let timestamp = clock.timestamp_ms();

    let event_type = if (dispute.appeals_used == 0) {
        dispute_opening_fee()
    } else {
        dispute_appeal_fee()
    };

    payments.push_back(PaymentDetails {
        amount,
        event_type,
        timestamp,
    });

    dispute.last_payer = party;

    event::emit(DisputePaymentEvent {
        dispute: object::id(dispute),
        amount,
        party,
        event_type,
        timestamp,
    });
}

public(package) fun register_refund(
    dispute: &mut Dispute,
    amount: u64,
    party: address,
    clock: &Clock,
) {
    let payments = dispute.payments.get_mut(&party);
    let timestamp = clock.timestamp_ms();

    payments.push_back(PaymentDetails {
        amount,
        event_type: dispute_refund(),
        timestamp,
    });

    event::emit(DisputePaymentEvent {
        dispute: object::id(dispute),
        amount,
        party,
        event_type: dispute_refund(),
        timestamp,
    });
}

public(package) fun start_response_period(
    dispute: &mut Dispute, 
    clock: &Clock
) {
    dispute.status = dispute_status_response();
    dispute.schedule.round_init_ms = clock.timestamp_ms();

    event::emit(ResponsePeriodEvent {
        dispute: object::id(dispute),
    });
}

public(package) fun start_draw_period(dispute: &mut Dispute, clock: &Clock) {
    dispute.status = dispute_status_draw();
    dispute.schedule.round_init_ms = clock.timestamp_ms();

    event::emit(DrawPeriodEvent { 
        dispute: object::id(dispute),
    });
}

public(package) fun add_voter(
    dispute: &mut Dispute,
    nivster: address,
    stake: u64,
) {
    let idx = dispute.voters.get_idx_opt(&nivster);

    if (idx.is_some()) {
        let voter_details = dispute
        .voters
        .get_value_by_idx_mut(*idx.borrow());

        voter_details.stake = voter_details.stake + stake;
        voter_details.votes = voter_details.votes + 1;
    } else {
        dispute.voters.insert_unsafe(
            nivster, 
            VoterDetails {
                stake,
                votes: 1,
                vote: option::none(),
                decrypted_vote: option::none(),
            }
        );
    };

    dispute.total_stake_locked = dispute.total_stake_locked + stake;

    event::emit(NivsterSelectionEvent {
        dispute: object::id(dispute),
        nivster,
        reselected: idx.is_some(),
        locked_amount: stake,
    });
}

public(package) fun start_new_round(
    dispute: &mut Dispute, 
    clock: &Clock,
) {
    dispute.status = dispute_status_active();
    dispute.schedule.round_init_ms = clock.timestamp_ms();
    dispute.round = dispute.round + 1;

    if (dispute.round > 1) {
        // Evidence period is restored in case a tie round occured in-between.
        dispute.schedule.evidence_period_ms = dispute.schedule.evidence_swap;
        // Reset last round's results.
        dispute.result = vector[];
        dispute.winner_option = option::none();
    };

    event::emit(NewRoundEvent {
        dispute: object::id(dispute),
        timestamp: dispute.schedule.round_init_ms,
        tie_round: false,
    });
}

public(package) fun start_new_round_tie(
    dispute: &mut Dispute, 
    clock: &Clock,
) {
    dispute.status = dispute_status_active();
    // Start from the voting period.
    dispute.schedule.evidence_period_ms = 0;
    dispute.schedule.round_init_ms = clock.timestamp_ms();
    dispute.round = dispute.round + 1;

    // Reset last round's results.
    dispute.result = vector[];
    dispute.winner_option = option::none();

    event::emit(NewRoundEvent {
        dispute: object::id(dispute),
        timestamp: dispute.schedule.round_init_ms,
        tie_round: true,
    });
}

public(package) fun add_evidence(
    dispute: &mut Dispute,
    party: address,
    evidence: ID,
) {
    let party_evidence = dispute.evidence.get_mut(&party);

    assert!(!party_evidence.contains(&evidence), EEvidenceAlreadyRegistered);
    assert!(
        party_evidence.length() < max_evidence_per_party(), 
        EMaxEvidenceReached
    );

    party_evidence.push_back(evidence);
}

public(package) fun remove_evidence(
    dispute: &mut Dispute,
    party: address,
    evidence: ID,
) {
    let party_evidence = dispute.evidence.get_mut(&party);

    let idx = party_evidence
    .find_index!(|existing_evidence| existing_evidence == evidence);

    assert!(idx.is_some(), EEvidenceNotFound);

    party_evidence.remove(*idx.borrow());
}

public(package) fun use_appeal(dispute: &mut Dispute) {
    dispute.appeals_used = dispute.appeals_used + 1;
}

public(package) fun voters_mut(
    dispute: &mut Dispute,
): &mut VecMapUnsafe<address, VoterDetails> {
    &mut dispute.voters
}

public(package) fun cancel_dispute(
    dispute: &mut Dispute,
    clock: &Clock,
) {
    let current_time = clock.timestamp_ms();

    let draw_period_end = dispute.schedule.round_init_ms +
        dispute.schedule.draw_period_ms;

    let timetable_end = dispute.schedule.round_init_ms + 
        dispute.schedule.evidence_period_ms + 
        dispute.schedule.voting_period_ms + 
        dispute.schedule.appeal_period_ms;

    let untallied = (current_time > timetable_end) && 
        (dispute.status == dispute_status_active());

    let unresolved_tie = (current_time > timetable_end) && 
        (dispute.status == dispute_status_tie());

    let no_nivsters_drawn = (current_time > draw_period_end) && 
        (dispute.status == dispute_status_draw());

    let mut reason = 0;

    if (untallied) {
        reason = VOTES_NOT_COUNTED;
    } else if (unresolved_tie) {
        reason = UNRESOLVED_TIE;
    } else if (no_nivsters_drawn) {
        reason = NIVSTERS_NOT_DRAWN;
    };

    dispute.status = dispute_status_cancelled();

    event::emit(DisputeCancelledEvent { 
        dispute: object::id(dispute), 
        reason,
    });
}

public(package) fun resolve_dispute_one_sided(
    dispute: &mut Dispute,
    ctx: &mut TxContext,
) {
    dispute.status = dispute_status_completed_one_sided();

    let winner_party = dispute.last_payer;
    let mso = dispute.options.mso_idx!(winner_party);
    let (winner_option, _) = dispute.options.get_entry_by_idx(mso);

    dispute.parties().do!(|party| {
        transfer::public_transfer(
            nivra::nivra_result::create(
                object::id(dispute), 
                dispute.contract, 
                dispute.court.to_address(), 
                dispute.options, 
                dispute.max_appeals, 
                *winner_option, 
                ctx,
            ),
            party
        );
    });

    event::emit(DisputeResolvedOneSided {
        dispute: object::id(dispute),
        winner_option: *winner_option,
    });
}

public(package) fun complete_dispute(
    dispute: &mut Dispute,
    ctx: &mut TxContext,
) {
    dispute.status = dispute_status_completed();
    let winner_option = dispute.winner_option();

    dispute.parties().do!(|party| {
        transfer::public_transfer(
            nivra::nivra_result::create(
                object::id(dispute), 
                dispute.contract, 
                dispute.court.to_address(), 
                dispute.options, 
                dispute.max_appeals, 
                *winner_option.borrow(), 
                ctx,
            ),
            party
        );
    });

    event::emit(DisputeCompleted {
        dispute: object::id(dispute),
        winner_option: *winner_option.borrow(),
    });
}

// === Test Functions ===
#[test_only]
public fun add_fake_vote_for_testing(
    dispute: &mut Dispute, 
    nivster: address, 
    vote_option: u8
) {
    let idx = *dispute.voters.get_idx_opt(&nivster).borrow();
    let voter_details = dispute.voters.get_value_by_idx_mut(idx);
    voter_details.decrypted_vote = option::some(vote_option);
}

#[test_only]
public fun tally_fake_votes_for_testing(dispute: &mut Dispute) {
    let mut result = vector::tabulate!(dispute.options.length(), |_| 0);

    dispute.voters.for_each!(|_, v| {
        v.decrypted_vote.do_ref!(|decrypted| {
            let opt = *decrypted;
            if (opt as u64 < dispute.options.length()) {
                *&mut result[opt as u64] = result[opt as u64] + v.votes;
            };
        });
    });

    let mut highest_opt = 0;
    let mut second_highest_opt = 0;

    dispute.result = result;
    dispute.result.do!(|vote_count| {
        if (vote_count > highest_opt) {
            second_highest_opt = highest_opt;
            highest_opt = vote_count;
        } else if (vote_count > second_highest_opt) {
            second_highest_opt = vote_count;
        };
    });
    
    let winner_option_idx = if (highest_opt > 0 && second_highest_opt == highest_opt) {
        dispute.status = dispute_status_tie();
        option::none()
    } else {
        dispute.status = dispute_status_tallied();
        dispute
            .result
            .find_index!(|count| count == highest_opt)
    };

    dispute.winner_option = winner_option_idx;
}