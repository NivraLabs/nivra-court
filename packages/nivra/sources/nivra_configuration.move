// © 2026 Nivra Labs Ltd.

/// Nivra dispute configuration module.
///
/// This module defines the configuration object required for integrating an
/// arbitrable smart contract with the Nivra arbitration protocol.
///
/// Contracts that wish to support dispute resolution through Nivra must:
///
/// 1. Create a `NivraConfiguration` instance.
/// 2. Store the configuration in the contract using a dynamic field where
///    the key is `nivra_key` (`std::string::String`).
/// 3. Expose a function that accepts a `NivraResult` object emitted by the
///    Nivra protocol to process the final dispute outcome.
///
/// The configuration acts as a **blueprint** used by the Nivra frontend SDK
/// when opening disputes. It defines the dispute court, allowed resolution
/// outcomes, appeal limits, and optional evidence verification metadata.
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
module nivra::nivra_configuration;

// === Imports ===
use sui::vec_map::VecMap;
use std::string::String;
use nivra::constants::max_appeals_limit;
use nivra::constants::min_option_count;
use nivra::constants::max_option_count;
use nivra::constants::max_option_len;
use nivra::constants::min_party_size;
use nivra::constants::max_party_size;

// === Errors ===
const EInvalidAppealCount: u64 = 1;
const EInvalidAlgorithm: u64 = 2;
const EInvalidOptionCount: u64 = 3;
const EOptionTooLong: u64 = 4;
const EInvalidPartySize: u64 = 5;
const EOptionEmpty: u64 = 6;

// === Constants ===
// Supported hashing algorithm identifiers.
const SHA256: u64 = 1;
const SHA512: u64 = 2;

// === Structs ===
/// Configuration object describing how disputes are created through Nivra.
///
/// This object is intended to be stored by arbitrable contracts and consumed
/// by the Nivra SDK when initiating disputes.
/// 
/// Fields:
/// 
/// - `contract_id`
/// 
///    Address of the integrating contract.
/// ---
/// - `court`
/// 
///    Address of the Nivra court contract that will adjudicate disputes.
/// ---
/// - `options`
/// 
///    Mapping of *outcome labels* to beneficiary addresses. Each key represents 
///    a dispute outcome option and maps to the address of the party that 
///    receives the dispute fee refund if that option wins.
/// 
///    Requirements:
///
///    - Must contain **2–4 options**
///    - Options must correspond to **exactly 2 unique parties**
///    - Option labels must not exceed **255 bytes**
/// 
///    Option ordering in the `VecMap` is significant:
/// 
///    The **first occurrence** of an option mapped to a given party defines the
///    party's **default resolution outcome**.
///
///    Default option is used when one party fails to deposit the required 
///    dispute fee and the other party wins the case automatically without vote.
/// ---
/// - `max_appeals`
///    
///    Maximum number of appeal rounds permitted.
/// 
///    Appeals allow parties to escalate a ruling to a larger jury pool.
///    Current protocol limit: **3 rounds**.
/// ---
/// - `file_hashes`
/// 
///    Optional list of file hashes related to the case.
/// 
///    These hashes allow the court to verify the integrity of external evidence
///    files submitted during the dispute.
/// ---
/// - `hashing_algorithm`
/// 
///    Identifier describing the hashing algorithm used to generate the hashes 
///    stored in `file_hashes`.
/// 
///    Supported algorithms:
/// 
///    `1` SHA-256 (default)
///    `2` SHA-512
public struct NivraConfiguration has copy, drop, store {
    court: address,
    options: VecMap<String, address>,
    max_appeals: u8,
    file_hashes: vector<vector<u8>>,
    hashing_algorithm: u64,
}

// === Method Aliases ===
use fun nivra::vec_map::count_unique_values as VecMap.count_unique_values;

// === Public Functions ===
/// Creates a validated `NivraConfiguration`.
///
/// This constructor performs several validation checks to ensure the
/// configuration is compatible with the Nivra protocol.
///
/// Validation Rules:
///
/// - `max_appeals` must not exceed **3**
/// - option count must be within **[2, 4]**
/// - option labels must not exceed **255 bytes**
/// - options must map to **exactly two unique parties**
public fun create(
    court: address,
    options: VecMap<String, address>,
    max_appeals: u8,
): NivraConfiguration {
    assert!(max_appeals <= max_appeals_limit(), EInvalidAppealCount);
    assert!(options.length() >= min_option_count(), EInvalidOptionCount);
    assert!(options.length() <= max_option_count(), EInvalidOptionCount);

    options
    .keys()
    .do!(|option| {
        assert!(option.length() > 0, EOptionEmpty);
        assert!(option.length() <= max_option_len() as u64, EOptionTooLong);
    });

    let party_size = options.count_unique_values!();

    assert!(party_size >= min_party_size(), EInvalidPartySize);
    assert!(party_size <= max_party_size(), EInvalidPartySize);

    NivraConfiguration {
        court, 
        options,
        max_appeals,
        file_hashes: vector[],
        hashing_algorithm: SHA256,
    }
}

/// Creates an unvalidated `NivraConfiguration`.
/// 
/// WARNING: Dispute opening is rejected for illegal Nivra configurations!
public fun create_unvalidated(
    court: address,
    options: VecMap<String, address>,
    max_appeals: u8,
    init_file_hashes: vector<vector<u8>>,
    hashing_algo: u64,
): NivraConfiguration {
    NivraConfiguration {
        court, 
        options,
        max_appeals,
        file_hashes: init_file_hashes,
        hashing_algorithm: hashing_algo,
    }
}

/// Updates the hashing algorithm.
///
/// Returns a modified configuration instance.
///
/// Supported algorithms:
///
/// - `1` → SHA-256 (default)
/// - `2` → SHA-512
public fun set_hashing_algorithm(
    mut config: NivraConfiguration,
    algorithm: u64,
): NivraConfiguration {
    assert!(algorithm >= SHA256 && algorithm <= SHA512, EInvalidAlgorithm);
    config.hashing_algorithm = algorithm;
    config
}

/// Updates the hashing algorithm.
///
/// Returns a modified configuration instance.
///
/// Supported algorithms:
///
/// - `1` → SHA-256 (default)
/// - `2` → SHA-512
public fun set_hashing_algorithm_mut(
    config: &mut NivraConfiguration,
    algorithm: u64,
) {
    assert!(algorithm >= SHA256 && algorithm <= SHA512, EInvalidAlgorithm);
    config.hashing_algorithm = algorithm;
}

/// Appends an evidence file hash to the configuration.
///
/// The hash must be produced using the currently selected hashing algorithm.
public fun add_file_hash(
    mut config: NivraConfiguration,
    hash: vector<u8>,
): NivraConfiguration {
    config.file_hashes.push_back(hash);
    config
}

/// Appends an evidence file hash to the configuration.
///
/// The hash must be produced using the currently selected hashing algorithm.
public fun add_file_hash_mut(
    config: &mut NivraConfiguration,
    hash: vector<u8>,
) {
    config.file_hashes.push_back(hash);
}

/// Removes file hash from the configuration if the hash exists.
/// 
/// Does not preserve ordering.
public fun remove_file_hash(
    mut config: NivraConfiguration,
    hash: vector<u8>,
): NivraConfiguration {
    let idx = config.file_hashes.find_index!(|ex_hash| ex_hash == hash);

    if (idx.is_some()) {
        config.file_hashes.swap_remove(idx.destroy_some());
    };

    config
}

/// Removes file hash from the configuration if the hash exists.
/// 
/// Does not preserve ordering.
public fun remove_file_hash_mut(
    config: &mut NivraConfiguration,
    hash: vector<u8>,
) {
    let idx = config.file_hashes.find_index!(|ex_hash| ex_hash == hash);
    
    if (idx.is_some()) {
        config.file_hashes.swap_remove(idx.destroy_some());
    };
}

/// Removes file hash by index or aborts if idx doesn't exists.
/// 
/// Preserves ordering.
public fun remove_file_hash_idx(
    mut config: NivraConfiguration,
    idx: u64,
): NivraConfiguration {
    config.file_hashes.remove(idx);
    config
}

/// Removes file hash by index or aborts if idx doesn't exists.
/// 
/// Preserves ordering.
public fun remove_file_hash_idx_mut(
    config: &mut NivraConfiguration,
    idx: u64,
) {
    config.file_hashes.remove(idx);
}

// === View Functions ===
public fun court(config: &NivraConfiguration): address {
    config.court
}

public fun options(config: &NivraConfiguration): VecMap<String, address> {
    config.options
}

public fun max_appeals(config: &NivraConfiguration): u8 {
    config.max_appeals
}

public fun file_hashes(config: &NivraConfiguration): vector<vector<u8>> {
    config.file_hashes
}

public fun hashing_algorithm(config: &NivraConfiguration): u64 {
    config.hashing_algorithm
}