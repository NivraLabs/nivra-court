// © 2025 Nivra Labs Ltd.

module faucet::faucet;

// === Imports ===

use sui::{
    coin::{Self, Coin},
    balance::{Self, Balance},
    table::{Self, Table},
    clock::Clock
};
use token::nvr::NVR;

// === Errors ===

const EDailyLimitReached: u64 = 1;

// === Constants ===

const DAY_MS: u64 = 86_400_000;
const COIN_DAILY_LIMIT: u64 = 1000_000_000;

// === Structs ===

public struct Faucet has key {
    id: UID,
    balance: Balance<NVR>,
    withdrawals: Table<address, u64>,
}

// === Public Functions ===

public fun withdraw(
    self: &mut Faucet,  
    clock: &Clock,
    ctx: &mut TxContext
): Coin<NVR> {
    let mut last_withdrawal_time = 0;

    if (self.withdrawals.contains(ctx.sender())) {
        last_withdrawal_time = *self.withdrawals.borrow(ctx.sender());
    } else {
        self.withdrawals.add(ctx.sender(), last_withdrawal_time);
    };

    assert!(clock.timestamp_ms() - last_withdrawal_time > DAY_MS, EDailyLimitReached);

    let v = self.withdrawals.borrow_mut(ctx.sender());
    *v = clock.timestamp_ms();

    coin::take(&mut self.balance, COIN_DAILY_LIMIT, ctx)
}

public fun load_balance(
    self: &mut Faucet,
    input: Coin<NVR>,
) {
    self.balance.join(input.into_balance());
}

// === Private Functions ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(Faucet {
        id: object::new(ctx),
        balance: balance::zero<NVR>(),
        withdrawals: table::new(ctx),
    });
}