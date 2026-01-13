// © 2025 Nivra Labs Ltd.

/// The Court module manages the lifecycle of disputes, including opening,
/// updating, and resolution.
/// 
/// Users stake NVR tokens into a court to become eligible for juror selection.
/// To accept dispute assignments, a staker must apply to the worker pool with
/// their staked amount. Higher stake amounts increase the probability of being
/// selected as a juror.
/// 
/// Any party may initiate a dispute by paying the required dispute fee against
/// another party. Upon a dispute or appeal, the opposing party must match the
/// fee; otherwise, the initiating party automatically prevails and is refunded.
/// After a verdict is reached, the winning party is refunded according to the
/// dispute outcome.
module nivra::court;

// === Imports ===
use std::string::String;
use sui::{
    versioned::{Self, Versioned},
    balance::{Self, Balance},
    coin::Coin,
    linked_table::{Self, LinkedTable},
    table::{Self, Table},
    random::{Random, new_generator},
    clock::Clock,
    sui::SUI,
    linked_table::borrow_mut,
    event,
    vec_map::{Self, VecMap},
    vec_set::{Self, VecSet},
};
use token::nvr::NVR;
use nivra::court_registry::CourtRegistry;
use nivra::court_registry::NivraAdminCap;
use nivra::constants::current_version;
use nivra::court_registry::create_metadata;
use nivra::dispute::VoterDetails;
use nivra::dispute::create_voter_details;
use nivra::dispute::create_dispute;
use nivra::dispute::Dispute;
use nivra::dispute::PartyCap;
use nivra::constants::dispute_status_active;
use nivra::result::create_result;
use std::u64::pow;
use std::u64::divide_and_round_up;
use nivra::worker_pool::{Self, WorkerPool};
use nivra::dispute::VoterCap;
use nivra::constants::dispute_status_cancelled;
use nivra::constants::dispute_status_completed_one_sided;
use nivra::constants::dispute_status_completed;

// === Constants ===
// Sanction models
const FIXED_PERCENTAGE_MODEL: u64 = 0;
const MINORITY_SCALED_MODEL: u64 = 1;
const QUADRATIC_MODEL: u64 = 2;
// Default dispute rules
const INIT_NIVSTER_COUNT: u64 = 1;
const TIE_NIVSTER_COUNT: u64 = 1;
const MIN_OPTIONS: u64 = 2;
const MAX_OPTIONS: u64 = 10;
const PARTY_COUNT: u64 = 2;
const MAX_APPEALS: u8 = 3;

// === Errors ===
const EWrongVersion: u64 = 1;
const ENotEnoughNVR: u64 = 3;
const ENotResponsePeriod: u64 = 7;
const EBalanceMismatchInternal: u64 = 18;
const EDisputeNotCompleted: u64 = 26;
const ENotEnoughSUI: u64 = 27;
const ENoWithdrawAmount: u64 = 28;
const EAlreadyInWorkerPool: u64 = 29;
const ENotInWorkerPool: u64 = 30;
const EDisputeNotCancelled: u64 = 31;
const ERewardAlreadyCollected: u64 = 32;
const EDisputeNotCompletedOneSided: u64 = 33;
const EDisputeNotCancellable: u64 = 34;
const EDisputeNotOneSided: u64 = 35;
const EInvalidTreasuryShareInternal: u64 = 36;
const EInvalidSanctionModelInternal: u64 = 37;
const EInvalidCoefficientInternal: u64 = 38;
const EInvalidVoterCap: u64 = 39;

#[error]
const ENotOperational: vector<u8> =
b"Court operations are currently halted.";

#[error]
const ENotEnoughNivsters: vector<u8> = 
b"The court does not have enough Nivsters to process this dispute action.";

#[error]
const EDisputeAlreadyExists: vector<u8> =
b"A dispute has already been opened for this contract ID.";

#[error]
const EInitiatorNotParty: vector<u8> =
b"The caller must be a party to the dispute.";

#[error]
const EInvalidOptionsAmount: vector<u8> =
b"The dispute must contain between 2 and 10 options.";

#[error]
const EInvalidPartyCount: vector<u8> =
b"A dispute must involve exactly two parties.";

#[error]
const EInvalidAppealCount: vector<u8> =
b"The maximum number of appeals in a dispute must be between 0 and 3.";

#[error]
const EInvalidFee: vector<u8> =
b"The provided fee amount is invalid.";

#[error]
const EInvalidPartyCap: vector<u8> =
b"The provided party capability is invalid for this dispute.";

#[error]
const ENotAppealPeriodTallied: vector<u8> =
b"Appeals are not allowed at this stage of the dispute.";

#[error]
const ENoAppealsLeft: vector<u8> =
b"No appeals remaining for this dispute.";

#[error]
const EWrongParty: vector<u8> =
b"The fee must be paid by the opposing party.";

#[error]
const EDisputeNotTie: vector<u8> =
b"Dispute outcome is not tied.";

// === Structs ===
public enum Status has copy, drop, store {
    Running,
    Halted,
}

public struct Stake has drop, store {
    amount: u64,          // NVR
    locked_amount: u64,   // NVR
    reward_amount: u64,   // SUI
    in_worker_pool: bool,
}

public struct DisputeDetails has drop, store {
    dispute_id: ID,
    depositors: VecMap<address, u64>, // Amount per address
}

public struct DefaultTimeTable has drop, store {
    default_response_period_ms: u64,
    default_evidence_period_ms: u64,
    default_voting_period_ms: u64,
    default_appeal_period_ms: u64,
}

public struct Court has key {
    id: UID,
    inner: Versioned,
}

public struct CourtInner has store {
    allowed_versions: VecSet<u64>,
    status: Status,
    ai_court: bool,
    sanction_model: u64,
    coefficient: u64,
    treasury_share: u64,
    treasury_share_nvr: u64,
    empty_vote_penalty: u64,
    dispute_fee: u64,
    min_stake: u64,
    timetable: DefaultTimeTable,
    cases: Table<ID, DisputeDetails>,
    stakes: LinkedTable<address, Stake>,
    worker_pool: WorkerPool,
    stake_pool: Balance<NVR>,
    reward_pool: Balance<SUI>,
}

// === Events ===

public struct StakeEvent has copy, drop {
    sender: address,
    amount: u64,
}

public struct WithdrawEvent has copy, drop {
    sender: address,
    amount_nvr: u64,
    amount_sui: u64,
}

// === Public Functions ===
/// Adds NVR stake to the court’s stake pool.
/// 
/// Aborts if:
/// - The court is not in the `Running` state
/// - The deposited stake amount is less than the minimum required stake
public fun stake(self: &mut Court, assets: Coin<NVR>, ctx: &mut TxContext) {
    let self = self.load_inner_mut();
    let amount = assets.value();

    assert!(self.status == Status::Running, ENotOperational);
    assert!(amount >= self.min_stake, ENotEnoughNVR);

    self.stake_pool.join(assets.into_balance());
    let sender = ctx.sender();

    if (self.stakes.contains(sender)) {
        let stake = self.stakes.borrow_mut(sender);
        stake.amount = stake.amount + amount;

        // If the user is enrolled in the worker pool, automatically
        // increase the worker pool stake.
        if (stake.in_worker_pool) {
            let i = self.worker_pool.index_by_address(sender).extract();
            self.worker_pool.add_stake(i, amount);
        };
    } else {
        self.stakes.push_back(sender, Stake {
            amount,
            locked_amount: 0,
            reward_amount: 0,
            in_worker_pool: false,
        });
    };

    event::emit(StakeEvent { 
        sender, 
        amount, 
    });
}


/// Withdraws NVR stake and/or SUI rewards from the court.
/// 
/// Aborts if:
/// - The caller does not have sufficient NVR stake or SUI rewards
/// - Both withdrawal amounts are zero
public fun withdraw(
    self: &mut Court, 
    amount_nvr: u64,
    amount_sui: u64,
    ctx: &mut TxContext,
): (Coin<NVR>, Coin<SUI>) {
    let self = self.load_inner_mut();
    let sender = ctx.sender();
    let stake = self.stakes.borrow_mut(sender);

    // Check balances.
    assert!(stake.amount >= amount_nvr, ENotEnoughNVR);
    assert!(stake.reward_amount >= amount_sui, ENotEnoughSUI);
    assert!(amount_nvr > 0 || amount_sui > 0, ENoWithdrawAmount);

    // Deduct amounts.
    stake.amount = stake.amount - amount_nvr;
    stake.reward_amount = stake.reward_amount - amount_sui;

    // Automatically update worker pool stake or remove the caller
    // if the remaining stake falls below the minimum threshold.
    if (stake.in_worker_pool) {
        let i = self.worker_pool.index_by_address(sender).extract();

        if (stake.amount < self.min_stake) {
            self.worker_pool.swap_remove(i);
            stake.in_worker_pool = false;
        } else {
            self.worker_pool.sub_stake(i, amount_nvr);
        };
    };

    let nvr = self.stake_pool.split(amount_nvr).into_coin(ctx);
    let sui = self.reward_pool.split(amount_sui).into_coin(ctx);

    event::emit(WithdrawEvent { 
        sender, 
        amount_nvr,
        amount_sui,
    });
    
    (nvr, sui)
}

/// Enrolls the caller in the court’s worker pool.
/// 
/// Aborts if:
/// - The court is not in the `Running` state
/// - The caller does not have the minimum required stake
/// - The caller is already enrolled in the worker pool
/// - The worker pool has reached its maximum capacity
public fun join_worker_pool(self: &mut Court, ctx: &mut TxContext) {
    let self = self.load_inner_mut();
    let sender = ctx.sender();
    let stake = self.stakes.borrow_mut(sender);

    assert!(self.status == Status::Running, ENotOperational);
    assert!(stake.amount >= self.min_stake, ENotEnoughNVR);
    assert!(!stake.in_worker_pool, EAlreadyInWorkerPool);

    self.worker_pool.push_back(sender, stake.amount);
    stake.in_worker_pool = true;
}

/// Removes the caller from the worker pool while retaining their stake.
/// 
/// Aborts if:
/// - The caller is not currently enrolled in the worker pool
public fun leave_worker_pool(self: &mut Court, ctx: &mut TxContext) {
    let self = self.load_inner_mut();
    let sender = ctx.sender();
    let stake = self.stakes.borrow_mut(sender);

    assert!(stake.in_worker_pool, ENotInWorkerPool);

    let i = self.worker_pool.index_by_address(sender).extract();
    self.worker_pool.swap_remove(i);
    stake.in_worker_pool = false;
}

/// Opens a new dispute in the specified court for a given contract.
/// 
/// The caller initiates a dispute by paying the court’s dispute fee and
/// specifying the involved parties, voting options, and dispute parameters.
/// An initial set of jurors ("nivsters") is randomly selected from the worker
/// pool using stake-weighted selection.
/// 
/// 
/// The caller must be one of the dispute parties. Only one dispute may exist
/// per contract at any given time.
/// 
/// Aborts if:
/// - The court is not in the `Running` state
/// - The provided fee does not match the court’s required dispute fee
/// - The number of voting options is outside the allowed range
/// - The number of parties is not exactly two
/// - The caller is not one of the dispute parties
/// - The maximum number of appeals exceeds the court’s limit
/// - A dispute has already been opened for the specified contract ID
/// - The worker pool does not contain enough eligible nivsters to initialize the case
entry fun open_dispute(
    court: &mut Court,
    fee: Coin<SUI>,
    contract: ID,
    description: String,
    parties: vector<address>,
    options: vector<String>,
    max_appeals: u8,
    response_period_ms: Option<u64>,
    evidence_period_ms: Option<u64>,
    voting_period_ms: Option<u64>,
    appeal_period_ms: Option<u64>,
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
    threshold: u8,
    r: &Random,
    clock: &Clock, 
    ctx: &mut TxContext
) {
    let court_id = object::id(court);
    let self = court.load_inner_mut();

    assert!(self.status == Status::Running, ENotOperational);
    assert!(fee.value() == self.dispute_fee, EInvalidFee);
    // Enforce the dispute limitations.
    assert!(options.length() >= MIN_OPTIONS && options.length() <= MAX_OPTIONS, EInvalidOptionsAmount);
    assert!(parties.length() == PARTY_COUNT, EInvalidPartyCount);
    assert!(parties.contains(&ctx.sender()), EInitiatorNotParty);
    assert!(max_appeals <= MAX_APPEALS, EInvalidAppealCount);
    assert!(!self.cases.contains(contract), EDisputeAlreadyExists);

    // Unwrap dispute timetable or use court defaults if not specified.
    let response_period = response_period_ms.destroy_or!(self.timetable.default_response_period_ms);
    let evidence_period = evidence_period_ms.destroy_or!(self.timetable.default_evidence_period_ms);
    let voting_period = voting_period_ms.destroy_or!(self.timetable.default_voting_period_ms);
    let appeal_period = appeal_period_ms.destroy_or!(self.timetable.default_appeal_period_ms);

    // Draw initial nivsters to the case.
    let mut nivsters = linked_table::new(ctx);
    draw_nivsters(self, &mut nivsters, INIT_NIVSTER_COUNT, r, ctx);

    let dispute_id = create_dispute(
        ctx.sender(),
        contract,
        court_id,
        description,
        response_period,
        evidence_period, 
        voting_period, 
        appeal_period, 
        max_appeals, 
        parties, 
        nivsters, 
        options, 
        key_servers, 
        public_keys, 
        threshold,
        clock, 
        ctx
    );

    // Create dispute details and add deposit for the initial dispute fee.
    let mut dispute_details = DisputeDetails {
        dispute_id,
        depositors: vec_map::empty(),
    };

    dispute_details.depositors.insert(ctx.sender(), fee.value());
    self.reward_pool.join(fee.into_balance());
    self.cases.add(contract, dispute_details);
}

/// Starts a new appeal round for an existing dispute.
/// 
/// Each appeal increases the number of jurors ("nivsters") assigned to the
/// dispute. After appeal round `i`, the total juror count `J` is:
///
/// `J = 2^i * N + (2^i - 1) + T`
///
/// where:
/// - `i` is the current appeal count
/// - `N` is the initial juror count
/// - `T` is the number of additional jurors drawn due to tie resolutions
/// 
/// The appeal fee `F` grows exponentially with each round `i` and must be paid by
/// an authorized dispute party to initiate the appeal:
/// 
/// `F = (13/5)^i * Fn`
/// 
/// where:
/// - `i` is the current appeal count
/// - `Fn` is the court's base dispute fee
/// 
/// Aborts if:
/// - The provided party capability does not correspond to the dispute
/// - The dispute is not in a state where appeals are allowed
/// - The dispute has reached the maximum number of appeals
/// - The worker pool does not contain enough eligible jurors to extend the case
entry fun open_appeal(
    court: &mut Court,
    dispute: &mut Dispute,
    fee: Coin<SUI>,
    cap: &PartyCap,
    clock: &Clock,
    r: &Random,
    ctx: &mut TxContext,
) {
    assert!(object::id(dispute) == cap.dispute_id_party(), EInvalidPartyCap);
    assert!(dispute.is_appeal_period_tallied(clock), ENotAppealPeriodTallied);
    assert!(dispute.has_appeals_left(), ENoAppealsLeft);

    let self = court.load_inner_mut();
    let appeal_count = dispute.appeals_used() + 1;

    // Fee = 13^i * Fn / 5^i, where Fn = base dispute fee & i = appeal count.
    let appeal_fee = divide_and_round_up(self.dispute_fee * pow(13, appeal_count), pow(5, appeal_count));
    assert!(fee.value() == appeal_fee, EInvalidFee);

    // Increment amount = 2^(i-1) * (N + 1), where N = initial nivster count & i = appeal count.
    let nivster_count = pow(2, appeal_count - 1) * (INIT_NIVSTER_COUNT + 1);
    self.draw_nivsters(dispute.voters_mut(), nivster_count, r, ctx);

    // Deposit coins
    let case = self.cases.borrow_mut(dispute.contract());
    let deposit = case.depositors.get_mut(&cap.party());
    *deposit = *deposit + fee.value();

    self.reward_pool.join(fee.into_balance());

    // Start a new appeal round
    dispute.start_new_round_appeal(clock, ctx);
}

/// Accepts an open dispute or appeal by the opposing party and deposits
/// the required response fee.
/// 
/// The responding party must pay a fee `F`, defined as:
/// 
/// `F = (13/5)^i * Fn`
/// 
/// where:
/// - `i` is the current appeal count
/// - `Fn` is the court's base dispute fee
/// 
/// The fee must be paid by the party that has not yet matched the
/// opposing party’s deposit. Once both parties have deposited equal
/// amounts, the dispute becomes active.
/// 
/// Aborts if:
/// - The provided party capability does not correspond to the dispute
/// - The dispute is not in a response period
/// - The fee amount is incorrect
/// - The fee is paid by the wrong party
public fun accept_dispute(
    court: &mut Court,
    dispute: &mut Dispute,
    fee: Coin<SUI>,
    cap: &PartyCap,
    clock: &Clock,
) {
    assert!(dispute.is_response_period(clock), ENotResponsePeriod);
    assert!(object::id(dispute) == cap.dispute_id_party(), EInvalidPartyCap);

    let self = court.load_inner_mut();
    let appeal_count = dispute.appeals_used();

    // Fee = 13^i * Fn / 5^i, where Fn = base dispute fee & i = appeal count.
    let outstanding_fee = divide_and_round_up(self.dispute_fee * pow(13, appeal_count), pow(5, appeal_count));
    assert!(fee.value() == outstanding_fee, EInvalidFee);

    let dispute_details = self.cases.borrow_mut(dispute.contract());
    let mut depositors = dispute_details.depositors;

    if (depositors.length() == 2) {
        // Dispute appeal scenario.
        let payer_balance = depositors.get_mut(&cap.party());
        *payer_balance = *payer_balance + fee.value();
    } else {
        // Dispute opening scenario. The other party has not made deposits yet.
        depositors.insert(cap.party(), fee.value());
    };

    // Make sure that the fee is paid by the opposing party.
    let (_, balance) = depositors.get_entry_by_idx(0);
    let (_, balance_other) = depositors.get_entry_by_idx(1);
    assert!(balance == balance_other, EWrongParty);

    self.reward_pool.join(fee.into_balance());

    // Dispute status is set to active after the other party accepts the case.
    dispute.set_status(dispute_status_active());
}

/// Handles dispute ties by drawing more nivsters and starting a new round.
/// 
/// Aborts if:
/// - Dispute is not in a tie period
/// - The worker pool does not contain enough eligible jurors to extend the case
entry fun handle_dispute_tie(
    court: &mut Court,
    dispute: &mut Dispute,
    clock: &Clock,
    r: &Random,
    ctx: &mut TxContext,
) {
    assert!(dispute.is_appeal_period_tie(clock), EDisputeNotTie);

    let court = court.load_inner_mut();
    court.draw_nivsters(dispute.voters_mut(), TIE_NIVSTER_COUNT, r, ctx);
    dispute.start_new_round_tie(clock, ctx);
}

/// Cancels a failed or abandoned dispute.
/// 
/// A dispute may be cancelled if it fails to progress to completion
/// (e.g. votes are not counted or a tie is not resolved within the allowed time window).
/// 
/// Aborts if:
/// - The dispute is not in a cancellable (incomplete) state
public fun cancel_dispute(
    dispute: &mut Dispute,
    court: &mut Court,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(dispute.is_incomplete(clock), EDisputeNotCancellable);
    dispute.set_status(dispute_status_cancelled());

    let self = court.load_inner_mut();
    // Remove the case from the case map, so a new case can be opened for the contract.
    let dispute_details = self.cases.remove(dispute.contract());

    // Refund the parties in full.
    let (depositor_1, amount_1) = dispute_details.depositors.get_entry_by_idx(0);
    let (depositor_2, amount_2) = dispute_details.depositors.get_entry_by_idx(1);

    transfer::public_transfer(self.reward_pool.split(*amount_1).into_coin(ctx), *depositor_1);
    transfer::public_transfer(self.reward_pool.split(*amount_2).into_coin(ctx), *depositor_2);
}

/// Resolves a one-sided dispute where one party failed to pay the required
/// dispute or appeal fee within the allowed time window.
/// 
/// A one-sided resolution occurs when only a single party has successfully
/// funded the dispute or an appeal round. In this case, the funded party
/// automatically wins without juror voting.
/// 
/// Aborts if:
/// - The dispute is not eligible for one-sided resolution
public fun resolve_one_sided_dispute(
    court: &mut Court,
    dispute: &mut Dispute,
    court_registry: &CourtRegistry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(dispute.party_failed_payment(clock), EDisputeNotOneSided);
    dispute.set_status(dispute_status_completed_one_sided());

    let court_id = object::id(court);
    let self = court.load_inner_mut();
    let dispute_details = self.cases.borrow(dispute.contract());

    // Refund the winner.
    let (mut winner_party, mut winner_amount) = dispute_details.depositors.get_entry_by_idx(0);
    let (party_2, amount_2) = dispute_details.depositors.get_entry_by_idx(1);

    if (*amount_2 > *winner_amount) {
        winner_party = party_2;
        winner_amount = amount_2;
    };

    transfer::public_transfer(self.reward_pool.split(*winner_amount).into_coin(ctx), *winner_party);
    // Send the result to both parties.
    dispute.parties().do!(|party| transfer::public_transfer(create_result(
        court_id, 
        object::id(dispute), 
        dispute.contract(), 
        dispute.options(), 
        option::none(), 
        dispute.parties(), 
        dispute.parties()
        .find_index!(|addr| addr == *winner_party)
        .extract(), 
        dispute.max_appeals(), 
        ctx
    ), party));

    // Distribute protocol fees to the treasury.
    let appeal_count = dispute.appeals_used();
    let voter_count = dispute.voters().length();

    if (appeal_count >= 1) {
        // if appeals = 1, then the party has paid the dispute opening fee.
        let base_cut = self.dispute_fee * (100 - self.treasury_share) / 100;
        let mut total_cut = self.dispute_fee * self.treasury_share / 100;
        let mut appeal_round = appeal_count;

        // if appeals > 1, then the party has also paid for appeal rounds.
        while (appeal_round > 1) {
            appeal_round = appeal_round - 1; // the paid round is one lower than the actual round.
            let appeal_fee = divide_and_round_up(
                self.dispute_fee * pow(13, appeal_round), 
                pow(5, appeal_round)
            );
            let nivsters_cut = base_cut * (
                pow(2, appeal_round) + 
                (pow(2, appeal_round) - 1) / voter_count
            );

            total_cut = total_cut + appeal_fee - nivsters_cut;
        };

        transfer::public_transfer(
            self.reward_pool.split(total_cut).into_coin(ctx), 
            court_registry.treasury_address()
        );
    };
}

/// Finalizes a fully adjudicated dispute after voting and tallying have completed.
/// 
/// This function may be called once the dispute has reached a terminal state
/// and a winning option has been determined by juror voting.
/// 
/// Aborts if:
/// - The dispute has not completed voting and tallying
public fun complete_dispute(
    court: &mut Court,
    dispute: &mut Dispute,
    court_registry: &CourtRegistry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(dispute.is_completed(clock), EDisputeNotCompleted);
    dispute.set_status(dispute_status_completed());

    let court_id = object::id(court);
    let self = court.load_inner_mut();
    let dispute_details = self.cases.borrow(dispute.contract());

    // Refund the winner party.
    let idx = dispute.winner_party().extract() as u64;
    let winner_party = dispute.parties()[idx];
    let deposit = dispute_details.depositors.get(&winner_party);

    transfer::public_transfer(
        self.reward_pool.split(*deposit).into_coin(ctx), 
        winner_party
    );

    // Distribute result to parties.
    dispute.parties().do!(|party| transfer::public_transfer(create_result(
        court_id, 
        object::id(dispute), 
        dispute.contract(), 
        dispute.options(), 
        dispute.winner_option(), 
        dispute.parties(), 
        idx, 
        dispute.max_appeals(), 
        ctx
    ), party));

    // Distribute protocol fees to the treasury.
    let mut appeal_count = dispute.appeals_used();
    let voter_count = dispute.voters().length();
    let base_cut = self.dispute_fee * (100 - self.treasury_share) / 100;
    let mut total_cut = self.dispute_fee * self.treasury_share / 100;

    while (appeal_count > 0) {
        let appeal_fee = divide_and_round_up(
            self.dispute_fee * pow(13, appeal_count), 
            pow(5, appeal_count)
        );
        let nivsters_cut = base_cut * (
            pow(2, appeal_count) + 
            (pow(2, appeal_count) - 1) / voter_count
        );

        total_cut = total_cut + appeal_fee - nivsters_cut;
        appeal_count = appeal_count - 1;
    };

    transfer::public_transfer(
        self.reward_pool.split(total_cut).into_coin(ctx), 
        court_registry.treasury_address()
    );

    // NVR fees.
    let winner_option = dispute.winner_option().extract();
    let winner_count = dispute.result()[winner_option as u64];
    let mut total_votes = 0;
    dispute.result().do!(|count| total_votes = total_votes + count);
    let minority = total_votes - winner_count;
    let voters = dispute.voters();
    let (p, _) = minority_penalties_and_majority_stakes(
        voters,
        winner_option,
        self.sanction_model,
        self.min_stake,
        self.empty_vote_penalty,
        self.coefficient,
        total_votes,
        winner_count,
        minority,
    );

    let nivra_cut = p * self.treasury_share_nvr / 100;

    transfer::public_transfer(
        self.stake_pool.split(nivra_cut).into_coin(ctx), 
        court_registry.treasury_address()
    );
}

/// Refunds a juror’s locked stake when a dispute is cancelled.
/// 
/// If a dispute is cancelled, participating jurors ("nivsters") may reclaim
/// the stake that was locked for the case. The refunded amount is proportional
/// to the juror’s voting weight and equals:
///
/// `locked_refund = votes × minimum_stake`
/// 
/// Aborts if:
/// - The dispute is not in the `Cancelled` state
/// - The juror has already collected their refund
public fun collect_rewards_cancelled(
    court: &mut Court,
    dispute: &mut Dispute,
    cap: &VoterCap,
) {
    assert!(dispute.status() == dispute_status_cancelled(), EDisputeNotCancelled);
    assert!(cap.dispute_id_voter() == object::id(dispute), EInvalidVoterCap);

    let self = court.load_inner_mut();
    let voter_details = dispute.voters_mut().borrow_mut(cap.voter());
    let stake = self.stakes.borrow_mut(cap.voter());

    assert!(!voter_details.reward_collected(), ERewardAlreadyCollected);

    let case_locked_amount = voter_details.votes() * self.min_stake;

    stake.locked_amount = stake.locked_amount - case_locked_amount;
    stake.amount = stake.amount + case_locked_amount;
    voter_details.set_reward_collected();

    if (stake.in_worker_pool) {
        let i = self.worker_pool.index_by_address(cap.voter()).extract();
        self.worker_pool.add_stake(i, case_locked_amount);
    };
}

/// Collects juror rewards for a one-sided dispute resolution.
/// 
/// A dispute is considered *one-sided* when one party fails to pay the
/// required dispute or appeal fee. In this case, the paying party
/// automatically prevails and any fees paid by the opposing party are
/// redistributed to participating jurors ("nivsters").
/// 
/// Aborts if:
/// - The dispute is not in the `CompletedOneSided` state
/// - The juror has already collected rewards for this dispute
public fun collect_rewards_one_sided(
    court: &mut Court,
    dispute: &mut Dispute,
    cap: &VoterCap,
) {
    assert!(dispute.status() == dispute_status_completed_one_sided(), EDisputeNotCompletedOneSided);
    assert!(cap.dispute_id_voter() == object::id(dispute), EInvalidVoterCap);

    let self = court.load_inner_mut();
    let appeal_count = dispute.appeals_used();
    let voter_count = dispute.voters().length();
    let voter_details = dispute.voters_mut().borrow_mut(cap.voter());
    let stake = self.stakes.borrow_mut(cap.voter());

    assert!(!voter_details.reward_collected(), ERewardAlreadyCollected);

    // Distribute any sui lost by the another party to the nivsters.
    if (appeal_count >= 1) {
        // if appeals = 1, then the party has paid the dispute opening fee.
        let base_cut = self.dispute_fee * (100 - self.treasury_share) / 100;
        let mut total_cut = base_cut;
        let mut appeal_round = appeal_count;

        // if appeals > 1, then the party has also paid for appeal rounds.
        while (appeal_round > 1) {
            appeal_round = appeal_round - 1; // the paid round is one lower than the actual round.
            total_cut = total_cut + base_cut * 
            (pow(2, appeal_round) + (pow(2, appeal_round) - 1) / voter_count);
        };

        stake.reward_amount = stake.reward_amount + total_cut / voter_count;
    };

    // Unlock the users nvr stake.
    let case_locked_amount = voter_details.votes() * self.min_stake;

    stake.locked_amount = stake.locked_amount - case_locked_amount;
    stake.amount = stake.amount + case_locked_amount;
    voter_details.set_reward_collected();

    if (stake.in_worker_pool) {
        let i = self.worker_pool.index_by_address(cap.voter()).extract();
        self.worker_pool.add_stake(i, case_locked_amount);
    };
}

public fun collect_rewards_completed(
    court: &mut Court,
    dispute: &mut Dispute,
    cap: &VoterCap,
) {
    assert!(dispute.status() == dispute_status_completed(), EDisputeNotCompleted);
    assert!(cap.dispute_id_voter() == object::id(dispute), EInvalidVoterCap);

    let self = court.load_inner_mut();
    let stake = self.stakes.borrow_mut(cap.voter());
    let voters = dispute.voters();
    let voter_details = voters.borrow(cap.voter());
    let winner_option = dispute.winner_option().extract();
    let user_option = voter_details.decrypted_vote();
    let staked_amount = voter_details.votes() * self.min_stake;

    assert!(!voter_details.reward_collected(), ERewardAlreadyCollected);

    if (user_option.is_none()) {
        let penalty = staked_amount * self.empty_vote_penalty / 100;

        stake.locked_amount = stake.locked_amount - staked_amount;
        stake.amount = stake.amount + staked_amount - penalty;

        if (stake.in_worker_pool) {
            let i = self.worker_pool.index_by_address(cap.voter()).extract();
            self.worker_pool.add_stake(i, staked_amount - penalty);
        };

        let voter_details = dispute.voters_mut().borrow_mut(cap.voter());
        voter_details.set_reward_collected();

        return
    };

    let winner_count = dispute.result()[winner_option as u64];
    let mut total_votes = 0;
    dispute.result().do!(|count| total_votes = total_votes + count);
    let minority = total_votes - winner_count;

    if (user_option.borrow() != winner_option) {
        let penalty = penalty(
            self.sanction_model,
            self.coefficient, 
            staked_amount, 
            total_votes,
            winner_count,
            minority
        );

        stake.locked_amount = stake.locked_amount - staked_amount;
        stake.amount = stake.amount + staked_amount - penalty;

        if (stake.in_worker_pool) {
            let i = self.worker_pool.index_by_address(cap.voter()).extract();
            self.worker_pool.add_stake(i, staked_amount - penalty);
        };

        let voter_details = dispute.voters_mut().borrow_mut(cap.voter());
        voter_details.set_reward_collected();

        return
    };

    let (penalties, majority_stake) = minority_penalties_and_majority_stakes(
        voters, 
        winner_option, 
        self.sanction_model, 
        self.min_stake, 
        self.empty_vote_penalty, 
        self.coefficient, 
        total_votes, 
        winner_count, 
        minority
    );

    let mut appeal_count = dispute.appeals_used();
    let voter_count = dispute.voters().length();
    let base_cut = self.dispute_fee * (100 - self.treasury_share) / 100;
    let mut total_cut = base_cut;

    while (appeal_count > 0) {
        let nivsters_cut = base_cut * (
            pow(2, appeal_count) + 
            (pow(2, appeal_count) - 1) / voter_count
        );

        total_cut = total_cut + nivsters_cut;
        appeal_count = appeal_count - 1;
    };

    let sui_reward = total_cut * staked_amount / majority_stake;
    let nvr_reward = penalties * staked_amount / majority_stake;

    stake.reward_amount = stake.reward_amount + sui_reward;
    stake.amount = stake.amount + staked_amount + nvr_reward;
    stake.locked_amount = stake.locked_amount - staked_amount;

    let voter_details = dispute.voters_mut().borrow_mut(cap.voter());
    voter_details.set_reward_collected();

    if (stake.in_worker_pool) {
        let i = self.worker_pool.index_by_address(cap.voter()).extract();
        self.worker_pool.add_stake(i, staked_amount + nvr_reward);
    };
}

// === Admin Functions ===
/// Creates a new court with metadata and registers it to the court registry.
/// 
/// Aborts if:
/// - The caller’s admin capability is not authorized
public fun create_court(
    court_registry: &mut CourtRegistry,
    cap: &NivraAdminCap,
    ai_court: bool,
    category: String,
    name: String,
    description: String,
    skills: String,
    sanction_model: u64,
    coefficient: u64,
    treasury_share: u64,
    treasury_share_nvr: u64,
    empty_vote_penalty: u64,
    dispute_fee: u64,
    min_stake: u64,
    default_response_period_ms: u64,
    default_evidence_period_ms: u64,
    default_voting_period_ms: u64,
    default_appeal_period_ms: u64,
    ctx: &mut TxContext,
): ID {
    court_registry.validate_admin_privileges(cap);
    assert!(treasury_share <= 100, EInvalidTreasuryShareInternal);
    assert!(treasury_share_nvr <= 100, EInvalidTreasuryShareInternal);
    assert!(empty_vote_penalty <= 100, EInvalidTreasuryShareInternal);
    assert!(sanction_model < 3, EInvalidSanctionModelInternal);

    if (sanction_model == FIXED_PERCENTAGE_MODEL) {
        assert!(coefficient < 100, EInvalidCoefficientInternal);
    };

    if (sanction_model == MINORITY_SCALED_MODEL || 
        sanction_model == QUADRATIC_MODEL) {
        assert!(coefficient <= 100, EInvalidCoefficientInternal);
    };

    let court_inner = CourtInner {
        allowed_versions: vec_set::singleton(current_version()),
        status: Status::Running,
        ai_court,
        sanction_model,
        coefficient,
        treasury_share,
        treasury_share_nvr,
        empty_vote_penalty,
        dispute_fee,
        min_stake,
        timetable: DefaultTimeTable {
            default_response_period_ms,
            default_evidence_period_ms,
            default_voting_period_ms,
            default_appeal_period_ms,
        },
        cases: table::new(ctx),
        stakes: linked_table::new(ctx),
        worker_pool: worker_pool::empty(ctx),
        stake_pool: balance::zero<NVR>(),
        reward_pool: balance::zero<SUI>(),
    };

    let court = Court { 
        id: object::new(ctx), 
        inner: versioned::create(
            current_version(), 
            court_inner, 
            ctx
        ),
    };

    let court_id = object::id(&court);
    let metadata = create_metadata(
        category, 
        name, 
        description, 
        skills, 
        min_stake, 
    );

    court_registry.register_court(court_id, metadata);
    transfer::share_object(court);

    court_id
}

/// Halts incoming operations to the court like staking, and opening disputes.
/// 
/// Aborts if:
/// - The caller’s admin capability is not authorized
public fun halt_operation(
    self: &mut Court, 
    cap: &NivraAdminCap, 
    court_registry: &CourtRegistry
) {
    court_registry.validate_admin_privileges(cap);

    let self = self.load_inner_mut();
    self.status = Status::Halted;
}

/// Updates court's package versions to match the court registry.
/// 
/// Aborts if:
/// - The caller’s admin capability is not authorized
public fun update_allowed_versions(
    self: &mut Court,
    cap: &NivraAdminCap,
    court_registry: &CourtRegistry,
) {
    court_registry.validate_admin_privileges(cap);
    let allowed_versions = court_registry.allowed_versions();
    let inner: &mut CourtInner = self.inner.load_value_mut();
    inner.allowed_versions = allowed_versions;
}

// === Package Functions ===
/// Randomly selects jurors ("nivsters") from the worker pool for a case.
/// 
/// Selection is stake-weighted: each enrolled worker’s probability of being
/// selected is proportional to their staked amount relative to the total stake
/// in the worker pool.
/// 
/// Limitations:
/// - Unique dynamic field accesses ≈ 3 * nivster_count + 10.
/// 
/// Aborts if:
/// - The worker pool does not contain enough eligible nivsters to satisfy
///   `nivster_count`
public(package) fun draw_nivsters(
    self: &mut CourtInner, 
    nivsters: &mut LinkedTable<address, VoterDetails>, 
    nivster_count: u64,
    r: &Random,
    ctx: &mut TxContext,
) {
    // Check if there are enough nivsters for the draw.
    let potential_nivsters: u64 = self.worker_pool.length();
    assert!(potential_nivsters >= nivster_count, ENotEnoughNivsters);

    let mut nivsters_selected = 0;
    let mut generator = new_generator(r, ctx);
    let mut sum_stakes: u64 = self.worker_pool.prefix_sum(potential_nivsters - 1);

    // Draw nivsters to nivsters list until nivster count is satisified.
    while(nivsters_selected < nivster_count) {
        // Randomly generate a threshold value T from [0, SUM_STAKES].
        let selection_threshold = generator.generate_u64_in_range(0, sum_stakes);
        // Find the first nivster n whose cumulative stake sum is >= T.
        let wp_idx = self.worker_pool.search(selection_threshold);
        let (n_addr, n_stake) = self.worker_pool.get_idx(wp_idx);
        // Load nivster's stake.
        let nivster_stake = self.stakes.borrow_mut(n_addr);

        // Remove the nivster n from the worker pool to prevent duplicate selections.
        self.worker_pool.swap_remove(wp_idx);
        nivster_stake.in_worker_pool = false;

        // Fail safe, should never throw.
        assert!(n_stake == nivster_stake.amount && n_stake >= self.min_stake, EBalanceMismatchInternal);

        // Lock the minimum stake amount for a vote in the case.
        nivster_stake.amount = nivster_stake.amount - self.min_stake;
        nivster_stake.locked_amount = nivster_stake.locked_amount + self.min_stake; 

        if (nivsters.contains(n_addr)) {
            // Nivster was already chosen in a previous draw, vote count is incremented by 1.
            let nivster_details = nivsters.borrow_mut(n_addr);
            nivster_details.increment_votes();
        } else {
            nivsters.push_back(n_addr, create_voter_details());
        };

        // Narrow the selection range by nivster's stake amount.
        sum_stakes = sum_stakes - n_stake;

        nivsters_selected = nivsters_selected + 1;
    };
}

public(package) fun load_inner_mut(self: &mut Court): &mut CourtInner {
    let inner: &mut CourtInner = self.inner.load_value_mut();
    let package_version = current_version();
    assert!(inner.allowed_versions.contains(&package_version), EWrongVersion);

    inner
}

public(package) fun load_inner(self: &Court): &CourtInner {
    let inner: &CourtInner = self.inner.load_value();
    let package_version = current_version();
    assert!(inner.allowed_versions.contains(&package_version), EWrongVersion);

    inner
}

// === Private Functions ===
fun penalty(
    sanction_model: u64,
    coefficient: u64,
    staked_amount: u64,
    total_votes: u64,
    winner_votes: u64,
    minority_votes: u64,
): u64 {
    if (sanction_model == FIXED_PERCENTAGE_MODEL) {
        return staked_amount * coefficient / 100
    };

    if (sanction_model == MINORITY_SCALED_MODEL) {
        return staked_amount * coefficient / (minority_votes * 100)
    };

    if (sanction_model == QUADRATIC_MODEL) {
        return staked_amount * coefficient * pow(winner_votes, 2) 
        / (100 * pow(total_votes, 2))
    };

    0
}

fun minority_penalties_and_majority_stakes(
    voters: &LinkedTable<address, VoterDetails>,
    winner_option: u8,
    sanction_model: u64,
    min_stake: u64,
    empty_vote_penalty: u64,
    coefficient: u64,
    total_votes: u64,
    winner_votes: u64,
    minority_votes: u64,
): (u64, u64) {
    let mut p = 0;
    let mut s = 0;
    let mut i = voters.front();

    while (i.is_some()) {
        let k = *i.borrow();
        let v = voters.borrow(k);
        let staked_amount = v.votes() * min_stake;

        if (v.decrypted_vote().is_none()) {
            p = p + staked_amount * empty_vote_penalty / 100;
        } else {
            let vote = v.decrypted_vote().borrow();

            if (vote == winner_option) {
                s = s + staked_amount;
            } else {
                p = p + penalty(
                    sanction_model, 
                    coefficient, 
                    staked_amount, 
                    total_votes, 
                    winner_votes, 
                    minority_votes
                );
            };
        };

        i = voters.next(k)
    };

    (p, s)
}