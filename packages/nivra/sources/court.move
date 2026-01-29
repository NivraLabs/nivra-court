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
        current_version,
    },
    worker_pool::{WorkerPool, Self},
    dispute::{
        create_voter_details,
        create_dispute,
        VoterDetails,
        Dispute,
        PartyCap,
    },
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
const TIE_NIVSTER_COUNT: u64 = 1;
const MIN_OPTIONS: u64 = 2;
const MAX_OPTIONS: u64 = 5;
const PARTY_COUNT: u64 = 2;
const MAX_APPEALS: u8 = 3;
const MAX_DESCRIPTION_LEN: u64 = 2000;
const MAX_OPTION_LEN: u64 = 255;
const MAX_INIT_NIVSTERS: u64 = 11;
const MAX_NIVSTER_COUNT: u64 = 100;

// === Errors ===
const EWrongVersion: u64 = 1;
const EZeroDeposit: u64 = 2;
const ENotResponsePeriod: u64 = 7;
const EDisputeNotCompleted: u64 = 26;
const ENoWithdrawAmount: u64 = 28;
const EAlreadyInWorkerPool: u64 = 29;
const ENotInWorkerPool: u64 = 30;
const EDisputeNotCancellable: u64 = 34;
const EDisputeNotOneSided: u64 = 35;
const EInvalidTreasuryShareInternal: u64 = 36;
const EInvalidSanctionModelInternal: u64 = 37;
const EInvalidCoefficientInternal: u64 = 38;
const EZeroMinStakeInternal: u64 = 40;
const EInvalidThresholdInternal: u64 = 41;
const EInvalidKeyConfigInternal: u64 = 42;
const ENotDrawPeriod: u64 = 43;
const EOptionEmpty: u64 = 44;
const EDisputeAlreadyExists: u64 = 45;
const ETooManyNivsters: u64 = 46;
const ETooHighNivsterCount: u64 = 47;

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
    worker_pool_pos: Option<u64>,
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
    init_nivster_count: u64,
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
    initial_deposit: bool,
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
    unlocked_nvr: u64,
    dispute_id: ID,
}

public struct BalancePenaltyEvent has copy, drop {
    nivster: address,
    amount_nvr: u64,
    unlocked_nvr: u64,
    dispute_id: ID,
}

public struct WorkerPoolEvent has copy, drop {
    nivster: address,
    entry: bool,
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
    initiator: address,
}

public struct DisputeAcceptEvent has copy, drop {
    dispute_id: ID,
    initiator: address,
}

public struct DisputeNivstersDrawnEvent has copy, drop {
    dispute_id: ID,
    initiator: address,
}

public struct DisputeTieNivstersDrawnEvent has copy, drop {
    dispute_id: ID,
    initiator: address,
}

public struct DisputeCancelEvent has copy, drop {
    dispute_id: ID,
    initiator: address,
}

public struct DisputeOneSidedCompletionEvent has copy, drop {
    dispute_id: ID,
    initiator: address,
}

public struct DisputeCompletionEvent has copy, drop {
    dispute_id: ID,
    initiator: address,
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
public fun stake(self: &mut Court, assets: Coin<NVR>, ctx: &mut TxContext) {
    let self = self.load_inner_mut();
    let deposit_amount = assets.value();
    let sender = ctx.sender();

    assert!(self.status == Status::Running, ENotOperational);
    assert!(deposit_amount > 0, EZeroDeposit);

    if (self.stakes.contains(sender)) {
        let stake = self.stakes.borrow_mut(sender);

        // Allow top-ups as long as the resulting stake meets the min stake.
        assert!(
            stake.amount + deposit_amount >= self.min_stake, 
            EDepositUnderMinStake
        );

        stake.amount = stake.amount + deposit_amount;

        // Automatically increase the worker pool stake.
        if (stake.worker_pool_pos.is_some()) {
            self.worker_pool.add_stake(
                *stake.worker_pool_pos.borrow(), 
                deposit_amount
            );
        };

        event::emit(BalanceDepositEvent { 
            nivster: sender, 
            amount_nvr: deposit_amount,
            initial_deposit: false,
        });
    } else {
        assert!(deposit_amount >= self.min_stake, EDepositUnderMinStake);

        self.stakes.push_back(sender, Stake {
            amount: deposit_amount,
            locked_amount: 0,
            reward_amount: 0,
            worker_pool_pos: option::none(),
        });

        event::emit(BalanceDepositEvent { 
            nivster: sender, 
            amount_nvr: deposit_amount, 
            initial_deposit: true,
        });
    };

    self.stake_pool.join(assets.into_balance());
}


/// Withdraws available NVR stake and/or accumulated SUI rewards from the court.
public fun withdraw(
    self: &mut Court, 
    amount_nvr: u64,
    amount_sui: u64,
    ctx: &mut TxContext,
): (Coin<NVR>, Coin<SUI>) {
    let self = self.load_inner_mut();
    let sender = ctx.sender();
    let stake = self.stakes.borrow_mut(sender);

    assert!(stake.amount >= amount_nvr, ENotEnoughNVR);
    assert!(stake.reward_amount >= amount_sui, ENotEnoughSUI);
    assert!(amount_nvr > 0 || amount_sui > 0, ENoWithdrawAmount);

    stake.amount = stake.amount - amount_nvr;
    stake.reward_amount = stake.reward_amount - amount_sui;

    // Automatically remove or deduct from the worker pool.
    if (stake.worker_pool_pos.is_some() && amount_nvr > 0) {
        let pos = *stake.worker_pool_pos.borrow();

        if (stake.amount < self.min_stake) {
            remove_from_worker_pool(self, sender, pos);
        } else {
            self.worker_pool.sub_stake(pos, amount_nvr);
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

/// Enrolls the caller into the worker pool.
public fun join_worker_pool(self: &mut Court, ctx: &mut TxContext) {
    let self = self.load_inner_mut();
    let sender = ctx.sender();

    assert!(self.stakes.contains(sender), ENoStake);

    let stake = self.stakes.borrow_mut(sender);

    assert!(self.status == Status::Running, ENotOperational);
    assert!(stake.amount >= self.min_stake, ENotEnoughNVR);
    assert!(!stake.worker_pool_pos.is_some(), EAlreadyInWorkerPool);
    
    stake.worker_pool_pos = option::some(
        self.worker_pool.push_back(sender, stake.amount)
    );

    event::emit(WorkerPoolEvent {
        nivster: sender,
        entry: true,
    });
}

/// Removes the caller from the worker pool.
public fun leave_worker_pool(self: &mut Court, ctx: &mut TxContext) {
    let self = self.load_inner_mut();
    let sender = ctx.sender();
    let stake = self.stakes.borrow_mut(sender);

    assert!(stake.worker_pool_pos.is_some(), ENotInWorkerPool);

    remove_from_worker_pool(
        self, 
        sender, 
        *stake.worker_pool_pos.borrow()
    );

    event::emit(WorkerPoolEvent {
        nivster: sender,
        entry: false,
    });
}

/// Opens a new dispute for a given contract.
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
    assert!(parties.length() == PARTY_COUNT, EInvalidPartyCount);
    assert!(parties[0] != parties[1], EInvalidPartyCount);
    assert!(parties.contains(&ctx.sender()), EInitiatorNotParty);
    assert!(max_appeals <= MAX_APPEALS, EInvalidAppealCount);
    assert!(description.length() <= MAX_DESCRIPTION_LEN, EDescriptionTooLong);
    assert!(
        (options.length() == 0) ||
            ((options.length() >= MIN_OPTIONS) && 
                (options.length() <= MAX_OPTIONS)), 
        EInvalidOptionsAmount
    );

    options.do_ref!(|option| {
        assert!(option.length() > 0, EOptionEmpty);
        assert!(option.length() <= MAX_OPTION_LEN, EOptionTooLong);
    });

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

    // NOTE: The dispute is initialized to start at response period.
    let dispute = create_dispute(
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
        self.init_nivster_count,
        clock, 
        ctx
    );

    let mut dispute_details = DisputeDetails {
        dispute_id: object::id(&dispute),
        depositors: vec_map::empty(),
    };

    dispute_details.depositors.insert(ctx.sender(), fee.value());

    if (!self.cases.contains(contract)) {
        self.cases.add(contract, vec_map::empty());
    };

    // Insert dispute details for this config (aborts if config already exists).
    self.cases
    .borrow_mut(contract)
    .insert(serialized_config, dispute_details);

    emit_dispute_creation(&dispute);

    self.reward_pool.join(fee.into_balance());
    dispute.share_dispute(ctx);
}

/// Starts a new appeal round for an existing dispute.
public fun open_appeal(
    court: &mut Court,
    dispute: &mut Dispute,
    fee: Coin<SUI>,
    cap: &PartyCap,
    clock: &Clock,
) {
    assert!(object::id(dispute) == cap.dispute_id_party(), EInvalidPartyCap);
    assert!(dispute.parties().contains(&cap.party()), EInvalidPartyCap);
    assert!(dispute.is_appeal_period_tallied(clock), ENotAppealPeriodTallied);
    assert!(dispute.has_appeals_left(), ENoAppealsLeft);

    let self = court.load_inner_mut();
    let appeal_count = dispute.appeals_used() + 1;

    let dispute_fee = dispute_fee(dispute.dispute_fee(), appeal_count);
    assert!(fee.value() == dispute_fee, EInvalidFee);

    let case = self.cases.borrow_mut(dispute.contract());
    // NOTE: Both depositors must exist by now.
    let deposit = case.get_mut(dispute.serialized_config())
    .depositors
    .get_mut(&cap.party());
    *deposit = *deposit + fee.value();

    self.reward_pool.join(fee.into_balance());

    event::emit(DisputeAppealEvent { 
        dispute_id: object::id(dispute), 
        initiator: cap.party(),
    });

    dispute.register_payment_by_party(cap.party());
    dispute.start_response_period_appeal(clock);
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
    assert!(cap.party() != dispute.last_payment(), EWrongParty);

    let self = court.load_inner_mut();
    let appeal_count = dispute.appeals_used();

    let dispute_fee = dispute_fee(dispute.dispute_fee(), appeal_count);
    assert!(fee.value() == dispute_fee as u64, EInvalidFee);

    let case = self.cases.borrow_mut(dispute.contract());
    let depositors = &mut case
    .get_mut(dispute.serialized_config())
    .depositors;

    if (!depositors.contains(&cap.party())) {
        depositors.insert(cap.party(), fee.value());
    } else {
        let payer_balance = depositors.get_mut(&cap.party());
        *payer_balance = *payer_balance + fee.value();
    };

    event::emit(DisputeAcceptEvent {
        dispute_id: object::id(dispute),
        initiator: cap.party(),
    });

    self.reward_pool.join(fee.into_balance());

    dispute.register_payment_by_party(cap.party());
    dispute.start_draw_period(clock);
}

/// Draws nivsters for the round after both parties have accepted the case.
entry fun draw_new_nivsters(
    self: &mut Court,
    dispute: &mut Dispute,
    clock: &Clock,
    r: &Random,
    ctx: &mut TxContext,
) {
    assert!(dispute.is_draw_period(clock), ENotDrawPeriod);

    let self = self.load_inner_mut();
    let dispute_id = object::id(dispute);
    let appeal_count = dispute.appeals_used();

    // The nivster count grows by 2^(i-1) * (N + 1) on appeal rounds, where 
    // i = appeal count and N = the initial nivster count.
    let nivster_count = if (appeal_count > 0) {
        std::u64::pow(2, appeal_count - 1) * (dispute.init_nivster_count() + 1)
    } else {
        dispute.init_nivster_count()
    };

    self.draw_nivsters(
        dispute.voters_mut(), 
        nivster_count, 
        dispute_id,
        r, 
        ctx
    );

    event::emit(DisputeNivstersDrawnEvent { 
        dispute_id, 
        initiator: ctx.sender(), 
    });

    dispute.start_new_round(clock, ctx);
}

/// Handles dispute ties by drawing more nivsters and starting a new round.
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

    event::emit(DisputeTieNivstersDrawnEvent { 
        dispute_id,
        initiator: ctx.sender(), 
    });

    dispute.start_new_round_tie(clock, ctx);
}

/// Cancels a failed or abandoned dispute.
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

    // Refund parties
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

    // Refund voters
    let voters = dispute.voters();
    let dispute_id = object::id(dispute);
    let mut i = linked_table::front(voters);

    while(i.is_some()) {
        let k = *i.borrow();
        let v = voters.borrow(k);
        let stake = self.stakes.borrow_mut(k);

        stake.amount = stake.amount + v.stake();
        stake.locked_amount = stake.locked_amount - v.stake();

        if (stake.worker_pool_pos.is_some()) {
            self.worker_pool.add_stake(
                *stake.worker_pool_pos.borrow(), 
                v.stake(),
            );
        };
        
        event::emit(BalanceUnlockedEvent {
            nivster: k,
            amount_nvr: v.stake(),
            dispute_id,
        });

        i = voters.next(k);
    };

    event::emit(DisputeCancelEvent { 
        dispute_id,
        initiator: ctx.sender(),
    });

    dispute.set_status(dispute_status_cancelled());
}

/// Resolves a one-sided dispute where one party failed to pay the required
/// dispute or appeal fee within the allowed time window.
public fun resolve_one_sided_dispute(
    court: &mut Court,
    dispute: &mut Dispute,
    court_registry: &CourtRegistry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(dispute.party_failed_payment(clock), EDisputeNotOneSided);

    let self = court.load_inner_mut();

    // The case is left to the case map intentionally, so that another case
    // can't be opened for the contract with same configurations.
    let dispute_details = self.cases.borrow(dispute.contract())
        .get(dispute.serialized_config());

    let winner_party = dispute.last_payment();
    let refund_amount = dispute_details.depositors.get(&winner_party);

    // Refund the winner party.
    transfer::public_transfer(
        self.reward_pool.split(*refund_amount).into_coin(ctx), 
        winner_party
    );

    let mut nivsters_take = 0;
    let mut remaining_fees = 0;

    // Split fees paid by the other party to the nivsters and the treasury.
    if (dispute.appeals_used() >= 1) {
        let paid_rounds = dispute.appeals_used() - 1;
        
        remaining_fees = total_dispute_fee(
            dispute.dispute_fee(), 
            paid_rounds
        );

        nivsters_take = nivsters_take(
            dispute.dispute_fee(),
            dispute.treasury_share(), 
            paid_rounds, 
            dispute.init_nivster_count()
        );
    };

    let voters = dispute.voters();
    let dispute_id = object::id(dispute);
    let total_stake_sum = dispute.total_stake_sum();
    let mut i = linked_table::front(voters);

    while(i.is_some()) {
        let k = *i.borrow();
        let v = voters.borrow(k);
        let stake = self.stakes.borrow_mut(k);

        // NOTE: min_stake is always > 0.
        let reward = (nivsters_take as u128) * (v.stake() as u128) / 
            (total_stake_sum as u128);
        remaining_fees = remaining_fees - (reward as u64);

        stake.amount = stake.amount + v.stake();
        stake.locked_amount = stake.locked_amount - v.stake();
        stake.reward_amount = stake.reward_amount + (reward as u64);

        if (stake.worker_pool_pos.is_some()) {
            self.worker_pool.add_stake(
                *stake.worker_pool_pos.borrow(), 
                v.stake(),
            );
        };
        
        event::emit(BalanceRewardEvent {
            nivster: k,
            amount_nvr: 0,
            amount_sui: (reward as u64),
            unlocked_nvr: v.stake(),
            dispute_id,
        });

        i = voters.next(k);
    };

    // Protocol fee.
    transfer::public_transfer(
        self.reward_pool.split(remaining_fees).into_coin(ctx), 
        court_registry.treasury_address()
    );

    event::emit(DisputeOneSidedCompletionEvent { 
        dispute_id: object::id(dispute),
        initiator: ctx.sender(),
    });

    dispute.send_results(ctx);
    dispute.set_status(dispute_status_completed_one_sided());
}

/// Finalizes a fully adjudicated dispute after voting and tallying have 
/// completed.
public fun complete_dispute(
    court: &mut Court,
    dispute: &mut Dispute,
    court_registry: &CourtRegistry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(dispute.is_completed(clock), EDisputeNotCompleted);

    let self = court.load_inner_mut();
    let idx = *dispute.winner_party().borrow() as u64;
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

    let nivsters_take = nivsters_take(
        dispute.dispute_fee(), 
        dispute.treasury_share(), 
        dispute.appeals_used(), 
        dispute.init_nivster_count()
    );
    let (penalties, majority_sum) = pentalties_and_majority(dispute);

    let mut remaining_penalties = penalties;
    let mut remaining_fees = total_dispute_fee(
        dispute.dispute_fee(), 
        dispute.appeals_used()
    );

    let (total_votes, winner_option, winner_votes) = vote_params(dispute);
    let dispute_id = object::id(dispute);
    let party_vote = dispute.winner_option().is_none();
    let voters = dispute.voters();

    let mut i = linked_table::front(voters);

    while(i.is_some()) {
        let k = *i.borrow();
        let v = voters.borrow(k);
        let stake = self.stakes.borrow_mut(k);

        let decrypted_vote = if (party_vote) {
            v.decrypted_party_vote()
        } else {
            v.decrypted_vote()
        };

        if (decrypted_vote.is_none()) {
            let penalty = v.stake() * dispute.empty_vote_penalty() / 100;

            stake.amount = stake.amount + v.stake() - penalty;
            stake.locked_amount = stake.locked_amount - v.stake();

            if (stake.worker_pool_pos.is_some()) {
                self.worker_pool.add_stake(
                    *stake.worker_pool_pos.borrow(), 
                    v.stake() - penalty,
                );
            };

            event::emit(BalancePenaltyEvent {
                nivster: k,
                amount_nvr: penalty,
                unlocked_nvr: v.stake(),
                dispute_id,
            });
        } else {
            let vote = *decrypted_vote.borrow();

            if (vote == winner_option) {
                let sui_reward = (nivsters_take as u128) * 
                    (v.stake() as u128) / (majority_sum as u128);
                let nvr_reward = (penalties as u128) * (v.stake() as u128) * 
                    (100 - (dispute.treasury_share_nvr() as u128)) / 
                    (100 * (majority_sum as u128));
                
                remaining_fees = remaining_fees - (sui_reward as u64);
                remaining_penalties = remaining_penalties - (nvr_reward as u64);

                stake.amount = stake.amount + v.stake() + (nvr_reward as u64);
                stake.locked_amount = stake.locked_amount - v.stake();
                stake.reward_amount = stake.reward_amount + (sui_reward as u64);

                if (stake.worker_pool_pos.is_some()) {
                    self.worker_pool.add_stake(
                        *stake.worker_pool_pos.borrow(), 
                        v.stake() + nvr_reward,
                    );
                };

                event::emit(BalanceRewardEvent {
                    nivster: k,
                    amount_nvr: (nvr_reward as u64),
                    amount_sui: (sui_reward as u64),
                    unlocked_nvr: v.stake(),
                    dispute_id,
                });
            } else {
                let penalty = penalty(
                    dispute.sanction_model(), 
                    dispute.coefficient(), 
                    v.stake(), 
                    total_votes, 
                    winner_votes
                );

                stake.amount = stake.amount + v.stake() - penalty;
                stake.locked_amount = stake.locked_amount - v.stake();

                if (stake.worker_pool_pos.is_some()) {
                    self.worker_pool.add_stake(
                        *stake.worker_pool_pos.borrow(), 
                        v.stake() - penalty,
                    );
                };

                event::emit(BalancePenaltyEvent {
                    nivster: k,
                    amount_nvr: penalty,
                    unlocked_nvr: v.stake(),
                    dispute_id,
                });
            };
        };

        i = voters.next(k);
    };

    // Protocol fees.
    transfer::public_transfer(
        self.reward_pool.split(remaining_fees).into_coin(ctx), 
        court_registry.treasury_address()
    );
    transfer::public_transfer(
        self.stake_pool.split(remaining_penalties).into_coin(ctx),
        court_registry.treasury_address()
    );

    event::emit(DisputeCompletionEvent { 
        dispute_id: object::id(dispute),
        initiator: ctx.sender(),
    });

    dispute.send_results(ctx);
    dispute.set_status(dispute_status_completed());
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
    init_nivster_count: u64,
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
    assert!(init_nivster_count <= MAX_INIT_NIVSTERS, ETooHighNivsterCount);

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
        init_nivster_count,
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

public fun change_min_stake(
    self: &mut Court, 
    cap: &NivraAdminCap, 
    court_registry: &CourtRegistry,
    min_stake: u64,
) {
    court_registry.validate_admin_privileges(cap);

    assert!(min_stake > 0, EZeroMinStakeInternal);

    let self = self.load_inner_mut();
    self.min_stake = min_stake;
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
public(package) fun draw_nivsters(
    self: &mut CourtInner, 
    nivsters: &mut LinkedTable<address, VoterDetails>, 
    nivster_count: u64,
    dispute_id: ID,
    r: &Random,
    ctx: &mut TxContext,
) {
    let potential_nivsters: u64 = self.worker_pool.length();
    assert!(potential_nivsters >= nivster_count, ENotEnoughNivsters);
    assert!(
        nivsters.length() + nivster_count <= MAX_NIVSTER_COUNT, 
        ETooManyNivsters
    );

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

        event::emit(WorkerPoolEvent { 
            nivster: n_addr,
            entry: false,
        });

        // Load nivster's stake.
        let nivster_stake = self.stakes.borrow_mut(n_addr);

        // Lock the available stake amount up to court's min stake.
        let locked_amount = if (nivster_stake.amount < self.min_stake) {
            nivster_stake.amount
        } else {
            self.min_stake 
        };

        nivster_stake.amount = nivster_stake.amount - locked_amount;
        nivster_stake.locked_amount = nivster_stake.locked_amount + locked_amount; 

        event::emit(BalanceLockedEvent {
            nivster: n_addr,
            amount_nvr: locked_amount,
            dispute_id,
        });

        if (nivsters.contains(n_addr)) {
            // Nivster was already chosen in a previous draw, vote count is incremented by 1.
            let nivster_details = nivsters.borrow_mut(n_addr);
            nivster_details.increment_votes();
            nivster_details.increase_stake(locked_amount);

            event::emit(NivsterReselectionEvent { 
                dispute_id, 
                nivster: n_addr,
            });
        } else {
            nivsters.push_back(n_addr, create_voter_details(
                locked_amount
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

/// Calculates dispute fee for the give round.
public(package) fun dispute_fee(dispute_fee: u64, appeal_count: u8): u64 {
    let fee = std::u128::divide_and_round_up(
        dispute_fee as u128 * std::u128::pow(13, appeal_count), 
        std::u128::pow(5, appeal_count)
    );

    fee as u64
}

/// Calculates cumulative fee up to this round.
public(package) fun total_dispute_fee(dispute_fee: u64, appeal_count: u8): u64 {
    let mut sum = 0;
    let mut i = 0;

    while (i <= appeal_count) {
        sum = sum + dispute_fee(dispute_fee, i);
        i = i + 1;
    };

    sum
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
    let r = total_dispute_fee(dispute_fee, appeals);
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
): u64 {
    if (sanction_model == FIXED_PERCENTAGE_MODEL) {
        return staked_amount * coefficient / 100
    };

    let minority_votes = total_votes - winner_votes;

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

    parties.insertion_sort_by!(|a, b| (*a).to_u256() < (*b).to_u256());
    options.insertion_sort_by!(|a, b| {
        bytes_lt(a.as_bytes(), b.as_bytes())
    });

    // Check for duplicates after sorting to save gas.
    let mut i = 1;

    while (i < options.length()) {
        assert!(options[i - 1] != options[i], EDuplicateOptions);
        i = i + 1;
    };

    serialized.append(object::id_to_bytes(&contract_id));
    parties.do!(|addr| serialized.append(addr.to_bytes()));
    // NOTE: max options.length() = 5.
    serialized.push_back(options.length() as u8);
    // NOTE: max option.length() = 255.
    options.do!(|option| {
        serialized.push_back(option.length() as u8);
        serialized.append(option.into_bytes());
    });
    serialized.push_back(max_appeals);

    sui::hash::blake2b256(&serialized)
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
        last_staker.worker_pool_pos = option::some(idx);
    };

    // Update the status and position of the removed staker.
    let removed_staker = self.stakes.borrow_mut(addr);
    removed_staker.worker_pool_pos = option::none();

    // Perform the swap remove.
    self.worker_pool.swap_remove(idx);
}

fun emit_dispute_creation(dispute: &Dispute) {
    event::emit(DisputeCreationEvent {
        dispute_id: object::id(dispute),
        contract_id: dispute.contract(),
        court_id: dispute.court(),
        initiator: dispute.inititator(),
        max_appeals: dispute.max_appeals(),
        description: dispute.description(),
        parties: dispute.parties(),
        options: dispute.options(),
        response_period_ms: dispute.response_period_ms(),
        draw_period_ms: dispute.draw_period_ms(),
        evidence_period_ms: dispute.evidence_period_ms(),
        voting_period_ms: dispute.voting_period_ms(),
        appeal_period_ms: dispute.appeal_period_ms(),
        sanction_model: dispute.sanction_model(),
        coefficient: dispute.coefficient(),
        treasury_share: dispute.treasury_share(),
        treasury_share_nvr: dispute.treasury_share_nvr(),
        empty_vote_penalty: dispute.empty_vote_penalty(),
        dispute_fee: dispute.dispute_fee(),
        key_servers: dispute.key_servers(),
        public_keys: dispute.public_keys(),
        threshold: dispute.threshold(),
    });
}

fun bytes_lt(a: &vector<u8>, b: &vector<u8>): bool {
    let min = if (a.length() < b.length()) { a.length() } else { b.length() };
    let mut i = 0;

    while (i < min) {
        if (a[i] < b[i]) {
            return true
        };
        if (a[i] > b[i]) {
            return false
        };
        i = i + 1;
    };

    a.length() < b.length()
}

fun vote_params(dispute: &Dispute): (u64, u8, u64) {
    let party_vote = dispute.winner_option().is_none();

    if (party_vote) {
        let total_votes = dispute.total_votes_party();
        let winner_party = *dispute.winner_party().borrow();
        let winner_votes = dispute.party_result()[winner_party as u64];
        (total_votes, winner_party, winner_votes)
    } else {
        let total_votes = dispute.total_votes_option();
        let winner_option = *dispute.winner_option().borrow();
        let winner_votes = dispute.result()[winner_option as u64];
        (total_votes, winner_option, winner_votes)
    }
}

fun pentalties_and_majority(dispute: &Dispute): (u64, u64) {
    let party_vote = dispute.winner_option().is_none();
    let voters = dispute.voters();
    let mut p = 0;
    let mut s = 0;

    let (total_votes, winner_option, winner_votes) = 
        vote_params(dispute);
    
    let mut i = linked_table::front(voters);
        
    while(i.is_some()) {
        let k = *i.borrow();
        let v = voters.borrow(k);

        let decrypted_vote = if (party_vote) {
            v.decrypted_party_vote()
        } else {
            v.decrypted_vote()
        };

        if (decrypted_vote.is_none()) {
            p = p + v.stake() * dispute.empty_vote_penalty() / 100;
        } else {
            let vote = *decrypted_vote.borrow();

            if (vote == winner_option) {
                s = s + v.stake();
            } else {
                p = p + penalty(
                    dispute.sanction_model(), 
                    dispute.coefficient(), 
                    v.stake(), 
                    total_votes, 
                    winner_votes
                );
            }
        };

        i = voters.next(k);
    };

    (p, s)
}