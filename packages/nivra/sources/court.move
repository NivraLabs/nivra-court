module nivra::court;

use sui::versioned::{Self, Versioned};
use nivra::constants::current_version;
use nivra::court_registry::NivraAdminCap;
use std::ascii::String;
use nivra::court_registry::create_metadata;
use nivra::court_registry::CourtRegistry;
use sui::balance::{Self, Balance};
use token::nvr::NVR;
use sui::linked_table::{Self, LinkedTable};
use sui::coin::{Self, Coin};
use sui::clock::Clock;
use nivra::dispute::{create_dispute, share_dispute};
use sui::sui::SUI;
use sui::table::{Self, Table};

const EWrongVersion: u64 = 1;
const ENotUpgrade: u64 = 2;
const ENotEnoughNVR: u64 = 3;
const ENotOperational: u64 = 4;
const EInvalidFee: u64 = 5;
const EExistingDispute: u64 = 6;

public enum Status has copy, drop, store {
    Running,
    Halted,
}

public struct Stake has drop, store {
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

public fun open_dispute(
    self: &mut Court,
    fee: Coin<SUI>,
    contract: ID,
    parties: vector<address>,
    options: vector<String>,
    nivster_count: u8,
    max_appeals: u8,
    evidence_period_ms: &mut Option<u64>,
    voting_period_ms: &mut Option<u64>,
    appeal_period_ms: &mut Option<u64>,
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
    clock: &Clock, 
    ctx: &mut TxContext
) {
    let self = self.load_inner_mut();

    assert!(fee.value() == self.fee_rate * (nivster_count as u64), EInvalidFee);
    assert!(!self.cases.contains(contract), EExistingDispute);

    let voters = linked_table::new(ctx);

    let dispute = create_dispute(
        contract,
        evidence_period_ms.extract_or!(self.default_evidence_period_ms), 
        voting_period_ms.extract_or!(self.default_voting_period_ms), 
        appeal_period_ms.extract_or!(self.default_appeal_period_ms), 
        max_appeals, 
        parties, 
        voters, 
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

    share_dispute(dispute);
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

public(package) fun load_inner_mut(self: &mut Court): &mut CourtInner {
    assert!(self.inner.version() == current_version(), EWrongVersion);
    self.inner.load_value_mut()
}

public(package) fun load_inner(self: &Court): &CourtInner {
    assert!(self.inner.version() == current_version(), EWrongVersion);
    self.inner.load_value()
}