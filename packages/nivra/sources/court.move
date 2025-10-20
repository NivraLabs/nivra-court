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

const EWrongVersion: u64 = 1;
const ENotUpgrade: u64 = 2;
const ENotEnoughNVR: u64 = 3;
const ENotOperational: u64 = 4;
const EInvalidFee: u64 = 5;
const EExistingDispute: u64 = 6;
const ENotEnoughNivsters: u64 = 7;

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

entry fun open_dispute(
    self: &mut Court,
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
    r: &Random,
    clock: &Clock, 
    ctx: &mut TxContext
) {
    let self = self.load_inner_mut();

    assert!(self.status == Status::Running, ENotOperational);
    assert!(fee.value() == self.fee_rate * (nivster_count as u64), EInvalidFee);
    assert!(!self.cases.contains(contract), EExistingDispute);

    let evidence_period = *evidence_period_ms.or!(option::some(self.default_evidence_period_ms)).borrow();
    let voting_period = *voting_period_ms.or!(option::some(self.default_voting_period_ms)).borrow();
    let appeal_period = *appeal_period_ms.or!(option::some(self.default_appeal_period_ms)).borrow();
    let mut nivsters = linked_table::new(ctx);
    draw_nivsters(self, &mut nivsters, nivster_count, r, ctx);

    let dispute = create_dispute(
        contract,
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
    nivster_count: u8,
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

    assert!(potential_nivsters >= nivster_count as u64, ENotEnoughNivsters);

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