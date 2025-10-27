// © 2025 Nivra Labs Ltd.

/// # Constants Module 
/// 
/// The `constants` module defines global constants used throughout the Nivra protocol,  
/// including version numbers, dispute statuses, and protocol limits.
module nivra::constants;


// === Constants ===
const CURRENT_VERSION: u64 = 1;
const DISPUTE_STATUS_ACTIVE: u64 = 1;
const DISPUTE_STATUS_TIE: u64 = 2;
const DISPUTE_STATUS_TALLIED: u64 = 3;
const DISPUTE_STATUS_COMPLETED: u64 = 4;
const DISPUTE_STATUS_CANCELED: u64 = 5;
const MAX_EVIDENCE_LIMIT: u64 = 3;


// === View Functions ===

/// Returns the current package version.
///
/// ### Returns
/// - The constant `CURRENT_VERSION` value.
public fun current_version(): u64 {
    CURRENT_VERSION
}

/// Returns the constant representing an **active** dispute.
///
/// ### Returns
/// - The `DISPUTE_STATUS_ACTIVE` value.
public fun dispute_status_active(): u64 {
    DISPUTE_STATUS_ACTIVE
}

/// Returns the constant representing a **tied** dispute.
///
/// ### Returns
/// - The `DISPUTE_STATUS_TIE` value.
public fun dispute_status_tie(): u64 {
    DISPUTE_STATUS_TIE
}

/// Returns the constant representing a **tallied** dispute.
///
/// ### Returns
/// - The `DISPUTE_STATUS_TALLIED` value.
public fun dispute_status_tallied(): u64 {
    DISPUTE_STATUS_TALLIED
}

/// Returns the constant representing a **completed** dispute.
///
/// ### Returns
/// - The `DISPUTE_STATUS_COMPLETED` value.
public fun dispute_status_completed(): u64 {
    DISPUTE_STATUS_COMPLETED
}

/// Returns the constant representing a **canceled** dispute.
///
/// ### Returns
/// - The `DISPUTE_STATUS_CANCELED` value.
public fun dispute_status_canceled(): u64 {
    DISPUTE_STATUS_CANCELED
}

/// Returns the maximum number of evidence submissions allowed for a dispute.
///
/// ### Returns
/// - The `MAX_EVIDENCE_LIMIT` value.
public fun max_evidence_limit(): u64 {
    MAX_EVIDENCE_LIMIT
}