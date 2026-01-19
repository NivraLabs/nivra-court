// © 2026 Nivra Labs Ltd.

module nivra::result;

// === Imports ===

use std::string::String;

// === Structs ===

public struct Result has key, store {
    id: UID,
    court_id: ID,
    dispute_id: ID,
    contract_id: ID,
    options: vector<String>,
    winner_option: Option<u8>,
    parties: vector<address>,
    winner_party: u64,
    max_appeals: u8,
}

// === View Functions ===

public fun has_correct_config(
    result: &Result,
    court_id: ID,
    contract_id: ID,
    options: &vector<String>,
    parties: &vector<address>,
    max_appeals: u8,
): bool {
    if (court_id != result.court_id || contract_id != result.contract_id) {
        return false
    };

    if (max_appeals != result.max_appeals) {
        return false
    };

    if (options.length() != result.options.length()) {
        return false
    };

    let mut i = 0;

    while (i < options.length()) {
        if (!result.options.contains(&options[i])) {
            return false
        };

        i = i + 1;
    };

    i = 0;

    while (i < parties.length()) {
        if (!result.parties.contains(&parties[i])) {
            return false
        };

        i = i + 1;
    };

    true
}

public fun court_id(result: &Result): ID {
    result.court_id
}

public fun dispute_id(result: &Result): ID {
    result.dispute_id
}

public fun contract_id(result: &Result): ID {
    result.contract_id
}

public fun options(result: &Result): vector<String> {
    result.options
}


public fun winner_option(result: &Result): Option<String> {
    result.winner_option.map!(|opt| result.options[opt as u64])
}

public fun parties(result: &Result): vector<address> {
    result.parties
}

public fun winner_party(result: &Result): address {
    result.parties[result.winner_party]
}

public fun max_appeals(result: &Result): u8 {
    result.max_appeals
}

// === Package Functions ===

public(package) fun create_result(
    court_id: ID,
    dispute_id: ID,
    contract_id: ID,
    options: vector<String>,
    winner_option: Option<u8>,
    parties: vector<address>,
    winner_party: u64,
    max_appeals: u8,
    ctx: &mut TxContext,
): Result {
    Result {
        id: object::new(ctx),
        court_id,
        dispute_id,
        contract_id,
        options,
        winner_option,
        parties,
        winner_party,
        max_appeals,
    }
}