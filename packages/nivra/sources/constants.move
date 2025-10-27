// © 2025 Nivra Labs Ltd.

/// # Constants Module 
/// 
/// The `constants` module defines global constants used throughout the Nivra protocol.
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
public fun current_version(): u64 {
    CURRENT_VERSION
}

/// Returns the constant representing an **active** dispute.
public fun dispute_status_active(): u64 {
    DISPUTE_STATUS_ACTIVE
}

/// Returns the constant representing a **tied** dispute.
public fun dispute_status_tie(): u64 {
    DISPUTE_STATUS_TIE
}

/// Returns the constant representing a **tallied** dispute.
public fun dispute_status_tallied(): u64 {
    DISPUTE_STATUS_TALLIED
}

/// Returns the constant representing a **completed** dispute.
public fun dispute_status_completed(): u64 {
    DISPUTE_STATUS_COMPLETED
}

/// Returns the constant representing a **canceled** dispute.
public fun dispute_status_canceled(): u64 {
    DISPUTE_STATUS_CANCELED
}

/// Returns the maximum number of evidence submissions allowed for a dispute by a single submitter.
public fun max_evidence_limit(): u64 {
    MAX_EVIDENCE_LIMIT
}