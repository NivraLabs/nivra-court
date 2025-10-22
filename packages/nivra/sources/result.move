module nivra::result;

use std::ascii::String;

public struct Result has key, store {
    id: UID,
    dispute_id: ID,
    contract_id: ID,
    options: vector<String>,
    results: vector<u64>,
    winner_option: u8,
}

public(package) fun create_result(
    dispute_id: ID,
    contract_id: ID,
    options: vector<String>,
    results: vector<u64>,
    winner_option: u8,
    ctx: &mut TxContext,
): Result {
    Result {
        id: object::new(ctx),
        dispute_id,
        contract_id,
        options,
        results,
        winner_option,
    }
}