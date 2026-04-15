-- Your SQL goes here

CREATE TABLE IF NOT EXISTS dispute 
(
    dispute_id                  TEXT         PRIMARY KEY,
    contract_id                 TEXT         NOT NULL,
    court_id                    TEXT         NOT NULL REFERENCES court(court_id),
    description                 TEXT         NOT NULL,
    dispute_status              SMALLINT     NOT NULL,
    vote_result                 INTEGER[],
    winner_option               TEXT,
    winner_party                TEXT,
    current_round               SMALLINT     NOT NULL,
    appeals_used                SMALLINT     NOT NULL,
    max_appeals                 SMALLINT     NOT NULL,
    initiator                   TEXT         NOT NULL,
    last_payer                  TEXT         NOT NULL,
    options                     TEXT[]       NOT NULL,
    options_party_mapping       TEXT[]       NOT NULL,
    round_init_ms               BIGINT       NOT NULL,
    response_period_ms          BIGINT       NOT NULL,
    draw_period_ms              BIGINT       NOT NULL,
    evidence_period_ms          BIGINT       NOT NULL,
    voting_period_ms            BIGINT       NOT NULL,
    appeal_period_ms            BIGINT       NOT NULL,
    init_nivster_count          SMALLINT     NOT NULL,
    sanction_model              SMALLINT     NOT NULL,
    coefficient                 SMALLINT     NOT NULL,
    dispute_fee                 BIGINT       NOT NULL,
    treasury_share              SMALLINT     NOT NULL,
    treasury_share_nvr          SMALLINT     NOT NULL,
    empty_vote_penalty          SMALLINT     NOT NULL,
    sender                      TEXT         NOT NULL,
    checkpoint_timestamp_ms     BIGINT       NOT NULL
);

CREATE EXTENSION IF NOT EXISTS btree_gin;

CREATE INDEX idx_dispute_config ON dispute USING GIN 
(contract_id, court_id, max_appeals, options, options_party_mapping);

CREATE INDEX idx_dispute_status ON dispute(dispute_status, round_init_ms);

CREATE TABLE IF NOT EXISTS dispute_payment
(
    id                          BIGSERIAL    PRIMARY KEY,
    dispute_id                  TEXT         NOT NULL REFERENCES dispute(dispute_id),
    party                       TEXT         NOT NULL,
    amount                      BIGINT       NOT NULL,
    payment_type                SMALLINT     NOT NULL,
    sender                      TEXT         NOT NULL,
    checkpoint_timestamp_ms     BIGINT       NOT NULL
);

CREATE INDEX idx_dispute_payment_party ON dispute_payment(dispute_id, checkpoint_timestamp_ms)
INCLUDE (party, payment_type, amount);

CREATE TABLE IF NOT EXISTS dispute_party
(
    dispute_id                  TEXT         NOT NULL REFERENCES dispute(dispute_id),
    party                       TEXT         NOT NULL,
    checkpoint_timestamp_ms     BIGINT       NOT NULL,
    PRIMARY KEY (dispute_id, party)
);

CREATE INDEX idx_dispute_party_id ON dispute_party(party, dispute_id);
CREATE INDEX idx_dispute_party_ts ON dispute_party(checkpoint_timestamp_ms);

CREATE TABLE IF NOT EXISTS dispute_nivster
(
    dispute_id                  TEXT         NOT NULL REFERENCES dispute(dispute_id),
    nivster                     TEXT         NOT NULL,
    votes                       SMALLINT     NOT NULL,
    stake                       BIGINT       NOT NULL,
    sender                      TEXT         NOT NULL,
    checkpoint_timestamp_ms     BIGINT       NOT NULL,
    PRIMARY KEY (dispute_id, nivster)
);

CREATE INDEX idx_dispute_nivster_created_at ON 
dispute_nivster(nivster, checkpoint_timestamp_ms) INCLUDE (dispute_id, votes, stake);

CREATE TABLE IF NOT EXISTS dispute_event
(
    id                          BIGSERIAL    PRIMARY KEY,
    dispute_id                  TEXT         NOT NULL REFERENCES dispute(dispute_id),
    event_type                  SMALLINT     NOT NULL,
    result                      TEXT,
    votes_per_option            INTEGER[],
    timestamp                   BIGINT       NOT NULL,
    sender                      TEXT         NOT NULL,
    checkpoint_timestamp_ms     BIGINT       NOT NULL
);

CREATE INDEX idx_dispute_events_dispute_id ON dispute_event(dispute_id);
CREATE INDEX idx_dispute_events_timestamp ON dispute_event(checkpoint_timestamp_ms);