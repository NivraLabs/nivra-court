// © 2026 Nivra Labs Ltd.

module nivra::constants;

// === Constants ===
const CURRENT_VERSION: u64 = 1;

const DISPUTE_STATUS_RESPONSE: u64 = 1;
const DISPUTE_STATUS_ACTIVE: u64 = 2;
const DISPUTE_STATUS_TIE: u64 = 3;
const DISPUTE_STATUS_TALLIED: u64 = 4;
const DISPUTE_STATUS_COMPLETED: u64 = 5;
const DISPUTE_STATUS_COMPLETED_ONE_SIDED: u64 = 6;
const DISPUTE_STATUS_CANCELLED: u64 = 7;

// === Public Functions ===
public fun current_version(): u64 {
    CURRENT_VERSION
}

public fun dispute_status_response(): u64 {
    DISPUTE_STATUS_RESPONSE
}

public fun dispute_status_active(): u64 {
    DISPUTE_STATUS_ACTIVE
}

public fun dispute_status_tie(): u64 {
    DISPUTE_STATUS_TIE
}

public fun dispute_status_tallied(): u64 {
    DISPUTE_STATUS_TALLIED
}

public fun dispute_status_completed(): u64 {
    DISPUTE_STATUS_COMPLETED
}

public fun dispute_status_completed_one_sided(): u64 {
    DISPUTE_STATUS_COMPLETED_ONE_SIDED
}

public fun dispute_status_cancelled(): u64 {
    DISPUTE_STATUS_CANCELLED
}