module nivra::court_registry;

public struct NivraAdminCap has key, store {
    id: UID,
}

fun init(ctx: &mut TxContext) {
    let admin = NivraAdminCap { 
        id: object::new(ctx) 
    };

    transfer::public_transfer(admin, ctx.sender());
}

#[test_only]
public fun get_admin_cap_for_testing(ctx: &mut TxContext): NivraAdminCap {
    NivraAdminCap { id: object::new(ctx) }
}