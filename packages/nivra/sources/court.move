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

const EWrongVersion: u64 = 1;
const ENotUpgrade: u64 = 2;
const ENotEnoughNVR: u64 = 3;

public struct Stake has drop, store {
    amount: u64,
    locked_amount: u64,
    multiplier: u8,
} 

public struct Court has key {
    id: UID,
    inner: Versioned,
}

public struct CourtInner has store {
    treasury_address: address,
    stake_pool: Balance<NVR>,
    stakes: LinkedTable<address, Stake>,
    fee_rate: u64,
    min_stake: u64,
}

public fun create_court(
    category: String,
    name: String,
    icon: Option<String>,
    description: String,
    skills: vector<String>,
    min_stake: u64,
    fee_rate: u64,
    court_registry: &mut CourtRegistry,
    _cap: &NivraAdminCap,
    ctx: &mut TxContext,
): ID {
    let court_inner = CourtInner {
        treasury_address: court_registry.treasury_address(),
        stake_pool: balance::zero<NVR>(),
        stakes: linked_table::new(ctx),
        fee_rate, 
        min_stake, 
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
        let amount = stake.amount;

        if (stake.locked_amount > 0) {
            self.stakes.push_back(sender, Stake {
                amount: 0,
                locked_amount: stake.locked_amount,
                multiplier: 1,
            });
        };

        coin::take(&mut self.stake_pool, amount, ctx)
    } else {
        coin::zero<NVR>(ctx)
    }
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