module nivra::constants;

const CURRENT_VERSION: u64 = 1;

const DISPUTE_STATUS_ACTIVE: u64 = 1;
const DISPUTE_STATUS_TIE: u64 = 2;
const DISPUTE_STATUS_COMPLETED: u64 = 3;
const DISPUTE_STATUS_CANCELED: u64 = 4;
const MAX_EVIDENCE_LIMIT: u64 = 3;

public fun current_version(): u64 {
    CURRENT_VERSION
}

public fun dispute_status_active(): u64 {
    DISPUTE_STATUS_ACTIVE
}

public fun dispute_status_tie(): u64 {
    DISPUTE_STATUS_TIE
}

public fun dispute_status_completed(): u64 {
    DISPUTE_STATUS_COMPLETED
}

public fun dispute_status_canceled(): u64 {
    DISPUTE_STATUS_CANCELED
}

public fun max_evidence_limit(): u64 {
    MAX_EVIDENCE_LIMIT
}