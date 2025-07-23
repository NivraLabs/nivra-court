module nivra_court::nivra_court;

// === Constants ===
#[allow(unused_const)]
const CURRENT_VERSION: u64 = 1;

// === Structs ===
public struct AdminCap has key {
    id: UID,
}

// === Private Functions ===
fun init(ctx: &mut TxContext) {
    let admin = AdminCap {
        id: object::new(ctx),
    };

    transfer::transfer(admin, ctx.sender());
}

// === Test Functions ===
#[test_only]
public fun get_admin_cap_for_testing(ctx: &mut TxContext): AdminCap {
    AdminCap { id: object::new(ctx) }
}