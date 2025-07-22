module nivra_court::nivra_court;

// === Constants ===
#[allow(unused_const)]
const VERSION: u64 = 0;

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
#[test]
fun test_module_initialization() {
    use sui::test_scenario;

    let admin_account = @0xA01;

    let mut scenario = test_scenario::begin(admin_account); 
    {
        init(scenario.ctx());
    };

    scenario.next_tx(admin_account);
    {
        let admin_cap = scenario.take_from_address<AdminCap>(admin_account);
        test_scenario::return_to_address<AdminCap>(admin_account, admin_cap);
    };

    scenario.end();
}