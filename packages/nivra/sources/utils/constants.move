// © 2026 Nivra Labs Ltd.

module nivra::constants;

// === Constants ===
const CURRENT_VERSION: u64 = 1;

// Registry rules.
const MAX_ADMINS: u64 = 100;
const MAX_COURTS: u64 = 1000;
const MIN_VOTE_THRESHOLD: u64 = 3;
const MIN_VOTE_DECAY_MS: u64 = 15768000000; // 6 months

// Admin vote rules.
const MAX_ADMIN_DESC_LENGTH: u64 = 2000;

// Nivster rules.
const REPUTATION_THRESHOLD: u64 = 3;

// Dispute statuses.
const DISPUTE_STATUS_RESPONSE: u64 = 1;
const DISPUTE_STATUS_DRAW: u64 = 2;
const DISPUTE_STATUS_ACTIVE: u64 = 3;
const DISPUTE_STATUS_TIE: u64 = 4;
const DISPUTE_STATUS_TALLIED: u64 = 5;
const DISPUTE_STATUS_COMPLETED: u64 = 6;
const DISPUTE_STATUS_COMPLETED_ONE_SIDED: u64 = 7;
const DISPUTE_STATUS_CANCELLED: u64 = 8;

// Dispute rules.
const MAX_APPEALS_LIMIT: u8 = 3;
const MIN_OPTION_COUNT: u64 = 2;
const MAX_OPTION_COUNT: u64 = 4;
// NOTE: Upping this value above 255 will break the dispute serialization.
const MAX_OPTION_LEN: u8 = 255;
// NOTE: Changing party size requires new dispute handling logic.
const MIN_PARTY_SIZE: u64 = 2;
const MAX_PARTY_SIZE: u64 = 2;
const MAX_DISPUTE_DESCRIPTION_LENGTH: u64 = 2000;
const MAX_EVIDENCE_PER_PARTY: u64 = 3;
const TIE_NIVSTER_COUNT: u64 = 1;

// Court rules.
const MAX_NAME_LENGTH: u64 = 255;
const MAX_CATEGORY_LENGTH: u64 = 255;
const MAX_DESCRIPTION_LENGTH: u64 = 2000;
const STATUS_ACTIVE: u8 = 0;
const STATUS_HALTED: u8 = 1;

// Evidence rules.
const MAX_EVIDENCE_DESCRIPTION_LENGTH: u64 = 2000;
const MAX_SRC: u64 = 255;
const MAX_FILE_NAME: u64 = 255;
const MAX_FILE_TYPE: u64 = 255;
const MAX_FILE_SUBTYPE: u64 = 255;

// Payment event types.
const DISPUTE_OPENING_FEE: u64 = 1;
const DISPUTE_APPEAL_FEE: u64 = 2;
const DISPUTE_REFUND: u64 = 3;


// === Public Functions ===
public fun current_version(): u64 {
    CURRENT_VERSION
}

public fun dispute_status_response(): u64 {
    DISPUTE_STATUS_RESPONSE
}

public fun dispute_status_draw(): u64 {
    DISPUTE_STATUS_DRAW
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

public fun max_appeals_limit(): u8 {
    MAX_APPEALS_LIMIT
}

public fun min_option_count(): u64 {
    MIN_OPTION_COUNT
}

public fun max_option_count(): u64 {
    MAX_OPTION_COUNT
}

public fun max_option_len(): u8 {
    MAX_OPTION_LEN
}

public fun min_party_size(): u64 {
    MIN_PARTY_SIZE
}

public fun max_party_size(): u64 {
    MAX_PARTY_SIZE
}

public fun max_name_length(): u64 {
    MAX_NAME_LENGTH
}

public fun max_category_length(): u64 {
    MAX_CATEGORY_LENGTH
}

public fun max_description_length(): u64 {
    MAX_DESCRIPTION_LENGTH
}

public fun max_dispute_description_length(): u64 {
    MAX_DISPUTE_DESCRIPTION_LENGTH
}

public fun dispute_opening_fee(): u64 {
    DISPUTE_OPENING_FEE
}

public fun dispute_appeal_fee(): u64 {
    DISPUTE_APPEAL_FEE
}

public fun dispute_refund(): u64 {
    DISPUTE_REFUND
}

public fun max_evidence_per_party(): u64 {
    MAX_EVIDENCE_PER_PARTY
}

public fun max_evidence_description_length(): u64 {
    MAX_EVIDENCE_DESCRIPTION_LENGTH
}

public fun max_src(): u64 {
    MAX_SRC
}

public fun max_file_name(): u64 {
    MAX_FILE_NAME
}

public fun max_file_type(): u64 {
    MAX_FILE_TYPE
}

public fun max_file_subtype(): u64 {
    MAX_FILE_SUBTYPE
}

public fun tie_nivster_count(): u64 {
    TIE_NIVSTER_COUNT
}

public fun status_active(): u8 {
    STATUS_ACTIVE
}

public fun status_halted(): u8 {
    STATUS_HALTED
}

public fun max_admins(): u64 {
    MAX_ADMINS
}

public fun max_courts(): u64 {
    MAX_COURTS
}

public fun max_admin_desc_length(): u64 {
    MAX_ADMIN_DESC_LENGTH
}

public fun min_vote_threshold(): u64 {
    MIN_VOTE_THRESHOLD
}

/// Time after which the founders may reset the min vote threshold to registry
/// since the last vote has passed.
public fun min_vote_decay_ms(): u64 {
    MIN_VOTE_DECAY_MS
}

/// Amount of solved cases before reputation starts counting.
public fun reputation_threshold(): u64 {
    REPUTATION_THRESHOLD
}