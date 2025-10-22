module nivra::court;

use sui::versioned::{Self, Versioned};
use nivra::constants::current_version;
use nivra::court_registry::NivraAdminCap;
use std::ascii::String;
use nivra::court_registry::create_metadata;
use nivra::court_registry::CourtRegistry;
use nivra::dispute::VoterDetails;
use sui::balance::{Self, Balance};
use token::nvr::NVR;
use sui::linked_table::{Self, LinkedTable};
use sui::coin::{Self, Coin};
use sui::clock::Clock;
use nivra::dispute::{create_dispute, share_dispute, create_voter_details};
use sui::sui::SUI;
use sui::table::{Self, Table};
use sui::random::Random;
use sui::linked_table::borrow_mut;
use sui::random::new_generator;
use nivra::dispute::Dispute;
use nivra::constants::dispute_status_tie;
use nivra::constants::dispute_status_canceled;
use nivra::constants::dispute_status_active;
use nivra::constants::dispute_status_completed;

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
const EDisputeNotActive: u64 = 15;

public enum Status has copy, drop, store {
    Running,
    Halted,
}

public struct Stake has copy, drop, store {
    amount: u64,
    locked_amount: u64,
    multiplier: u8,
}

public struct DisputeDetails has store {
    dispute_id: ID,
    reward: Balance<SUI>,
}

public struct Court has key {
    id: UID,
    inner: Versioned,
}

public struct CourtInner has store {
    status: Status,
    cases: Table<ID, DisputeDetails>,
    treasury_address: address,
    stake_pool: Balance<NVR>,
    stakes: LinkedTable<address, Stake>,
    fee_rate: u64,
    min_stake: u64,
    default_evidence_period_ms: u64,
    default_voting_period_ms: u64,
    default_appeal_period_ms: u64,
}

public fun create_court(
    category: String,
    name: String,
    icon: Option<String>,
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
        status: Status::Running,
        cases: table::new(ctx),
        treasury_address: court_registry.treasury_address(),
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

public fun halt_operation(self: &mut Court, _cap: &NivraAdminCap) {
    let self = self.load_inner_mut();
    self.status = Status::Halted;
}

entry fun update_treasury_address(self: &mut Court, court_registry: &CourtRegistry, _cap: &NivraAdminCap) {
    let latest_treasury_address = court_registry.treasury_address();
    let self = self.load_inner_mut();
    self.treasury_address = latest_treasury_address;
}

entry fun migrate(self: &mut Court, _cap: &NivraAdminCap) {
    assert!(self.inner.version() < current_version(), ENotUpgrade);
    let (inner, cap) = self.inner.remove_value_for_upgrade<CourtInner>();
    self.inner.upgrade(current_version(), inner, cap);
}

public fun distribute_rewards(
    court: &mut Court,
    dispute: &mut Dispute,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(dispute.is_completed(clock), EDisputeNotCompleted);
    assert!(dispute.get_status() == dispute_status_active(), EDisputeNotActive);

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

        if (vote.is_none()) {
            let cut = std::u64::divide_and_round_up((v.getStake() * 30), 100);
            let stake = court.stakes.borrow_mut(k);
            stake.locked_amount = stake.locked_amount - v.getStake();
            stake.amount = stake.amount + v.getStake() - cut;
            nvr_cut = nvr_cut + cut;
        };

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
    let sui_reward = if (standard_sui_reward > std::u64::divide_and_round_up(case.reward.value(), majority_count)) {
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

    transfer::public_transfer(remaining_balance, court.treasury_address);

    dispute.set_status(dispute_status_completed());
}

#[allow(lint(public_random))]
public fun open_appeal(
    court: &mut Court,
    dispute: &mut Dispute,
    fee: Coin<SUI>,
    clock: &Clock,
    r: &Random,
    ctx: &mut TxContext,
) {
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

public fun cancel_dispute(
    court: &mut Court,
    dispute: &mut Dispute,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(dispute.get_status() == dispute_status_tie(), EDisputeNotTie);
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
            staked_amount = staked_amount + v.amount;
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
                amount_counter = amount_counter + v.amount;
            };

            if (amount_counter >= next_nivster) {
                if (nivsters.contains(k)) {
                    let nivster_details = nivsters.borrow_mut(k);
                    nivster_details.increase_stake(v.amount);
                    nivster_details.increase_multiplier();
                } else {
                    nivsters.push_back(k, create_voter_details(v.amount));
                };

                staked_amount = staked_amount - v.amount;
                v.locked_amount = v.locked_amount + v.amount;
                v.amount = 0;
                nivster_found = true;
            };

            i = self.stakes.next(k);
        };
    };
}

public(package) fun load_inner_mut(self: &mut Court): &mut CourtInner {
    assert!(self.inner.version() == current_version(), EWrongVersion);
    self.inner.load_value_mut()
}

public(package) fun load_inner(self: &Court): &CourtInner {
    assert!(self.inner.version() == current_version(), EWrongVersion);
    self.inner.load_value()
}