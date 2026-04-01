// Dispute statuses.
pub const DISPUTE_STATUS_RESPONSE: i16 = 1;
pub const DISPUTE_STATUS_DRAW: i16 = 2;
pub const DISPUTE_STATUS_ACTIVE: i16 = 3;
pub const DISPUTE_STATUS_TIE: i16 = 4;
pub const DISPUTE_STATUS_TALLIED: i16 = 5;
pub const DISPUTE_STATUS_COMPLETED: i16 = 6;
pub const DISPUTE_STATUS_COMPLETED_ONE_SIDED: i16 = 7;
pub const DISPUTE_STATUS_CANCELLED: i16 = 8;
pub const DISPUTE_STATUS_CENSORED: i16 = 9;

// Dispute payment types.
pub const DISPUTE_OPENING_FEE: i16 = 1;
pub const DISPUTE_APPEAL_FEE: i16 = 2;
pub const DISPUTE_REFUND: i16 = 3;

// Dispute event types.
pub const START_RESPONSE_PERIOD: i16 = 1;