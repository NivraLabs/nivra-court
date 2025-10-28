// © 2025 Nivra Labs Ltd.

/// # Court Module
///
/// The `court` module defines and manages individual courts within the Nivra protocol.
/// Courts handle staking, dispute creation, reward distribution, and appeals.
/// 
/// Each court maintains its own stake pool, disputes, and operational settings.
module nivra::court;

// === Imports ===

use nivra::{
    court_registry::{
        CourtRegistry,
        create_metadata,
        NivraAdminCap,
    },
    constants::{
        current_version, 
        dispute_status_active, 
        dispute_status_tie,
        dispute_status_tallied,
        dispute_status_canceled, 
        dispute_status_completed,
    },
    dispute::{
        Dispute,
        VoterDetails,
        PartyCap,
        create_dispute, 
        share_dispute, 
        create_voter_details,
    },
    result::create_result,
};
use std::string::String;
use sui::{
    versioned::{Self, Versioned},
    balance::{Self, Balance},
    coin::{Self, Coin},
    linked_table::{Self, LinkedTable},
    table::{Self, Table},
    random::{Random, new_generator},
    clock::Clock,
    sui::SUI,
    linked_table::borrow_mut,
};
use token::nvr::NVR;

// === Constants ===

const EWrongVersion: u64 = 1;
const ENotUpgrade: u64 = 2;
const ENotEnoughNVR: u64 = 3;
const ENotOperational: u64 = 4;
const EInvalidFee: u64 = 5;
const EExistingDispute: u64 = 6;
const ENotEnoughNivsters: u64 = 7;
const ENoNivsters: u64 = 8;
const EDisputeNotTie: u64 = 9;
const EDisputeNotCompleted: u64 = 10;
const EDisputeCompleted: u64 = 11;
const ENotEnoughOptions: u64 = 12;
const ENotAppealPeriod: u64 = 13;
const ENoAppealsLeft: u64 = 14;
const EDisputeNotTallied: u64 = 15;
const EDisputeNotError: u64 = 16;
const ENotPartyMember: u64 = 17;

// === Structs ===

/// ## `Status`
///
/// Operational status of the court.
///
/// - `Running`: Court is active and can accept new disputes and stakes.
/// - `Halted`: Court is paused by admin and operations are disabled.
public enum Status has copy, drop, store {
    Running,
    Halted,
}

/// ## `Stake`
///
/// Represents a staker's balance within a court.
///
/// ### Fields
/// - `amount`: Available stake.
/// - `locked_amount`: Currently locked stake in disputes.
/// - `multiplier`: Multiplier applied to amount when nivsters are drawn.
public struct Stake has copy, drop, store {
    amount: u64,
    locked_amount: u64,
    multiplier: u8,
}

/// ## `DisputeDetails`
///
/// Internal record storing reference to a dispute and its reward pool.
public struct DisputeDetails has store {
    dispute_id: ID,
    reward: Balance<SUI>,
}

public struct Court has key {
    id: UID,
    inner: Versioned,
}

/// ## `CourtInner`
/// 
/// ### Fields
/// - `status`: Court operational status.
/// - `cases`: Table of disputes associated with this court.
/// - `stake_pool`: Pool of staked NVR tokens.
/// - `stakes`: Linked table mapping addresses to their `Stake`.
/// - `fee_rate`: Dispute fee rate per nivster.
/// - `min_stake`: Minimum stake requirement.
/// - `default_*_period_ms`: Default durations for evidence, voting, and appeals.
public struct CourtInner has store {
    ai_court: bool,
    status: Status,
    cases: Table<ID, DisputeDetails>,
    stake_pool: Balance<NVR>,
    stakes: LinkedTable<address, Stake>,
    fee_rate: u64,
    min_stake: u64,
    default_evidence_period_ms: u64,
    default_voting_period_ms: u64,
    default_appeal_period_ms: u64,
}

// === Public Functions ===

/// Stake NVR tokens in a court.
/// (Regular stake option with multiplier = 1)
public fun stake(self: &mut Court, assets: Coin<NVR>, ctx: &mut TxContext) {
    let self = self.load_inner_mut();
    let amount = assets.value();
    assert!(amount >= self.min_stake, ENotEnoughNVR);
    assert!(self.status == Status::Running, ENotOperational);

    coin::put(&mut self.stake_pool, assets);
    let sender = ctx.sender();

    if (self.stakes.contains(sender)) {
        let stake = self.stakes.borrow_mut(sender);
        stake.amount = stake.amount + amount;
    } else {
        self.stakes.push_back(sender, Stake {
            amount,
            locked_amount: 0,
            multiplier: 1,
        });
    };
}

/// Withdraw available stake amount.
public fun withdraw(self: &mut Court, ctx: &mut TxContext): Coin<NVR> {
    let self = self.load_inner_mut();
    let sender = ctx.sender();
    
    if (self.stakes.contains(sender)) {
        let stake = self.stakes.remove(sender);

        if (stake.locked_amount > 0) {
            self.stakes.push_back(sender, Stake {
                amount: 0,
                locked_amount: stake.locked_amount,
                multiplier: stake.multiplier,
            });
        };

        coin::take(&mut self.stake_pool, stake.amount, ctx)
    } else {
        coin::zero<NVR>(ctx)
    }
}

/// Distribute rewards to jurors after a dispute has been tallied and is in reward period.
public fun distribute_rewards(
    court: &mut Court,
    dispute: &mut Dispute,
    registry: &CourtRegistry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(dispute.is_completed(clock), EDisputeNotCompleted);
    assert!(dispute.get_status() == dispute_status_tallied(), EDisputeNotTallied);

    let court = court.load_inner_mut();
    let winner_option = dispute.get_winner_option().destroy_some();
    let voters = dispute.get_voters();

    let majority_count = dispute.get_results()[winner_option as u64];
    let mut nvr_cut = 0;
    let mut i = linked_table::front(voters);

    while(i.is_some()) {
        let k = *i.borrow();
        let v = voters.borrow(k);
        let vote = v.get_decrypted_vote();

        // Omitting vote results in 30% penalty.
        if (vote.is_none()) {
            let cut = std::u64::divide_and_round_up((v.getStake() * 30), 100);
            let stake = court.stakes.borrow_mut(k);
            stake.locked_amount = stake.locked_amount - v.getStake();
            stake.amount = stake.amount + v.getStake() - cut;
            nvr_cut = nvr_cut + cut;
        };

        // Minority vote results in 25% penalty.
        if (vote.is_some() && *vote.borrow() != winner_option) {
            let cut = std::u64::divide_and_round_up((v.getStake() * 25), 100);
            let stake = court.stakes.borrow_mut(k);
            stake.locked_amount = stake.locked_amount - v.getStake();
            stake.amount = stake.amount + v.getStake() - cut;
            nvr_cut = nvr_cut + cut;
        };

        i = voters.next(k);
    };

    let nvr_reward = std::uq64_64::from_int(nvr_cut)
        .div(std::uq64_64::from_int(majority_count))
        .to_int();
    let standard_sui_reward = std::u64::divide_and_round_up((court.fee_rate * 99), 100);
    let mut case = court.cases.remove(dispute.get_contract_id());
    let sui_reward = if (standard_sui_reward < std::u64::divide_and_round_up(case.reward.value(), majority_count)) {
        standard_sui_reward
    } else {
        std::uq64_64::from_int(case.reward.value())
        .div(std::uq64_64::from_int(majority_count))
        .to_int()
    };
    i = linked_table::front(voters);

    while(i.is_some()) {
        let k = *i.borrow();
        let v = voters.borrow(k);
        let vote = v.get_decrypted_vote();

        if (vote.is_some() && *vote.borrow() == winner_option) {
            let stake = court.stakes.borrow_mut(k);
            stake.locked_amount = stake.locked_amount - v.getStake();
            stake.amount = stake.amount + v.getStake() + (nvr_reward * v.get_multiplier());

            let coin = case.reward.split(sui_reward * v.get_multiplier()).into_coin(ctx);
            transfer::public_transfer(coin, k);
        };

        i = voters.next(k);
    };

    let DisputeDetails { 
        dispute_id: _, 
        mut reward, 
    } = case;

    let remaining_balance = reward.withdraw_all().into_coin(ctx);
    reward.destroy_zero();

    transfer::public_transfer(remaining_balance, registry.treasury_address());

    dispute.get_parties().do_ref!(|party| {
        transfer::public_transfer(create_result(
            object::id(dispute), 
            dispute.get_contract_id(), 
            dispute.get_options(), 
            dispute.get_results(), 
            winner_option, 
            ctx
        ), *party)
    });

    dispute.set_status(dispute_status_completed());
}

/// Open an appeal for a tallied dispute in appeal period.
#[allow(lint(public_random))]
public fun open_appeal(
    court: &mut Court,
    dispute: &mut Dispute,
    fee: Coin<SUI>,
    cap: &PartyCap,
    clock: &Clock,
    r: &Random,
    ctx: &mut TxContext,
) {
    assert!(dispute.is_party_member(cap), ENotPartyMember);
    assert!(dispute.get_status() == dispute_status_tallied(), EDisputeNotTallied);
    assert!(dispute.has_appeals_left(), ENoAppealsLeft);
    assert!(dispute.is_appeal_period(clock), ENotAppealPeriod);

    let court = court.load_inner_mut();
    let nivster_count = dispute.get_nivster_count();

    assert!(fee.value() == court.fee_rate * nivster_count, EInvalidFee);

    let case = court.cases.borrow_mut(dispute.get_contract_id());
    case.reward.join(fee.into_balance());

    court.draw_nivsters(dispute.get_voters_mut(), nivster_count, r, ctx);
    dispute.increase_appeals();
    dispute.start_new_round(clock, ctx);
}

/// Handle a tied dispute by assigning an additional juror.
#[allow(lint(public_random))]
public fun handle_dispute_tie(
    court: &mut Court,
    dispute: &mut Dispute,
    clock: &Clock,
    r: &Random,
    ctx: &mut TxContext,
) {
    assert!(dispute.get_status() == dispute_status_tie(), EDisputeNotTie);
    assert!(!dispute.is_completed(clock), EDisputeCompleted);

    let court = court.load_inner_mut();
    court.draw_nivsters(dispute.get_voters_mut(), 1, r, ctx);
    dispute.start_new_round(clock, ctx);
}

/// Cancel an active or tied dispute without result and refund participants.
public fun cancel_dispute(
    court: &mut Court,
    dispute: &mut Dispute,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(dispute.get_status() == dispute_status_tie() || dispute.get_status() == dispute_status_active(), EDisputeNotError);
    assert!(dispute.is_completed(clock), EDisputeNotCompleted);
    dispute.set_status(dispute_status_canceled());

    let court = court.load_inner_mut();
    let mut case = court.cases.remove(dispute.get_contract_id());

    let coin = case.reward.withdraw_all().into_coin(ctx);
    transfer::public_transfer(coin, dispute.get_initiator());

    let DisputeDetails { 
        dispute_id: _, 
        reward,
    } = case;
    reward.destroy_zero();

    let voters = dispute.get_voters();
    let mut i = linked_table::front(voters);

    while(i.is_some()) {
        let k = *i.borrow();
        let v = voters.borrow(k);
        let stake = court.stakes.borrow_mut(k);

        stake.locked_amount = stake.locked_amount - v.getStake();
        stake.amount = stake.amount + v.getStake();

        i = voters.next(k);
    };
}

/// Open a new dispute in the court.
///
/// ### Parameters
/// - `court`: Mutable reference to the `Court`.
/// - `fee`: SUI fee = nivster count * court fee rate.
/// - `contract`: Associated contract ID.
/// - `description`: Dispute description.
/// - `parties`: List of involved addresses.
/// - `options`: Voting options.
/// - `nivster_count`: Number of jurors.
/// - `max_appeals`: Maximum appeals.
/// - `evidence_period_ms`: Optional custom evidence duration.
/// - `voting_period_ms`: Optional custom voting duration.
/// - `appeal_period_ms`: Optional custom appeal duration.
/// - `key_servers`: Public key servers.
/// - `public_keys`: Juror public keys.
/// - `threshold`: Encryption key servers threshold.
/// - `r`: Randomness source.
/// - `clock`: Global clock.
#[allow(lint(public_random))]
public fun open_dispute(
    court: &mut Court,
    fee: Coin<SUI>,
    contract: ID,
    description: String,
    parties: vector<address>,
    options: vector<String>,
    nivster_count: u8,
    max_appeals: u8,
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
    assert!(fee.value() == self.fee_rate * (nivster_count as u64), EInvalidFee);
    assert!(!self.cases.contains(contract), EExistingDispute);
    assert!(nivster_count > 0, ENoNivsters);
    assert!(options.length() >= 2, ENotEnoughOptions);

    let evidence_period = *evidence_period_ms.or!(option::some(self.default_evidence_period_ms)).borrow();
    let voting_period = *voting_period_ms.or!(option::some(self.default_voting_period_ms)).borrow();
    let appeal_period = *appeal_period_ms.or!(option::some(self.default_appeal_period_ms)).borrow();
    let mut nivsters = linked_table::new(ctx);
    draw_nivsters(self, &mut nivsters, nivster_count as u64, r, ctx);

    let dispute = create_dispute(
        ctx.sender(),
        contract,
        court_id,
        description,
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

    self.cases.add(contract, DisputeDetails { 
        dispute_id: object::id(&dispute), 
        reward: fee.into_balance(),
    });

    share_dispute(dispute, ctx);
}

// === Admin Functions ===

/// Creates and registers a new court.
///
/// ### Parameters
/// - `category`: Court category name.
/// - `name`: Human-readable name of the court.
/// - `icon`: Optional icon URL.
/// - `description`: Court description.
/// - `skills`: List of required skills.
/// - `min_stake`: Minimum stake in NVR.
/// - `fee_rate`: Dispute fee rate per nivster.
/// - `default_evidence_period_ms`: Default evidence period (milliseconds).
/// - `default_voting_period_ms`: Default voting period (milliseconds).
/// - `default_appeal_period_ms`: Default appeal period (milliseconds).
/// - `court_registry`: Court registry.
/// - `_cap`: Nivra admin capability.
///
/// ### Returns
/// - The `ID` of the newly created court.
///
/// ### Aborts
/// - If registration in registry fails.
public fun create_court(
    ai_court: bool,
    category: String,
    name: String,
    icon: Option<std::ascii::String>,
    description: String,
    skills: vector<String>,
    min_stake: u64,
    fee_rate: u64,
    default_evidence_period_ms: u64,
    default_voting_period_ms: u64,
    default_appeal_period_ms: u64,
    court_registry: &mut CourtRegistry,
    _cap: &NivraAdminCap,
    ctx: &mut TxContext,
): ID {
    let court_inner = CourtInner {
        ai_court,
        status: Status::Running,
        cases: table::new(ctx),
        stake_pool: balance::zero<NVR>(),
        stakes: linked_table::new(ctx),
        fee_rate, 
        min_stake,
        default_evidence_period_ms,
        default_voting_period_ms,
        default_appeal_period_ms,
    };

    let court = Court { 
        id: object::new(ctx), 
        inner: versioned::create(
            current_version(), 
            court_inner, 
            ctx
        )
    };

    let court_id = object::id(&court);
    let metadata = create_metadata(
        category, 
        name, 
        icon, 
        description, 
        skills, 
        min_stake, 
        std::u64::divide_and_round_up((fee_rate * 99), 100),
    );

    court_registry.register_court(court_id, metadata);
    transfer::share_object(court);

    court_id
}

/// Halt court operations.
public fun halt_operation(self: &mut Court, _cap: &NivraAdminCap) {
    let self = self.load_inner_mut();
    self.status = Status::Halted;
}

/// Migrate the court to the latest package version.
entry fun migrate(self: &mut Court, _cap: &NivraAdminCap) {
    assert!(self.inner.version() < current_version(), ENotUpgrade);
    let (inner, cap) = self.inner.remove_value_for_upgrade<CourtInner>();
    self.inner.upgrade(current_version(), inner, cap);
}

// === Package Functions ===

/// Randomly selects nivsters from the stake pool based on their stake amounts.
public(package) fun draw_nivsters(
    self: &mut CourtInner, 
    nivsters: &mut LinkedTable<address, VoterDetails>, 
    nivster_count: u64,
    r: &Random,
    ctx: &mut TxContext,
) {
    let mut potential_nivsters: u64 = 0;
    let mut staked_amount: u64 = 0;
    let mut i = linked_table::front(&self.stakes);

    while (i.is_some()) {
        let k = *i.borrow();
        let v = self.stakes.borrow(k);

        if (v.amount >= self.min_stake) {
            potential_nivsters = potential_nivsters + 1;
            staked_amount = staked_amount + v.amount * (v.multiplier as u64);
        };

        i = self.stakes.next(k);
    };

    assert!(potential_nivsters >= nivster_count, ENotEnoughNivsters);

    let mut j = 0;
    let mut generator = new_generator(r, ctx);

    loop {
        if (j >= nivster_count) {
            break
        };

        let mut amount_counter = 0;
        let mut nivster_found = false;
        let next_nivster = generator.generate_u64_in_range(0, staked_amount);
        i = linked_table::front(&self.stakes);
        j = j + 1;

        while (i.is_some() && !nivster_found) {
            let k = *i.borrow();
            let v = self.stakes.borrow_mut(k);

            if (v.amount >= self.min_stake) {
                amount_counter = amount_counter + v.amount * (v.multiplier as u64);
            };

            if (amount_counter >= next_nivster) {
                if (nivsters.contains(k)) {
                    let nivster_details = nivsters.borrow_mut(k);
                    nivster_details.increase_stake(v.amount);
                    nivster_details.increase_multiplier();
                } else {
                    nivsters.push_back(k, create_voter_details(v.amount));
                };

                staked_amount = staked_amount - v.amount * (v.multiplier as u64);
                v.locked_amount = v.locked_amount + v.amount;
                v.amount = 0;
                nivster_found = true;
            };

            i = self.stakes.next(k);
        };
    };
}

/// Loads mutable reference to the inner court data.
public(package) fun load_inner_mut(self: &mut Court): &mut CourtInner {
    assert!(self.inner.version() == current_version(), EWrongVersion);
    self.inner.load_value_mut()
}

/// Loads immutable reference to the inner court data.
public(package) fun load_inner(self: &Court): &CourtInner {
    assert!(self.inner.version() == current_version(), EWrongVersion);
    self.inner.load_value()
}