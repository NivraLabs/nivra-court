// © 2026 Nivra Labs Ltd.

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
use token::nvr::NVR;
use nivra::{
    court_registry::{create_metadata, CourtRegistry, NivraAdminCap},
    constants::{
        dispute_status_completed_one_sided,
        dispute_status_cancelled,
        dispute_status_completed,
        dispute_status_active,
        dispute_status_draw,
        current_version,
    },
    worker_pool::{WorkerPool, Self},
    dispute::{
        distribute_voter_caps,
        create_voter_details,
        create_dispute,
        VoterDetails,
        Dispute,
        PartyCap,
        VoterCap,
    },
    result::create_result,
};
use std::string::String;
use sui::{
    linked_table::{LinkedTable, borrow_mut, Self},
    versioned::{Versioned, Self},
    balance::{Balance, Self},
    vec_map::{VecMap, Self},
    random::{new_generator, Random},
    table::{Table, Self},
    vec_set::VecSet,
    clock::Clock,
    coin::Coin,
    sui::SUI,
    event,
};

// === Constants ===
// Sanction models
const FIXED_PERCENTAGE_MODEL: u64 = 0;
const MINORITY_SCALED_MODEL: u64 = 1;
const QUADRATIC_MODEL: u64 = 2;
// Default dispute rules
const INIT_NIVSTER_COUNT: u64 = 1;
const TIE_NIVSTER_COUNT: u64 = 1;
const MIN_OPTIONS: u64 = 2;
const MAX_OPTIONS: u64 = 5;
const PARTY_COUNT: u64 = 2;
const MAX_APPEALS: u8 = 3;
const MAX_DESCRIPTION_LEN: u64 = 2000;
const MAX_OPTION_LEN: u64 = 50;

// === Errors ===
const EWrongVersion: u64 = 1;
const ENotResponsePeriod: u64 = 7;
const EBalanceMismatchInternal: u64 = 18;
const EDisputeNotCompleted: u64 = 26;
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
const EZeroMinStakeInternal: u64 = 40;
const EInvalidThresholdInternal: u64 = 41;
const EInvalidKeyConfigInternal: u64 = 42;
const ENotDrawPeriod: u64 = 43;

#[error]
const EOptionTooLong: vector<u8> =
b"Each voting option must be at most 50 bytes long.";

#[error]
const EDescriptionTooLong: vector<u8> =
b"The dispute description must be at most 2000 bytes long.";

#[error]
const EDuplicateOptions: vector<u8> = 
b"Voting options must be unique.";

#[error]
const ENoStake: vector<u8> = 
b"Caller has no stake in the court.";

#[error]
const EDepositUnderMinStake: vector<u8> =
b"Deposit amount is below the court's minimum required stake.";

#[error]
const ENotEnoughNVR: vector<u8> =
b"Insufficient NVR balance to complete the withdrawal.";

#[error]
const ENotEnoughSUI: vector<u8> =
b"Insufficient SUI balance to complete the withdrawal.";

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
b"The dispute must contain between 2 and 5 options.";

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
const EInvalidVoterCap: vector<u8> =
b"The provided voter capability is invalid for this dispute.";

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
    amount: u64,
    locked_amount: u64,
    reward_amount: u64,
    in_worker_pool: bool,
    worker_pool_pos: u64,
}

public struct DisputeDetails has drop, store {
    dispute_id: ID,
    depositors: VecMap<address, u64>,
}

public struct DefaultTimeTable has drop, store {
    default_response_period_ms: u64,
    default_draw_period_ms: u64,
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
    cases: Table<ID, VecMap<vector<u8>, DisputeDetails>>,
    stakes: LinkedTable<address, Stake>,
    worker_pool: WorkerPool,
    stake_pool: Balance<NVR>,
    reward_pool: Balance<SUI>,
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
    threshold: u8,
}

// === Events ===
public struct BalanceDepositEvent has copy, drop {
    nivster: address,
    amount_nvr: u64,
}

public struct BalanceInitialDepositEvent has copy, drop {
    nivster: address,
    amount_nvr: u64,
}

public struct BalanceWithdrawalEvent has copy, drop {
    nivster: address,
    amount_nvr: u64,
    amount_sui: u64,
}

public struct BalanceLockedEvent has copy, drop {
    nivster: address,
    amount_nvr: u64,
    dispute_id: ID,
}

public struct BalanceUnlockedEvent has copy, drop {
    nivster: address,
    amount_nvr: u64,
    dispute_id: ID,
}

public struct BalanceRewardEvent has copy, drop {
    nivster: address,
    amount_nvr: u64,
    amount_sui: u64,
    dispute_id: ID,
}

public struct BalancePenaltyEvent has copy, drop {
    nivster: address,
    amount_nvr: u64,
    dispute_id: ID,
}

public struct WorkerPoolEntryEvent has copy, drop {
    nivster: address,
}

public struct WorkerPoolDepartEvent has copy, drop {
    nivster: address,
}

public struct DisputeCreationEvent has copy, drop {
    dispute_id: ID,
    contract_id: ID,
    court_id: ID,
    initiator: address,
    max_appeals: u8,
    description: String,
    parties: vector<address>,
    options: vector<String>,
    response_period_ms: u64,
    draw_period_ms: u64,
    evidence_period_ms: u64,
    voting_period_ms: u64,
    appeal_period_ms: u64,
    sanction_model: u64,
    coefficient: u64,
    treasury_share: u64,
    treasury_share_nvr: u64,
    empty_vote_penalty: u64,
    dispute_fee: u64,
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
    threshold: u8,
}

public struct DisputeAppealEvent has copy, drop {
    dispute_id: ID,
    initiator_party: address,
    fee: u64,
}

public struct DisputeAcceptEvent has copy, drop {
    dispute_id: ID,
    accepting_party: address,
    fee: u64,
}

public struct DisputeTieEvent has copy, drop {
    dispute_id: ID,
}

public struct DisputeCancelEvent has copy, drop {
    dispute_id: ID,
}

public struct DisputeOneSidedCompletionEvent has copy, drop {
    dispute_id: ID,
    winner_party: address,
}

public struct DisputeCompletionEvent has copy, drop {
    dispute_id: ID,
    winner_party: address,
    winner_option: String,
}

public struct NivsterSelectionEvent has copy, drop {
    dispute_id: ID,
    nivster: address,
}

public struct NivsterReselectionEvent has copy, drop {
    dispute_id: ID,
    nivster: address,
}

// === Public Functions ===
/// Adds stake to the court.
/// 
/// The deposited NVR is added to the court’s stake pool and credited to the
/// caller’s available stake. If the caller is already enrolled in the worker
/// pool, their worker pool stake weight is automatically increased to reflect
/// the additional deposit.
/// 
/// Aborts if:
/// - The court is not in the `Running` state
/// - The deposited stake amount is less than the minimum required stake
public fun stake(self: &mut Court, assets: Coin<NVR>, ctx: &mut TxContext) {
    let self = self.load_inner_mut();
    let deposit_amount = assets.value();

    assert!(self.status == Status::Running, ENotOperational);
    assert!(deposit_amount >= self.min_stake, EDepositUnderMinStake);

    self.stake_pool.join(assets.into_balance());
    let sender = ctx.sender();

    if (self.stakes.contains(sender)) {
        let stake = self.stakes.borrow_mut(sender);
        stake.amount = stake.amount + deposit_amount;

        // If the user is enrolled in the worker pool, automatically
        // increase the worker pool stake.
        if (stake.in_worker_pool) {
            self.worker_pool.add_stake(
                stake.worker_pool_pos, 
                deposit_amount
            );
        };

        event::emit(BalanceDepositEvent { 
            nivster: sender, 
            amount_nvr: deposit_amount,
        });
    } else {
        self.stakes.push_back(sender, Stake {
            amount: deposit_amount,
            locked_amount: 0,
            reward_amount: 0,
            in_worker_pool: false,
            worker_pool_pos: 10_001,
        });

        event::emit(BalanceInitialDepositEvent { 
            nivster: sender, 
            amount_nvr: deposit_amount, 
        });
    };
}


/// Withdraws available NVR stake and/or accumulated SUI rewards from the court.
/// 
/// The caller may withdraw either or both assets in a single transaction.
/// Withdrawn NVR is deducted from the caller’s available (unlocked) stake,
/// while withdrawn SUI is deducted from accumulated rewards.
/// 
/// If the caller is enrolled in the worker pool, the worker pool stake is
/// automatically updated. If the remaining NVR stake falls below the court’s
/// minimum stake requirement, the caller is removed from the worker pool.
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
    if (stake.in_worker_pool && amount_nvr > 0) {
        if (stake.amount < self.min_stake) {
            remove_from_worker_pool(self, sender, stake.worker_pool_pos);
        } else {
            self.worker_pool.sub_stake(stake.worker_pool_pos, amount_nvr);
        };
    };

    let nvr = self.stake_pool.split(amount_nvr).into_coin(ctx);
    let sui = self.reward_pool.split(amount_sui).into_coin(ctx);

    event::emit(BalanceWithdrawalEvent {
        nivster: sender,
        amount_nvr,
        amount_sui,
    });
    
    (nvr, sui)
}

/// Enrolls the caller in the court’s worker pool.
/// 
/// Aborts if:
/// - The court is not in the `Running` state
/// - The user does not have a stake in the court.
/// - The caller does not have the minimum required stake
/// - The caller is already enrolled in the worker pool
/// - The worker pool has reached its maximum capacity
/// 
/// Emits:
/// - `WorkerPoolEntryEvent` recording the caller's entry to the worker pool
public fun join_worker_pool(self: &mut Court, ctx: &mut TxContext) {
    let self = self.load_inner_mut();
    let sender = ctx.sender();

    assert!(self.stakes.contains(sender), ENoStake);

    let stake = self.stakes.borrow_mut(sender);

    assert!(self.status == Status::Running, ENotOperational);
    assert!(stake.amount >= self.min_stake, ENotEnoughNVR);
    assert!(!stake.in_worker_pool, EAlreadyInWorkerPool);

    self.worker_pool.push_back(sender, stake.amount);
    stake.in_worker_pool = true;
    stake.worker_pool_pos = self.worker_pool.length() - 1;

    event::emit(WorkerPoolEntryEvent {
        nivster: sender,
    });
}

/// Removes the caller from the worker pool while retaining their stake.
/// 
/// Aborts if:
/// - The caller is not currently enrolled in the worker pool
/// - The user does not have a stake in the court.
/// 
/// Emits:
/// - `WorkerPoolDepartEvent` recording the caller's exit from the worker pool
public fun leave_worker_pool(self: &mut Court, ctx: &mut TxContext) {
    let self = self.load_inner_mut();
    let sender = ctx.sender();

    assert!(self.stakes.contains(sender), ENoStake);

    let stake = self.stakes.borrow_mut(sender);

    assert!(stake.in_worker_pool, ENotInWorkerPool);

    remove_from_worker_pool(self, sender, stake.worker_pool_pos);

    event::emit(WorkerPoolDepartEvent {
        nivster: sender,
    });
}

/// Opens a new dispute in the specified court for a given contract.
public fun open_dispute(
    court: &mut Court,
    fee: Coin<SUI>,
    contract: ID,
    description: String,
    parties: vector<address>,
    options: vector<String>,
    max_appeals: u8,
    clock: &Clock, 
    ctx: &mut TxContext
) {
    let court_id = object::id(court);
    let self = court.load_inner_mut();

    assert!(self.status == Status::Running, ENotOperational);
    assert!(fee.value() == self.dispute_fee, EInvalidFee);
    // Enforce the dispute limitations.
    assert!(
        options.length() == 0 || 
        (options.length() >= MIN_OPTIONS && options.length() <= MAX_OPTIONS), 
        EInvalidOptionsAmount
    );
    assert!(parties.length() == PARTY_COUNT, EInvalidPartyCount);
    assert!(parties[0] != parties[1], EInvalidPartyCount);
    assert!(parties.contains(&ctx.sender()), EInitiatorNotParty);
    assert!(max_appeals <= MAX_APPEALS, EInvalidAppealCount);
    assert!(description.length() <= MAX_DESCRIPTION_LEN, EDescriptionTooLong);

    // Check if all the options are unique and less than the max length.
    let mut i = 0;

    while(i < options.length()) {
        let mut j = i + 1;
        assert!(
            options[i].length() > 0 && options[i].length() <= MAX_OPTION_LEN, 
            EOptionTooLong
        );

        while (j < options.length()) {
            assert!(options[i] != options[j], EDuplicateOptions);
            j = j + 1;
        };
        i = i + 1;
    };

    let serialized_config = serialize_dispute_config(
        contract, 
        parties, 
        options, 
        max_appeals
    );

    assert!(
        !dispute_exists_for_contract(self, contract, &serialized_config), 
        EDisputeAlreadyExists
    );

    let dispute_id = create_dispute(
        ctx.sender(),
        contract,
        court_id,
        description,
        self.timetable.default_response_period_ms,
        self.timetable.default_draw_period_ms,
        self.timetable.default_evidence_period_ms, 
        self.timetable.default_voting_period_ms, 
        self.timetable.default_appeal_period_ms, 
        max_appeals, 
        parties, 
        linked_table::new(ctx), 
        options, 
        self.key_servers, 
        self.public_keys, 
        self.threshold,
        serialized_config,
        self.dispute_fee,
        self.sanction_model,
        self.coefficient,
        self.treasury_share,
        self.treasury_share_nvr,
        self.empty_vote_penalty,
        clock, 
        ctx
    );

    // Create dispute details and add deposit for the initial dispute fee.
    let mut dispute_details = DisputeDetails {
        dispute_id,
        depositors: vec_map::empty(),
    };

    dispute_details.depositors.insert(ctx.sender(), fee.value());

    if (!self.cases.contains(contract)) {
        self.cases.add(contract, vec_map::empty());
    };

    self.cases
    .borrow_mut(contract)
    .insert(serialized_config, dispute_details);

    event::emit(DisputeCreationEvent {
        dispute_id,
        contract_id: contract,
        court_id,
        initiator: ctx.sender(),
        max_appeals,
        description,
        parties,
        options,
        response_period_ms: self.timetable.default_response_period_ms,
        draw_period_ms: self.timetable.default_draw_period_ms,
        evidence_period_ms: self.timetable.default_evidence_period_ms,
        voting_period_ms: self.timetable.default_voting_period_ms,
        appeal_period_ms: self.timetable.default_appeal_period_ms,
        sanction_model: self.sanction_model,
        coefficient: self.coefficient,
        treasury_share: self.treasury_share,
        treasury_share_nvr: self.treasury_share_nvr,
        empty_vote_penalty: self.empty_vote_penalty,
        dispute_fee: self.dispute_fee,
        key_servers: self.key_servers,
        public_keys: self.public_keys,
        threshold: self.threshold,
    });

    self.reward_pool.join(fee.into_balance());
}

/// Draws initial nivsters after both parties have accepted the case
entry fun draw_initial_nivsters(
    court: &mut Court,
    dispute: &mut Dispute,
    clock: &Clock,
    r: &Random,
    ctx: &mut TxContext,
) {
    assert!(dispute.is_draw_period(clock), ENotDrawPeriod);

    let self = court.load_inner_mut();
    let dispute_id = object::id(dispute);

    self.draw_nivsters(
        dispute.voters_mut(), 
        INIT_NIVSTER_COUNT, 
        dispute_id,
        r, 
        ctx
    );

    distribute_voter_caps(dispute.voters_mut(), dispute_id, ctx);
    dispute.set_status(dispute_status_active());
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
/// The appeal fee `F` grows exponentially with each round `i` and must be paid 
/// by an authorized dispute party to initiate the appeal:
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
/// 
/// Emits:
/// - `DisputeAppealEvent` recording the start of an appeal round
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
    assert!(dispute.parties().contains(&cap.party()), EInvalidPartyCap);
    assert!(dispute.is_appeal_period_tallied(clock), ENotAppealPeriodTallied);
    assert!(dispute.has_appeals_left(), ENoAppealsLeft);

    let self = court.load_inner_mut();
    let appeal_count = dispute.appeals_used() + 1;

    // Fee = 13^i * Fn / 5^i, where Fn = base dispute fee & i = appeal count.
    // The appeal count is hard capped at 3.
    let appeal_fee = std::u128::divide_and_round_up(
        dispute.dispute_fee() as u128 * std::u128::pow(13, appeal_count), 
        std::u128::pow(5, appeal_count)
    );
    assert!(fee.value() == appeal_fee as u64, EInvalidFee);

    // Increment amount = 2^(i-1) * (N + 1), where N = initial nivster count 
    // & i = appeal count.
    let nivster_count = std::u64::pow(2, appeal_count - 1) * 
    (INIT_NIVSTER_COUNT + 1);
    let dispute_id = object::id(dispute);

    self.draw_nivsters(
        dispute.voters_mut(), 
        nivster_count, 
        dispute_id,
        r, 
        ctx
    );

    let case = self.cases.borrow_mut(dispute.contract());
    // Both depositors must exist by now since appeal can be only raised after
    // a successful round, where both parties have made a deposit.
    let deposit = case.get_mut(dispute.serialized_config())
    .depositors
    .get_mut(&cap.party());
    *deposit = *deposit + fee.value();

    // Start a new appeal round
    dispute.start_new_round_appeal(clock, ctx);

    event::emit(DisputeAppealEvent { 
        dispute_id, 
        initiator_party: cap.party(),
        fee: fee.value(),
    });

    self.reward_pool.join(fee.into_balance());
}

/// Accepts an open dispute or appeal by the opposing party and deposits
/// the required response fee.
public fun accept_dispute(
    court: &mut Court,
    dispute: &mut Dispute,
    fee: Coin<SUI>,
    cap: &PartyCap,
    clock: &Clock,
) {
    assert!(dispute.is_response_period(clock), ENotResponsePeriod);
    assert!(object::id(dispute) == cap.dispute_id_party(), EInvalidPartyCap);
    assert!(dispute.parties().contains(&cap.party()), EInvalidPartyCap);

    let self = court.load_inner_mut();
    let appeal_count = dispute.appeals_used();

    // Fee = 13^i * Fn / 5^i, where Fn = base dispute fee & i = appeal count.
    let outstanding_fee = std::u128::divide_and_round_up(
        dispute.dispute_fee() as u128 * std::u128::pow(13, appeal_count), 
        std::u128::pow(5, appeal_count)
    );
    assert!(fee.value() == outstanding_fee as u64, EInvalidFee);

    let case = self.cases.borrow_mut(dispute.contract());
    let depositors = &mut case
    .get_mut(dispute.serialized_config())
    .depositors;

    if (depositors.length() == 2) {
        // Dispute appeal scenario.
        let payer_balance = depositors.get_mut(&cap.party());
        
        *payer_balance = *payer_balance + fee.value();

        let (_, balance_1) = depositors.get_entry_by_idx(0);
        let (_, balance_2) = depositors.get_entry_by_idx(1);

        assert!(*balance_1 == *balance_2, EWrongParty);

        dispute.set_status(dispute_status_active());
    } else {
        // Dispute opening scenario. The other party has not made deposits yet.
        assert!(!depositors.contains(&cap.party()), EWrongParty);
        depositors.insert(cap.party(), fee.value());

        dispute.set_status(dispute_status_draw());
    };

    event::emit(DisputeAcceptEvent {
        dispute_id: object::id(dispute),
        accepting_party: cap.party(),
        fee: fee.value(),
    });

    self.reward_pool.join(fee.into_balance());
}

/// Handles dispute ties by drawing more nivsters and starting a new round.
/// 
/// Aborts if:
/// - Dispute is not in a tie period
/// - The worker pool does not contain enough eligible jurors to extend the case
/// 
/// Emits:
/// - `DisputeTieEvent` recording the start of a tie round
entry fun handle_dispute_tie(
    court: &mut Court,
    dispute: &mut Dispute,
    clock: &Clock,
    r: &Random,
    ctx: &mut TxContext,
) {
    assert!(dispute.is_appeal_period_tie(clock), EDisputeNotTie);

    let court = court.load_inner_mut();
    let dispute_id = object::id(dispute);
    court.draw_nivsters(
        dispute.voters_mut(), 
        TIE_NIVSTER_COUNT, 
        dispute_id,
        r, 
        ctx
    );
    dispute.start_new_round_tie(clock, ctx);

    event::emit(DisputeTieEvent { 
        dispute_id, 
    });
}

/// Cancels a failed or abandoned dispute.
/// 
/// Anyone may cancel the dispute if it fails to progress to completion
/// (e.g. votes are not counted or a tie is not resolved within the allowed time
///  window).
/// 
/// Aborts if:
/// - The dispute is not in a cancellable (incomplete) state
/// 
/// Emits:
/// - `DisputeCancelEvent` recording the dispute cancellation
public fun cancel_dispute(
    dispute: &mut Dispute,
    court: &mut Court,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(dispute.is_incomplete(clock), EDisputeNotCancellable);

    let self = court.load_inner_mut();
    // Remove the case from the case map, so a new case can be opened 
    // for the contract.
    let (_, dispute_details) = self.cases
    .borrow_mut(dispute.contract())
    .remove(dispute.serialized_config());

    // Refund parties in full.
    let mut i = 0;

    while (i < dispute_details.depositors.length()) {
        let (addr, amount) = dispute_details.depositors
        .get_entry_by_idx(i);

        transfer::public_transfer(
            self.reward_pool.split(*amount).into_coin(ctx),
            *addr
        );

        i = i + 1;
    };

    dispute.set_status(dispute_status_cancelled());

    event::emit(DisputeCancelEvent { 
        dispute_id: object::id(dispute),
    });
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
/// 
/// Emits:
/// - `DisputeOneSidedCompletionEvent` recording the dispute one-sided 
///    completion
public fun resolve_one_sided_dispute(
    court: &mut Court,
    dispute: &mut Dispute,
    court_registry: &CourtRegistry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(dispute.party_failed_payment(clock), EDisputeNotOneSided);

    let court_id = object::id(court);
    let self = court.load_inner_mut();

    // The case is left to the case map intentionally, so that another case
    // can't be opened for the contract with same configurations.
    let dispute_details = self.cases.borrow(dispute.contract())
    .get(dispute.serialized_config());

    // At least 1 party has made a deposit at this point.
    let (mut refund_party, mut refund_amount) = dispute_details.depositors
    .get_entry_by_idx(0);

    // Check if the counter party has made a deposit greater than the first 
    // party.
    if (dispute_details.depositors.length() == 2) {
        let (party_2, amount_2) = dispute_details.depositors
        .get_entry_by_idx(1);

        if (*amount_2 > *refund_amount) {
            refund_party = party_2;
            refund_amount = amount_2;
        };
    };

    // Refund the party with the most deposits.
    transfer::public_transfer(
        self.reward_pool.split(*refund_amount).into_coin(ctx), 
        *refund_party
    );

    // Send the result to both parties.
    dispute.parties().do!(|party| transfer::public_transfer(create_result(
        court_id, 
        object::id(dispute), 
        dispute.contract(), 
        dispute.options(), 
        option::none(), 
        dispute.parties(), 
        dispute.parties()
        .find_index!(|addr| addr == *refund_party)
        .extract(), 
        dispute.max_appeals(), 
        ctx
    ), party));

    // If the losing party has made deposits, distribute protocol fees to the 
    // treasury. The other party has paid for 1 round less.
    if (dispute.appeals_used() >= 1) {
        let total_cut = treasury_take(
            dispute.dispute_fee(), 
            dispute.treasury_share(), 
            dispute.appeals_used() - 1,
            INIT_NIVSTER_COUNT
        );

        transfer::public_transfer(
            self.reward_pool.split(total_cut).into_coin(ctx), 
            court_registry.treasury_address()
        );
    };

    event::emit(DisputeOneSidedCompletionEvent { 
        dispute_id: object::id(dispute),
        winner_party: *refund_party,
    });

    dispute.set_status(dispute_status_completed_one_sided());
}

/// Finalizes a fully adjudicated dispute after voting and tallying have 
/// completed.
/// 
/// This function may be called once the dispute has reached a terminal state
/// and a winning option has been determined by juror voting.
/// 
/// Aborts if:
/// - The dispute has not completed voting and tallying
/// 
/// Emits:
/// - `DisputeCompleteEvent` recording the dispute completion
public fun complete_dispute(
    court: &mut Court,
    dispute: &mut Dispute,
    court_registry: &CourtRegistry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(dispute.is_completed(clock), EDisputeNotCompleted);

    let court_id = object::id(court);
    let self = court.load_inner_mut();
    let idx = dispute.winner_party().extract() as u64;
    let winner_party = dispute.parties()[idx];
    // The case is left to the case map intentionally, so that another case
    // can't be opened for the contract with same configurations.
    let deposit = self.cases.borrow(dispute.contract())
    .get(dispute.serialized_config())
    .depositors
    .get(&winner_party);

    // Refund the winner party.
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

    // Distribute protocol fees to the treasury from the other party's half.
    let total_cut = treasury_take(
        dispute.dispute_fee(), 
        dispute.treasury_share(), 
        dispute.appeals_used(),
        INIT_NIVSTER_COUNT
    );

    transfer::public_transfer(
        self.reward_pool.split(total_cut).into_coin(ctx), 
        court_registry.treasury_address()
    );

    // Distribute protocol fees to the treasury from the NVR penalties.
    let winner_option = dispute.winner_option().extract();
    let winner_count = dispute.result()[winner_option as u64];
    let mut total_votes = 0;
    dispute.result().do!(|count| total_votes = total_votes + count);
    let minority = total_votes - winner_count;
    let voters = dispute.voters();
    let (p, _) = minority_penalties_and_majority_stakes(
        voters,
        winner_option,
        dispute.sanction_model(),
        dispute.empty_vote_penalty(),
        dispute.coefficient(),
        total_votes,
        winner_count,
        minority,
    );

    let nivra_cut = p * dispute.treasury_share_nvr() / 100;

    if (nivra_cut > 0) {
        transfer::public_transfer(
            self.stake_pool.split(nivra_cut).into_coin(ctx), 
            court_registry.treasury_address()
        );
    };

    dispute.set_status(dispute_status_completed());

    event::emit(DisputeCompletionEvent { 
        dispute_id: object::id(dispute),
        winner_party,
        winner_option: 
        dispute.options()[dispute.winner_option().extract() as u64],
    });
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
    let dispute_id = object::id(dispute);

    assert!(dispute.status() == dispute_status_cancelled(), EDisputeNotCancelled);
    assert!(cap.dispute_id_voter() == dispute_id, EInvalidVoterCap);

    let self = court.load_inner_mut();
    let voter_details = dispute.voters_mut().borrow_mut(cap.voter());
    let stake = self.stakes.borrow_mut(cap.voter());

    assert!(!voter_details.reward_collected(), ERewardAlreadyCollected);

    let case_locked_amount = voter_details.stake();

    stake.locked_amount = stake.locked_amount - case_locked_amount;
    stake.amount = stake.amount + case_locked_amount;
    voter_details.set_reward_collected();

    if (stake.in_worker_pool) {
        self.worker_pool.add_stake(
            stake.worker_pool_pos, 
            case_locked_amount
        );
    };

    event::emit(BalanceUnlockedEvent {
        nivster: cap.voter(),
        amount_nvr: case_locked_amount,
        dispute_id,
    });
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
    let dispute_id = object::id(dispute);

    assert!(
        dispute.status() == dispute_status_completed_one_sided(), 
        EDisputeNotCompletedOneSided
    );
    assert!(cap.dispute_id_voter() == dispute_id, EInvalidVoterCap);

    let self = court.load_inner_mut();
    let appeals_used = dispute.appeals_used();
    let voter_details = dispute.voters().borrow(cap.voter());
    let stake = self.stakes.borrow_mut(cap.voter());

    assert!(!voter_details.reward_collected(), ERewardAlreadyCollected);

    // Distribute any sui lost by the another party to the nivsters.
    if (appeals_used >= 1) {
        let total_stake_sum = dispute.total_stake_sum();
        let total_cut = nivsters_take(
            dispute.dispute_fee(), 
            dispute.treasury_share(), 
            appeals_used - 1,
            INIT_NIVSTER_COUNT
        );

        let sui_cut = total_cut * voter_details.stake() / total_stake_sum;

        stake.reward_amount = stake.reward_amount + sui_cut;

        event::emit(BalanceRewardEvent {
            nivster: cap.voter(),
            amount_nvr: 0,
            amount_sui: sui_cut,
            dispute_id,
        });
    };

    // Unlock the users nvr stake.
    let case_locked_amount = voter_details.stake();

    stake.locked_amount = stake.locked_amount - case_locked_amount;
    stake.amount = stake.amount + case_locked_amount;

    let voter_details = dispute.voters_mut().borrow_mut(cap.voter());
    voter_details.set_reward_collected();

    if (stake.in_worker_pool) {
        self.worker_pool.add_stake(stake.worker_pool_pos, case_locked_amount);
    };

    event::emit(BalanceUnlockedEvent {
        nivster: cap.voter(),
        amount_nvr: case_locked_amount,
        dispute_id,
    });
}

/// Collects juror rewards after a dispute has been fully adjudicated.
///
/// Aborts if:
/// - Dispute is not completed
/// - Voter cap is invalid
/// - Juror already claimed
public fun collect_rewards_completed(
    court: &mut Court,
    dispute: &mut Dispute,
    cap: &VoterCap,
) {
    let dispute_id = object::id(dispute);

    assert!(
        dispute.status() == dispute_status_completed(), 
        EDisputeNotCompleted
    );
    assert!(
        cap.dispute_id_voter() == dispute_id, 
        EInvalidVoterCap
    );

    let self = court.load_inner_mut();
    let stake = self.stakes.borrow_mut(cap.voter());
    let voters = dispute.voters();
    let winner_option = dispute.winner_option().extract();
    // Voter details.
    let voter_details = voters.borrow(cap.voter());
    let user_option = voter_details.decrypted_vote();
    let staked_amount = voter_details.stake();

    assert!(!voter_details.reward_collected(), ERewardAlreadyCollected);

    // The vote was omitted.
    if (user_option.is_none()) {
        let penalty = staked_amount * dispute.empty_vote_penalty() / 100;

        // Unlock the stake - penalty.
        stake.locked_amount = stake.locked_amount - staked_amount;
        stake.amount = stake.amount + staked_amount - penalty;

        // Update the worker pool amount.
        if (stake.in_worker_pool) {
            self.worker_pool.add_stake(
                stake.worker_pool_pos, 
                staked_amount - penalty
            );
        };

        // Set status as collected.
        let voter_details = dispute.voters_mut().borrow_mut(cap.voter());
        voter_details.set_reward_collected();

        event::emit(BalanceUnlockedEvent {
            nivster: cap.voter(),
            amount_nvr: staked_amount,
            dispute_id,
        });

        event::emit(BalancePenaltyEvent {
            nivster: cap.voter(),
            amount_nvr: penalty,
            dispute_id,
        });

        return
    };

    let winner_count = dispute.result()[winner_option as u64];
    let mut total_votes = 0;
    dispute.result().do!(|count| total_votes = total_votes + count);
    let minority = total_votes - winner_count;

    // The vote falls into minority.
    if (user_option.borrow() != winner_option) {
        let penalty = penalty(
            dispute.sanction_model(),
            dispute.coefficient(), 
            staked_amount, 
            total_votes,
            winner_count,
            minority
        );

        // Unlock the stake - penalty.
        stake.locked_amount = stake.locked_amount - staked_amount;
        stake.amount = stake.amount + staked_amount - penalty;

        // Update the worker pool amount.
        if (stake.in_worker_pool) {
            self.worker_pool.add_stake(
                stake.worker_pool_pos, 
                staked_amount - penalty
            );
        };

        let voter_details = dispute.voters_mut().borrow_mut(cap.voter());
        voter_details.set_reward_collected();

        event::emit(BalanceUnlockedEvent {
            nivster: cap.voter(),
            amount_nvr: staked_amount,
            dispute_id,
        });

        event::emit(BalancePenaltyEvent {
            nivster: cap.voter(),
            amount_nvr: penalty,
            dispute_id,
        });

        return
    };

    // The vote falls into the majority.
    let (penalties, majority_stake) = minority_penalties_and_majority_stakes(
        voters, 
        winner_option, 
        dispute.sanction_model(), 
        dispute.empty_vote_penalty(), 
        dispute.coefficient(), 
        total_votes, 
        winner_count, 
        minority
    );

    let total_cut = nivsters_take(
        dispute.dispute_fee(), 
        dispute.treasury_share(), 
        dispute.appeals_used(),
        INIT_NIVSTER_COUNT
    );

    // Distribute reward based on staked amount.
    let sui_reward = total_cut * staked_amount / majority_stake;
    let nvr_reward = penalties * staked_amount * 
    (100 - dispute.treasury_share_nvr()) / (100 * majority_stake);

    stake.reward_amount = stake.reward_amount + sui_reward;
    stake.amount = stake.amount + staked_amount + nvr_reward;
    stake.locked_amount = stake.locked_amount - staked_amount;

    let voter_details = dispute.voters_mut().borrow_mut(cap.voter());
    voter_details.set_reward_collected();

    if (stake.in_worker_pool) {
        self.worker_pool.add_stake(
            stake.worker_pool_pos, 
            staked_amount + nvr_reward
        );
    };

    event::emit(BalanceUnlockedEvent {
        nivster: cap.voter(),
        amount_nvr: staked_amount,
        dispute_id,
    });

    event::emit(BalanceRewardEvent {
        nivster: cap.voter(),
        amount_nvr: nvr_reward,
        amount_sui: sui_reward,
        dispute_id,
    });
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
    default_draw_period_ms: u64,
    default_evidence_period_ms: u64,
    default_voting_period_ms: u64,
    default_appeal_period_ms: u64,
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
    threshold: u8,
    ctx: &mut TxContext,
): ID {
    court_registry.validate_admin_privileges(cap);
    assert!(treasury_share <= 100, EInvalidTreasuryShareInternal);
    assert!(treasury_share_nvr <= 100, EInvalidTreasuryShareInternal);
    assert!(empty_vote_penalty <= 100, EInvalidTreasuryShareInternal);
    assert!(sanction_model < 3, EInvalidSanctionModelInternal);
    assert!(min_stake > 0, EZeroMinStakeInternal);

    // Seal limitations.
    assert!(key_servers.length() == public_keys.length(), EInvalidKeyConfigInternal);
    assert!(threshold > 0, EInvalidThresholdInternal);
    assert!(threshold as u64 <= key_servers.length(), EInvalidThresholdInternal);

    if (sanction_model == FIXED_PERCENTAGE_MODEL) {
        assert!(coefficient < 100, EInvalidCoefficientInternal);
    };

    if (sanction_model == MINORITY_SCALED_MODEL || 
        sanction_model == QUADRATIC_MODEL) {
        assert!(coefficient <= 100, EInvalidCoefficientInternal);
    };

    let court_inner = CourtInner {
        allowed_versions: court_registry.allowed_versions(),
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
            default_draw_period_ms,
            default_evidence_period_ms,
            default_voting_period_ms,
            default_appeal_period_ms,
        },
        cases: table::new(ctx),
        stakes: linked_table::new(ctx),
        worker_pool: worker_pool::empty(ctx),
        stake_pool: balance::zero<NVR>(),
        reward_pool: balance::zero<SUI>(),
        key_servers,
        public_keys,
        threshold,
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

public fun start_operation(
    self: &mut Court, 
    cap: &NivraAdminCap, 
    court_registry: &CourtRegistry
) {
    court_registry.validate_admin_privileges(cap);

    let self = self.load_inner_mut();
    self.status = Status::Running;
}

public fun change_dispute_fee(
    self: &mut Court, 
    cap: &NivraAdminCap, 
    court_registry: &CourtRegistry,
    dispute_fee: u64
) {
    court_registry.validate_admin_privileges(cap);

    let self = self.load_inner_mut();
    self.dispute_fee = dispute_fee;
}

public fun change_timetable(
    self: &mut Court, 
    cap: &NivraAdminCap, 
    court_registry: &CourtRegistry,
    default_response_period_ms: u64,
    default_draw_period_ms: u64,
    default_evidence_period_ms: u64,
    default_voting_period_ms: u64,
    default_appeal_period_ms: u64,
) {
    court_registry.validate_admin_privileges(cap);

    let self = self.load_inner_mut();
    self.timetable.default_response_period_ms = default_response_period_ms;
    self.timetable.default_draw_period_ms = default_draw_period_ms;
    self.timetable.default_evidence_period_ms = default_evidence_period_ms;
    self.timetable.default_voting_period_ms = default_voting_period_ms;
    self.timetable.default_appeal_period_ms = default_appeal_period_ms;
}

public fun change_sanction_model(
    self: &mut Court, 
    cap: &NivraAdminCap, 
    court_registry: &CourtRegistry,
    sanction_model: u64,
    coefficient: u64,
    empty_vote_penalty: u64,
) {
    court_registry.validate_admin_privileges(cap);

    assert!(empty_vote_penalty <= 100, EInvalidSanctionModelInternal);
    assert!(sanction_model < 3, EInvalidSanctionModelInternal);

    if (sanction_model == FIXED_PERCENTAGE_MODEL) {
        assert!(coefficient < 100, EInvalidCoefficientInternal);
    };

    if (sanction_model == MINORITY_SCALED_MODEL || 
        sanction_model == QUADRATIC_MODEL) {
        assert!(coefficient <= 100, EInvalidCoefficientInternal);
    };

    let self = self.load_inner_mut();
    self.sanction_model = sanction_model;
    self.coefficient = coefficient;
    self.empty_vote_penalty = empty_vote_penalty;
}

public fun change_treasury_share(
    self: &mut Court, 
    cap: &NivraAdminCap, 
    court_registry: &CourtRegistry,
    treasury_share: u64,
    treasury_share_nvr: u64,
) {
    court_registry.validate_admin_privileges(cap);

    assert!(treasury_share <= 100, EInvalidTreasuryShareInternal);
    assert!(treasury_share_nvr <= 100, EInvalidTreasuryShareInternal);

    let self = self.load_inner_mut();
    self.treasury_share = treasury_share;
    self.treasury_share_nvr = treasury_share_nvr;
}

public fun change_key_servers(
    self: &mut Court, 
    cap: &NivraAdminCap, 
    court_registry: &CourtRegistry,
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
    threshold: u8,
) {
    court_registry.validate_admin_privileges(cap);

    assert!(
        key_servers.length() == public_keys.length(), 
        EInvalidKeyConfigInternal
    );
    assert!(threshold > 0, EInvalidThresholdInternal);
    assert!(
        threshold as u64 <= key_servers.length(), 
        EInvalidThresholdInternal
    );

    let self = self.load_inner_mut();
    self.key_servers = key_servers;
    self.public_keys = public_keys;
    self.threshold = threshold;
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
/// - Unique dynamic field accesses ≈ 4 * nivster_count + 10.
/// 
/// Aborts if:
/// - The worker pool does not contain enough eligible nivsters to satisfy
///   `nivster_count`
public(package) fun draw_nivsters(
    self: &mut CourtInner, 
    nivsters: &mut LinkedTable<address, VoterDetails>, 
    nivster_count: u64,
    dispute_id: ID,
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
        // Remove the nivster n from the worker pool to prevent duplicate selections.
        remove_from_worker_pool(self, n_addr, wp_idx);
        // Load nivster's stake.
        let nivster_stake = self.stakes.borrow_mut(n_addr);

        // Fail safe, should never throw.
        assert!(
            n_stake == nivster_stake.amount && n_stake >= self.min_stake, 
            EBalanceMismatchInternal
        );

        // Lock the minimum stake amount for a vote in the case.
        nivster_stake.amount = nivster_stake.amount - self.min_stake;
        nivster_stake.locked_amount = nivster_stake.locked_amount + self.min_stake; 

        event::emit(BalanceLockedEvent {
            nivster: n_addr,
            amount_nvr: self.min_stake,
            dispute_id,
        });

        if (nivsters.contains(n_addr)) {
            // Nivster was already chosen in a previous draw, vote count is incremented by 1.
            let nivster_details = nivsters.borrow_mut(n_addr);
            nivster_details.increment_votes();
            nivster_details.increase_stake(self.min_stake);

            event::emit(NivsterReselectionEvent { 
                dispute_id, 
                nivster: n_addr,
            });
        } else {
            nivsters.push_back(n_addr, create_voter_details(
                self.min_stake
            ));

            event::emit(NivsterSelectionEvent { 
                dispute_id, 
                nivster: n_addr, 
            });
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

/// Calculates the total reward amount R that treasury takes from the deposited 
/// fees.
/// 
/// `R(k) = F(n)[1 + (5/8) * ((13/5)^(k+1) - (13/5))] - T(k)`
///
/// where:
/// - `F(n)`: dispute fee
/// - `k`: appeal count
/// - `T(k)`: nivsters_take
public(package) fun treasury_take(
    dispute_fee: u64,
    treasury_share: u64,
    appeals: u8,
    init_nivster_count: u64,
): u64 {
    let mut r = 0;
    let mut i = 0;

    while (i <= appeals) {
        let appeal_fee = std::u128::divide_and_round_up(
            dispute_fee as u128 * std::u128::pow(13, i), 
            std::u128::pow(5, i)
        );

        r = r + (appeal_fee as u64);
        i = i + 1;
    };

    let t = nivsters_take(
        dispute_fee, 
        treasury_share, 
        appeals,
        init_nivster_count,
    );

    if(t >= r) {
        0 
    } else {
        r - t
    }
}

/// Calculates the total reward amount T that nivsters take from the deposited 
/// sui fees. Rounds up the result in favor of nivsters.
/// 
/// `T(k) = F(n)(1 - a)[(2^(k + 1) - 1) + (2^(k + 1) - k - 2) / N]`
/// 
/// where:
/// - `F(n)`: dispute fee
/// - `a`: treasury_share in percentages scaled by 100
/// - `k`: appeal count
/// - `N`: initial nivster count
public(package) fun nivsters_take(
    dispute_fee: u64,
    treasury_share: u64,
    appeals: u8,
    init_nivster_count: u64,
): u64 {
    // F(n)(1 - a) => F(n)(100 - a) / 100
    let base = std::uq64_64::from_int(dispute_fee * (100 - treasury_share))
    .div(std::uq64_64::from_int(100));
    // 2^(k + 1)
    let step = std::u64::pow(2, appeals + 1);
    // [(2^(k + 1) - 1) + (2^(k + 1) - k - 2) / N]
    let base_multiplier = std::uq64_64::from_int(step - 1)
    .add(
        std::uq64_64::from_int(step - (appeals as u64) - 2)
        .div(std::uq64_64::from_int(init_nivster_count))
    );

    let result = base.mul(base_multiplier);
    let result_int = result.to_int();

    // Round up the result if the fractional part > 0.
    if (result.gt(std::uq64_64::from_int(result_int))) {
        result_int + 1
    } else {
        result_int
    }
}

public(package) fun penalty(
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

    if (sanction_model == MINORITY_SCALED_MODEL && minority_votes > 0) {
        return staked_amount * coefficient / (minority_votes * 100)
    };

    if (sanction_model == QUADRATIC_MODEL) {
        return (
            (staked_amount as u128) * (coefficient as u128) 
            * std::u128::pow(winner_votes as u128, 2) 
            / (100 * std::u128::pow(total_votes as u128, 2))
        ) as u64
    };

    0
}

public(package) fun serialize_dispute_config(
    contract_id: ID,
    parties: vector<address>,
    options: vector<String>,
    max_appeals: u8,
): vector<u8> {
    let mut serialized: vector<u8> = vector::empty();
    let mut parties = parties;
    let mut options = options;

    let mut val_per_word: VecMap<String, u64> = vec_map::empty();

    options.do_ref!(|word| {
        let mut sum = 0;

        word.as_bytes().do_ref!(|char_val| sum = sum + (*char_val as u64));
        val_per_word.insert(*word, sum);
    });

    // Sort addresses and options, so the order doesn't matter
    parties.insertion_sort_by!(|a, b| (*a).to_u256() < (*b).to_u256());
    options.insertion_sort_by!(|a, b| {
        let a_val = val_per_word.get(a);
        let b_val = val_per_word.get(b);

        // In rare cases, if the words have the same value, then compare by
        // byte positions.
        if (*a_val == *b_val) {
            let mut bytes: &vector<u8>;
            let mut compare: &vector<u8>;

            if (a.length() > b.length()) {
                bytes = b.as_bytes();
                compare = a.as_bytes();
            } else {
                bytes = a.as_bytes();
                compare = b.as_bytes();
            };

            let mut i = 0;

            while (i < bytes.length() - 1) {
                if (bytes[i] != compare[i]) {
                    return bytes[i] < compare[i]
                };

                i = i + 1;
            };

            bytes[bytes.length() - 1] < compare[bytes.length() - 1]
        } else {
            *a_val < *b_val
        }
    });

    serialized.append(object::id_to_bytes(&contract_id));
    parties.do!(|addr| serialized.append(addr.to_bytes()));
    options.do!(|option| serialized.append(option.into_bytes()));
    serialized.push_back(max_appeals);

    serialized
}

public(package) fun minority_penalties_and_majority_stakes(
    voters: &LinkedTable<address, VoterDetails>,
    winner_option: u8,
    sanction_model: u64,
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
        let staked_amount = v.stake();

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

// === Private Functions ===

fun dispute_exists_for_contract(
    self: &CourtInner,
    contract_id: ID,
    serialized_config: &vector<u8>,
): bool {
    if (!self.cases.contains(contract_id)) {
        false
    } else {
        let case = self.cases.borrow(contract_id);

        case.contains(serialized_config)
    }
}

fun remove_from_worker_pool(
    self: &mut CourtInner,
    addr: address,
    idx: u64,
) {
    let last_pos_idx = self.worker_pool.length() - 1;

    // Update the position of the last staker in the worker pool
    if (last_pos_idx != idx) {
        let (last_pos_addr, _) = self.worker_pool.get_idx(last_pos_idx);
        let last_staker = self.stakes.borrow_mut(last_pos_addr);
        last_staker.worker_pool_pos = idx;
    };

    // Update the status and position of the removed staker.
    let removed_staker = self.stakes.borrow_mut(addr);
    removed_staker.in_worker_pool = false;
    removed_staker.worker_pool_pos = 10_001;

    // Perform the swap remove.
    self.worker_pool.swap_remove(idx);
}