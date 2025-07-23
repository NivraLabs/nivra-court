module nivra_court::nivra_court;

// === Constants ===
#[allow(unused_const)]
const VERSION: u64 = 1;

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