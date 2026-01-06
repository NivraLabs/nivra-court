// © 2025 Nivra Labs Ltd.

module nivra::result;

// === Imports ===

use std::string::String;

// === Structs ===

public struct Result has key, store {
    id: UID,
    dispute_id: ID,
    contract_id: ID,
    options: vector<String>,
    winner_option: Option<u8>,
    parties: vector<address>,
    winner_party: Option<u8>,
    max_appeals: u8,
}

// === View Functions ===

public fun dispute_id(result: &Result): ID {
    result.dispute_id
}

public fun contract_id(result: &Result): ID {
    result.contract_id
}

public fun options(result: &Result): vector<String> {
    result.options
}

public fun winner_option(result: &Result): Option<u8> {
    result.winner_option
}

public fun parties(result: &Result): vector<address> {
    result.parties
}

public fun winner_party(result: &Result): Option<u8> {
    result.winner_party
}

public fun max_appeals(result: &Result): u8 {
    result.max_appeals
}

// === Package Functions ===

public(package) fun create_result(
    dispute_id: ID,
    contract_id: ID,
    options: vector<String>,
    winner_option: Option<u8>,
    parties: vector<address>,
    winner_party: Option<u8>,
    max_appeals: u8,
    ctx: &mut TxContext,
): Result {
    Result {
        id: object::new(ctx),
        dispute_id,
        contract_id,
        options,
        winner_option,
        parties,
        winner_party,
        max_appeals,
    }
}