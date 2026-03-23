// © 2026 Nivra Labs Ltd.

/// Nivra dispute result module.
/// 
/// This module defines the `NivraResult` object used to deliver the final
/// resolution of a dispute adjudicated by the Nivra arbitration protocol.
///
/// Contracts that wish to support dispute resolution through Nivra must:
///
/// 1. Create a `NivraConfiguration` instance.
/// 2. Store the configuration in the contract using a dynamic field where
///    the key is `nivra_key` (`std::string::String`).
/// 3. Expose a function that accepts a `NivraResult` object emitted by the
///    Nivra protocol to process the final dispute outcome.
/// 
/// The `NivraResult` object is provided for both parties after dispute
/// is finalized. The purpose of the object is to execute application-specific 
/// settlement logic based on the winning dispute option. 
/// **Must always be validated** before being used to enforce contract logic.
/// 
/// Helper functions `validate_result` and `validate_result_by_config` are
/// provided for this purpose.
///
/// Failure to validate the result could allow malicious actors to supply
/// forged dispute outcomes.
/// 
/// Integration flow:
///
/// ```text
/// Arbitrable Contract
///        │
///        │ stores
///        ▼
/// NivraConfiguration (dynamic field)
///        │
///        │ read by
///        ▼
/// Nivra SDK (frontend)
///        │
///        │ opens dispute
///        ▼
/// Nivra Court
///        │
///        │ returns
///        ▼
/// NivraResult → handled by arbitrable contract
/// ```
module nivra::nivra_result;

// === Imports ===
use sui::vec_map::VecMap;
use std::string::String;
use nivra::nivra_configuration::NivraConfiguration;

// === Errors ===
const EIncorrectContractID: u64 = 1;
const EInvalidCourt: u64 = 2;
const EInvalidAppealCount: u64 = 3;
const EInvalidOptions: u64 = 4;

// === Structs ===
public struct NIVRA_RESULT has drop {}

/// Object representing the finalized outcome of a Nivra dispute.
///
/// This object is produced by the Nivra court once a dispute has reached a
/// final verdict.
///
/// The object contains enough information for the receiving contract to
/// verify the authenticity and consistency of the dispute result.
/// 
/// Fields:
/// 
/// - `dispute_id`:
///    
///    Identifier of the dispute from which this result originated.
///
///    This ID allows applications and indexers to link the result back to
///    the corresponding dispute record.
/// ---
/// - `contract_id`:
/// 
///    Object ID of the arbitrable contract associated with the dispute.
/// ---
/// - `court`:
/// 
///    Address of the Nivra court contract that resolved the dispute.
///
///    Contracts should verify that this matches the configured court address.
/// ---
/// - `options`:
/// 
///    Set of dispute outcome options used during the voting process.
/// 
///    This map must match the options defined in the original 
///    `NivraConfiguration`.
/// ---
/// - `max_appeals`:
/// 
///    Maximum number of appeal rounds allowed for the dispute.
/// ---
/// - `winner_option`:
/// 
///    Label of the option that won the dispute.
///
///    The corresponding beneficiary address can be obtained using
///    `winner_party()`.
public struct NivraResult has key, store {
    id: UID,
    dispute_id: ID,
    contract_id: ID,
    court: address,
    options: VecMap<String, address>,
    max_appeals: u8,
    winner_option: String,
}

// === Method Aliases ===
use fun nivra::vec_map::eq as VecMap.eq;

// === Public Functions ===
fun init(otw: NIVRA_RESULT, ctx: &mut TxContext) {
    let publisher = sui::package::claim(otw, ctx);
    let mut result_display = 
    sui::display::new<NivraResult>(&publisher, ctx);

    result_display.add(
        b"name".to_string(),
        b"Nivra Court Result".to_string()
    );

    result_display.add(
        b"description".to_string(),
        b"Result from a dispute: {dispute_id}.".to_string()
    );

    result_display.add(
        b"link".to_string(),
        b"https://nivracourt.io/".to_string()
    );

    result_display.add(
        b"image_url".to_string(),
        b"https://static.nivracourt.io/nivra-result.svg".to_string()
    );

    result_display.update_version();

    transfer::public_transfer(publisher, ctx.sender());
    transfer::public_transfer(result_display, ctx.sender());
}

/// Validates that a `NivraResult` matches the expected dispute configuration.
///
/// This function verifies:
///
/// - contract identity
/// - court address
/// - maximum appeal configuration
/// - dispute option set
/// 
/// Aborts if result is from an incorrect dispute.
public fun validate_result(
    result: &NivraResult,
    contract_id: ID,
    court: address,
    options: VecMap<String, address>,
    max_appeals: u8,
) {
    assert!(result.contract_id == contract_id, EIncorrectContractID);
    assert!(result.court == court, EInvalidCourt);
    assert!(result.max_appeals == max_appeals, EInvalidAppealCount);
    assert!(result.options.eq!(&options), EInvalidOptions);
}

/// Validates a `NivraResult` using an existing `NivraConfiguration`.
/// 
/// Aborts if result is from an incorrect dispute.
public fun validate_result_by_config(
    result: &NivraResult,
    contract_id: ID,
    config: &NivraConfiguration,
) {
    assert!(result.contract_id == contract_id, EIncorrectContractID);
    assert!(result.court == config.court(), EInvalidCourt);
    assert!(result.max_appeals == config.max_appeals(), EInvalidAppealCount);
    assert!(result.options.eq!(&config.options()), EInvalidOptions);
}

/// Permanently destroys an obsolete `NivraResult` object.
public fun destroy_result(
    result: NivraResult
) {
    let NivraResult {
        id,
        dispute_id: _,
        contract_id: _,
        court: _,
        options: _,
        max_appeals: _,
        winner_option: _,
    } = result;

    id.delete();
}

// === View Functions ===
public fun dispute_id(result: &NivraResult): ID {
    result.dispute_id
}

public fun contract_id(result: &NivraResult): ID {
    result.contract_id
}

public fun court(result: &NivraResult): address {
    result.court
}

public fun options(result: &NivraResult): VecMap<String, address> {
    result.options
}

public fun max_appeals(result: &NivraResult): u8 {
    result.max_appeals
}

/// Validates the nivra result and returns the winner option.
/// 
/// Aborts if result is from an incorrect dispute.
public fun winner_option(
    result: &NivraResult,
    contract_id: ID,
    court: address,
    options: VecMap<String, address>,
    max_appeals: u8,
): String {
    validate_result(result, contract_id, court, options, max_appeals);
    result.winner_option
}

/// Validates the nivra result and returns the winner option.
/// 
/// Aborts if result is from an incorrect dispute.
public fun winner_option_by_config(
    result: &NivraResult,
    contract_id: ID,
    config: &NivraConfiguration,
): String {
    validate_result_by_config(result, contract_id, config);
    result.winner_option
}

/// Returns the winner option without validation.
public fun winner_option_unvalidated(result: &NivraResult): String {
    result.winner_option
}

/// Validates the nivra result and returns the winner party.
/// 
/// Aborts if result is from an incorrect dispute.
public fun winner_party(
    result: &NivraResult,
    contract_id: ID,
    court: address,
    options: VecMap<String, address>,
    max_appeals: u8,
): address {
    validate_result(result, contract_id, court, options, max_appeals);
    *result.options.get(&result.winner_option)
}

/// Validates the nivra result and returns the winner party.
/// 
/// Aborts if result is from an incorrect dispute.
public fun winner_party_by_config(
    result: &NivraResult,
    contract_id: ID,
    config: &NivraConfiguration,
): address {
    validate_result_by_config(result, contract_id, config);
    *result.options.get(&result.winner_option)
}

/// Returns the winner party without validation.
public fun winner_party_unvalidated(result: &NivraResult): address {
    *result.options.get(&result.winner_option)
}

// === Package Functions ===
public(package) fun create(
    dispute_id: ID,
    contract_id: ID,
    court: address,
    options: VecMap<String, address>,
    max_appeals: u8,
    winner_option: String,
    ctx: &mut TxContext,
): NivraResult {
    NivraResult {
        id: object::new(ctx),
        dispute_id,
        contract_id,
        court,
        options,
        max_appeals,
        winner_option,
    }
}