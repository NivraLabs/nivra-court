module nivra::constants;

const CURRENT_VERSION: u64 = 1;
const MAX_EVIDENCE_LIMIT: u64 = 3;

public fun current_version(): u64 {
    CURRENT_VERSION
}

public fun max_evidence_limit(): u64 {
    MAX_EVIDENCE_LIMIT
}