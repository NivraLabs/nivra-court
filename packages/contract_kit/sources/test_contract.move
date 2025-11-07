module contract_kit::test_contract;

use std::string::String;

public struct TestContract has key, store{
    id: UID,
    description: String,
    outcomes: vector<String>,
    result: Option<u8>,
}

public fun create_test_contract(
    description: String, 
    outcomes: vector<String>, 
    ctx: &mut TxContext
): ID {
    let contract = TestContract {
        id: object::new(ctx),
        description,
        outcomes,
        result: option::none(),
    };
    let contract_id = object::id(&contract);

    transfer::share_object(contract);
    contract_id
}