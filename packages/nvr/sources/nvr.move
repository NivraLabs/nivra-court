module nvr::nvr;

// === Imports ===
use sui::coin_registry::CoinRegistry;
use sui::coin_registry::new_currency;
use sui::coin_registry::MetadataCap;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::Coin;
use sui::vec_map::{Self, VecMap};

// === Constants ===
// Total NVR supply.
const TGE_TOTAL_SUPPLY: u64 = 1_000_000_000_000_000;

// Supply allocations.
const TGE_COMMUNITY_RESERVE: u64 = 430_000_000_000_000;
const TGE_INITIAL_LIQUIDITY: u64 = 40_000_000_000_000;
const TGE_CORE_CONTRIBUTORS: u64 = 230_000_000_000_000;
const TGE_INITIAL_DEX_OFFERING: u64 = 30_000_000_000_000;
const TGE_PRIVATE_INVESTORS: u64 = 170_000_000_000_000;
const TGE_INCENTIVES: u64 = 100_000_000_000_000;

// Initial Contributors.
const RASMUS: address = 
    @0x2bfd4b6e634b4f72094ca68e13c64be93727d8e57c40e2c3a6cb08a989c87a4b;
const ELMERI: address = 
    @0x0eb4bdaf7b57fc5a7cdaf88c3187c4289ed5f2794e8ba87de82a05c859cebbc9;
const PATRIK: address = 
    @0xba8089644adbfa2421f6432c674df9f809cc253e8b20cd892800e81fe974bb95;
const LUKA: address = 
    @0xd852f054563382af4bd6196c6b76ee662312f0e312ef9165bf73cce75228bfac;

// Private Investors.
// Exchanges.
const NIVRA_PROTOCOL: address = 
    @0x78b21978658505237a465ef20a4cf3ce2d418fda9cfb3ce4a0e4be7f9a16187d;

// TODO: Release the initial liquidity.

const MONTH_MS: u64 = 2_629_746_000;
const YEAR_MS: u64 = 31_556_952_000;

// === Errors ===
const ETokenGenerationEventAlreadyFinalized: u64 = 1;
const ETokenGenerationEventNotFinalized: u64 = 2;
const ELaunchDateNotReached: u64 = 3;
const ENotEnoughTokensAllocated: u64 = 4;
const EUserNotContributor: u64 = 5;
const EUserNotExchange: u64 = 6;
const EUserNotInvestor: u64 = 7;

// === Structs ===
public struct NVR has key {
    id: UID,
}

public struct NivraAdminCap has key, store {
    id: UID,
}

public struct NivraWallet has key {
    id: UID,
    community_reserve: Balance<NVR>,
    initial_liquidity: Balance<NVR>,
    core_contributors: Balance<NVR>,
    initial_dex_offering: Balance<NVR>,
    private_investors: Balance<NVR>,
    incentives: Balance<NVR>,
    tge_finalized: bool,
    tge_timestamp: u64,
    contributors: VecMap<address, NivraWalletBalance>,
    investors: VecMap<address, NivraWalletBalance>,
    exchanges: VecMap<address, NivraWalletBalance>,
}

public struct NivraWalletBalance has store {
    eligible_amount: u64,
    claimed_amount: u64,
}

fun init(ctx: &mut TxContext) {
    let admin_cap = NivraAdminCap { 
        id: object::new(ctx), 
    };

    let wallet = NivraWallet {
        id: object::new(ctx),
        community_reserve: balance::zero(),
        initial_liquidity: balance::zero(),
        core_contributors: balance::zero(),
        initial_dex_offering: balance::zero(),
        private_investors: balance::zero(),
        incentives: balance::zero(),
        tge_finalized: false,
        tge_timestamp: 0,
        contributors: vec_map::from_keys_values(
            vector[
                RASMUS, 
                ELMERI, 
                PATRIK, 
                LUKA,
            ], 
            vector[
                create_balance_with_amount(61_200_000_000_000),
                create_balance_with_amount(59_400_000_000_000),
                create_balance_with_amount(27_000_000_000_000),
                create_balance_with_amount(32_400_000_000_000),
            ],
        ),
        investors: vec_map::from_keys_values(
            vector[
                NIVRA_PROTOCOL,
            ], 
            vector[
                create_balance_with_amount(TGE_PRIVATE_INVESTORS),
            ],
        ),
        exchanges: vec_map::from_keys_values(
            vector[
                NIVRA_PROTOCOL,
            ], 
            vector[
                create_balance_with_amount(TGE_INITIAL_DEX_OFFERING),
            ],
        ),
    };

    transfer::public_transfer(admin_cap, ctx.sender());
    transfer::share_object(wallet);
}

// === Public Functions ===
public fun claim_private_investors(
    wallet: &mut NivraWallet,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<NVR> {
    assert!(
        wallet.investors.contains(&ctx.sender()),
        EUserNotInvestor
    );

    let current_timestamp = clock.timestamp_ms();

    assert!(wallet.tge_finalized, ETokenGenerationEventNotFinalized);
    assert!(current_timestamp >= wallet.tge_timestamp, ELaunchDateNotReached);

    // 6-Month cliff.
    let redeem_period = wallet.tge_timestamp + 6 * MONTH_MS;

    let months_elapsed = if (current_timestamp > redeem_period) {
        (current_timestamp - redeem_period) / MONTH_MS
    } else {
        0
    };

    let user_balance = wallet.investors.get_mut(&ctx.sender());

    let amount = if (months_elapsed >= 12) {
        user_balance.eligible_amount - user_balance.claimed_amount
    } else {
        let claimable = user_balance.eligible_amount / 12 * months_elapsed;
        
        claimable - user_balance.claimed_amount
    };

    // Update the claimed amount.
    user_balance.claimed_amount = user_balance.claimed_amount + amount;
    
    wallet.private_investors.split(amount).into_coin(ctx)
}

public fun claim_initial_dex_offering(
    wallet: &mut NivraWallet,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<NVR> {
    assert!(
        wallet.exchanges.contains(&ctx.sender()),
        EUserNotExchange
    );

    let current_timestamp = clock.timestamp_ms();

    assert!(wallet.tge_finalized, ETokenGenerationEventNotFinalized);
    assert!(current_timestamp >= wallet.tge_timestamp, ELaunchDateNotReached);

    // No vesting.
    let balance = wallet.exchanges.get_mut(&ctx.sender());
    let remaining_amount = balance.eligible_amount - balance.claimed_amount;

    balance.claimed_amount = balance.claimed_amount + remaining_amount;
    wallet.initial_dex_offering.split(remaining_amount).into_coin(ctx)
}

public fun claim_core_contributors(
    wallet: &mut NivraWallet,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<NVR> {
    assert!(
        wallet.contributors.contains(&ctx.sender()),
        EUserNotContributor
    );

    let current_timestamp = clock.timestamp_ms();

    assert!(wallet.tge_finalized, ETokenGenerationEventNotFinalized);
    assert!(current_timestamp >= wallet.tge_timestamp, ELaunchDateNotReached);

    // 12-Month cliff.
    let redeem_period = wallet.tge_timestamp + YEAR_MS;

    let months_elapsed = if (current_timestamp > redeem_period) {
        (current_timestamp - redeem_period) / MONTH_MS
    } else {
        0
    };

    let user_balance = wallet.contributors.get_mut(&ctx.sender());

    let amount = if (months_elapsed >= 36) {
        user_balance.eligible_amount - user_balance.claimed_amount
    } else {
        let claimable = user_balance.eligible_amount / 36 * months_elapsed;
        
        claimable - user_balance.claimed_amount
    };

    // Update the claimed amount.
    user_balance.claimed_amount = user_balance.claimed_amount + amount;
    
    wallet.core_contributors.split(amount).into_coin(ctx)
}

// === Admin Functions ===
public fun token_generation_event(
    wallet: &mut NivraWallet,
    registry: &mut CoinRegistry,
    tge_launch_timestamp_ms: u64,
    _cap: &NivraAdminCap,
    ctx: &mut TxContext,
): MetadataCap<NVR> {
    assert!(!wallet.tge_finalized, ETokenGenerationEventAlreadyFinalized);

    let (mut currency_initializer, mut treasury_cap) = new_currency<NVR>(
        registry, 
        6, 
        b"NVR".to_string(), 
        b"Nivra".to_string(), 
        b"The native token for the Nivra arbitration protocol.".to_string(), 
        b"https://static.nivracourt.io/icon.svg".to_string(), 
        ctx,
    );

    let mut nvr_supply = treasury_cap
        .mint(TGE_TOTAL_SUPPLY, ctx)
        .into_balance();

    currency_initializer.make_supply_fixed(treasury_cap);
    let metadata_cap = currency_initializer.finalize(ctx);

    // Community reserve (43%).
    wallet.community_reserve.join(nvr_supply.split(TGE_COMMUNITY_RESERVE));
    // Initial Liquidity (4%).
    wallet.initial_liquidity.join(nvr_supply.split(TGE_INITIAL_LIQUIDITY));
    // Core Contributors (23%).
    wallet.core_contributors.join(nvr_supply.split(TGE_CORE_CONTRIBUTORS));
    // Initial Dex Offering (3%).
    wallet.initial_dex_offering.join(nvr_supply.split(TGE_INITIAL_DEX_OFFERING));
    // Private Investors (17%).
    wallet.private_investors.join(nvr_supply.split(TGE_PRIVATE_INVESTORS));
    // Incentives (10%).
    wallet.incentives.join(nvr_supply.split(TGE_INCENTIVES));

    nvr_supply.destroy_zero();

    // Finalize the token generation event.
    wallet.tge_finalized = true;
    wallet.tge_timestamp = tge_launch_timestamp_ms;

    // Return the NVR metadata cap for future updates.
    metadata_cap
}

public fun claim_community_reserve(
    wallet: &mut NivraWallet,
    _cap: &NivraAdminCap,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<NVR> {
    let current_timestamp = clock.timestamp_ms();
    
    assert!(wallet.tge_finalized, ETokenGenerationEventNotFinalized);
    assert!(current_timestamp >= wallet.tge_timestamp, ELaunchDateNotReached);

    // 15% is unlocked at the TGE.
    let init_claim: u64 = 64_500_000_000_000;

    // The rest are unlocked at 48 months of linear monthly vesting.
    let months_elapsed = (current_timestamp - wallet.tge_timestamp) / MONTH_MS;

    let amount = if (months_elapsed >= 48) { 
        TGE_COMMUNITY_RESERVE 
    } else {
        let monthly_claim = (TGE_COMMUNITY_RESERVE - init_claim) / 48;
        init_claim + months_elapsed * monthly_claim 
    };

    let amount_left = wallet.community_reserve.value();
    let amount_claimed = TGE_COMMUNITY_RESERVE - amount_left;
    let claimable_amount = amount - amount_claimed;

    wallet.community_reserve.split(claimable_amount).into_coin(ctx)
}

public fun claim_for_core_contributors(
    wallet: &mut NivraWallet,
    _cap: &NivraAdminCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let current_timestamp = clock.timestamp_ms();

    assert!(wallet.tge_finalized, ETokenGenerationEventNotFinalized);
    assert!(current_timestamp >= wallet.tge_timestamp, ELaunchDateNotReached);

    // 12-Month cliff.
    let redeem_period = wallet.tge_timestamp + YEAR_MS;

    let months_elapsed = if (current_timestamp > redeem_period) {
        (current_timestamp - redeem_period) / MONTH_MS
    } else {
        0
    };

    let mut i = 0;

    while (i < wallet.contributors.length()) {
        let (contributor, balance) = wallet.contributors.get_entry_by_idx_mut(i);

        let amount = if (months_elapsed >= 36) {
            balance.eligible_amount - balance.claimed_amount
        } else {
            let claimable = balance.eligible_amount / 36 * months_elapsed;
            
            claimable - balance.claimed_amount
        };
        
        // Update the claimed amount.
        balance.claimed_amount = balance.claimed_amount + amount;
        
        let coins = wallet.core_contributors.split(amount).into_coin(ctx);
        transfer::public_transfer(coins, *contributor);

        i = i + 1;
    };
}

public fun claim_for_initial_dex_offering(
    wallet: &mut NivraWallet,
    _cap: &NivraAdminCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let current_timestamp = clock.timestamp_ms();

    assert!(wallet.tge_finalized, ETokenGenerationEventNotFinalized);
    assert!(current_timestamp >= wallet.tge_timestamp, ELaunchDateNotReached);

    let mut i = 0;

    while (i < wallet.exchanges.length()) {
        let (exchange, balance) = wallet.exchanges.get_entry_by_idx_mut(i);
        let remaining_amount = balance.eligible_amount - balance.claimed_amount;
        
        balance.claimed_amount = balance.claimed_amount + remaining_amount;
        
        let coins = wallet.initial_dex_offering.split(remaining_amount).into_coin(ctx);
        transfer::public_transfer(coins, *exchange);

        i = i + 1;
    };
}

public fun claim_for_private_investors(
    wallet: &mut NivraWallet,
    _cap: &NivraAdminCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let current_timestamp = clock.timestamp_ms();

    assert!(wallet.tge_finalized, ETokenGenerationEventNotFinalized);
    assert!(current_timestamp >= wallet.tge_timestamp, ELaunchDateNotReached);

    // 6-Month cliff.
    let redeem_period = wallet.tge_timestamp + 6 * MONTH_MS;

    let months_elapsed = if (current_timestamp > redeem_period) {
        (current_timestamp - redeem_period) / MONTH_MS
    } else {
        0
    };

    let mut i = 0;

    while (i < wallet.investors.length()) {
        let (investor, balance) = wallet.investors.get_entry_by_idx_mut(i);

        let amount = if (months_elapsed >= 12) {
            balance.eligible_amount - balance.claimed_amount
        } else {
            let claimable = balance.eligible_amount / 12 * months_elapsed;
            
            claimable - balance.claimed_amount
        };
        
        // Update the claimed amount.
        balance.claimed_amount = balance.claimed_amount + amount;
        
        let coins = wallet.private_investors.split(amount).into_coin(ctx);
        transfer::public_transfer(coins, *investor);

        i = i + 1;
    };
}

public fun claim_incentives(
    wallet: &mut NivraWallet,
    _cap: &NivraAdminCap,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<NVR> {
    let current_timestamp = clock.timestamp_ms();

    assert!(wallet.tge_finalized, ETokenGenerationEventNotFinalized);
    assert!(current_timestamp >= wallet.tge_timestamp, ELaunchDateNotReached);

    // 20% is unlocked at the TGE.
    let init_unlock: u64 = 20_000_000_000_000;

    // 80% are linearly released over 36 months.
    let months_elapsed = (current_timestamp - wallet.tge_timestamp) / MONTH_MS;
    let amount_left = wallet.incentives.value();
    let amount_claimed = TGE_INCENTIVES - amount_left;

    let amount = if (months_elapsed >= 36) {
        TGE_INCENTIVES
    } else {
        let monthly_claim = (TGE_INCENTIVES - init_unlock) / 36;
        init_unlock + monthly_claim * months_elapsed
    };

    let claim = amount - amount_claimed;

    wallet.incentives.split(claim).into_coin(ctx)
}

public fun add_contributor(
    wallet: &mut NivraWallet,
    contributor: address,
    eligible_amount: u64,
    _cap: &NivraAdminCap,
) {
    let mut i = 0;
    let mut sum_distributed = 0;

    while (i < wallet.contributors.length()) {
        let (_, balance) = wallet.contributors.get_entry_by_idx(i);

        sum_distributed = sum_distributed + balance.eligible_amount;
        i = i + 1;
    };

    assert!(
        TGE_CORE_CONTRIBUTORS - sum_distributed >= eligible_amount,
        ENotEnoughTokensAllocated
    );

    wallet.contributors.insert(
        contributor, 
        create_balance_with_amount(eligible_amount)
    );
}

// === Package Functions ===
public(package) fun create_balance_with_amount(
    eligible_amount: u64,
): NivraWalletBalance {
    NivraWalletBalance { 
        eligible_amount, 
        claimed_amount: 0 
    }
}