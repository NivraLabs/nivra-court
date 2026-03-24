// © 2026 Nivra Labs Ltd.

/// Faucet used to distribute nvr testnet tokens.
module testnet_faucet::nvr_faucet;

// === Imports ===
use sui::balance::{Self, Balance};
use nvr::nvr::NVR;
use sui::coin::Coin;
use sui::dynamic_field;
use sui::clock::Clock;

// === Errors ===
const EOutOfFunds: u64 = 1;
const EDailyQuotaReached: u64 = 2;

// === Constants ===
const DAY_MS: u64 = 86_400_000;

// === Structs ===
public struct NVRFaucetAdminCap has key, store {
    id: UID,
}

public struct NVRFaucet has key {
    id: UID,
    daily_claim_amount: u64,
    pool: Balance<NVR>,
}

public struct FaucetStatistics has drop, store {
    amount_claimed: u64,
    last_claimed: u64,
}

// === Public Functions ===
fun init(ctx: &mut TxContext) {
    let admin = NVRFaucetAdminCap { 
        id: object::new(ctx), 
    };

    let faucet = NVRFaucet {
        id: object::new(ctx),
        daily_claim_amount: 1000_000_000,
        pool: balance::zero(),
    };

    transfer::share_object(faucet);
    transfer::public_transfer(admin, ctx.sender());
}

public fun claim(
    faucet: &mut NVRFaucet,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<NVR> {
    assert!(
        faucet.pool.value() >= faucet.daily_claim_amount, 
        EOutOfFunds
    );

    if (!dynamic_field::exists_(&faucet.id, ctx.sender())) {
        dynamic_field::add(
            &mut faucet.id, 
            ctx.sender(), 
            FaucetStatistics { 
                amount_claimed: 0, 
                last_claimed: 0,
            }
        );
    };

    let user: &mut FaucetStatistics = dynamic_field::borrow_mut(
        &mut faucet.id, 
        ctx.sender()
    );
    let timestamp = clock.timestamp_ms();

    assert!(timestamp - user.last_claimed >= DAY_MS, EDailyQuotaReached);

    user.amount_claimed = user.amount_claimed + faucet.daily_claim_amount;
    user.last_claimed = timestamp;

    faucet.pool.split(faucet.daily_claim_amount).into_coin(ctx)
}

public fun load_balance(
    faucet: &mut NVRFaucet,
    assets: Coin<NVR>,
) {
    faucet.pool.join(assets.into_balance());
}

// === Admin Functions ===
public fun change_daily_claim_amount(
    faucet: &mut NVRFaucet,
    cap: &NVRFaucetAdminCap,
    daily_claim_amount: u64,
) {
    faucet.daily_claim_amount = daily_claim_amount;
}