// Dispute statuses.
pub const DISPUTE_STATUS_RESPONSE: i16 = 1;
pub const DISPUTE_STATUS_DRAW: i16 = 2;
pub const DISPUTE_STATUS_ACTIVE: i16 = 3;
pub const DISPUTE_STATUS_TIE: i16 = 4;
pub const DISPUTE_STATUS_TALLIED: i16 = 5;
pub const DISPUTE_STATUS_CENSORED: i16 = 6;
pub const DISPUTE_STATUS_COMPLETED: i16 = 7;
pub const DISPUTE_STATUS_DEFAULTED: i16 = 8;
pub const DISPUTE_STATUS_CANCELLED: i16 = 9;

// Dispute payment types.
pub const DISPUTE_OPENING_FEE: i16 = 1;
pub const DISPUTE_APPEAL_FEE: i16 = 2;
pub const DISPUTE_REFUND: i16 = 3;

// Dispute event types.
pub const START_RESPONSE_PERIOD: i16 = 1;
pub const START_DRAW_PERIOD: i16 = 2;
pub const START_NEW_ROUND: i16 = 3;
pub const START_TIE_ROUND: i16 = 4;
pub const VOTE_FINALIZED: i16 = 5;
pub const DISPUTE_CENSORED: i16 = 6;
pub const DISPUTE_CANCELLED: i16 = 7;
pub const DISPUTE_COMPLETED: i16 = 8;
pub const DISPUTE_DEFAULTED: i16 = 9;

// Dispute cancellation reasons.
pub const CANCELLATION_REASON_CENSORED: i16 = 1;
pub const CANCELLATION_REASON_UNTALLIED: i16 = 2;
pub const CANCELLATION_REASON_UNRESOLVED_TIE: i16 = 3;
pub const CANCELLATION_REASON_NO_NIVSTERS_DRAWN: i16 = 4;
pub const CANCELLATION_REASON_UNKNOWN: i16 = 5;

// Court balance event types.
pub const BALANCE_DEPOSIT: i16 = 1;
pub const BALANCE_WITHDRAWAL: i16 = 2;
pub const BALANCE_LOCKED: i16 = 3;
pub const BALANCE_UNLOCKED: i16 = 4;
pub const BALANCE_UNLOCKED_WITH_PENALTY: i16 = 5;
pub const BALANCE_UNLOCKED_WITH_REWARD: i16 = 6;

// Party notification types.
pub const DISPUTE_OPENED: i16 = 1;
pub const APPEAL_OPENED: i16 = 2;
pub const DISPUTE_ACCEPTED: i16 = 3;
pub const APPEAL_ACCEPTED: i16 = 4;
pub const EVIDENCE_PERIOD_STARTED: i16 = 5;
pub const APPEAL_PERIOD_STARTED: i16 = 6;
pub const DISPUTE_RESOLVED_CANCELLED: i16 = 7;
pub const DISPUTE_RESOLVED_COMPLETED: i16 = 8;
pub const DISPUTE_RESOLVED_DEFAULTED: i16 = 9;
pub const CUSTOM_NOTIFICATION: i16 = 10;

// Nivster notification types.
pub const NIVSTER_SELECTED: i16 = 1;
pub const NIVSTER_NEW_ROUND_STARTED: i16 = 2;
pub const NIVSTER_NEW_TIE_ROUND_STARTED: i16 = 3;
pub const NIVSTER_VOTING_PERIOD_STARTED: i16 = 4;
pub const NIVSTER_DISPUTE_RESOLVED_CANCELLED: i16 = 5;
pub const NIVSTER_DISPUTE_RESOLVED_COMPLETED: i16 = 6;
pub const NIVSTER_DISPUTE_RESOLVED_DEFAULTED: i16 = 7;
pub const NIVSTER_CUSTOM_NOTIFICATION: i16 = 8;