-- Your SQL goes here

CREATE TABLE IF NOT EXISTS dispute 
(
    dispute_id                  TEXT         PRIMARY KEY,
    contract_id                 TEXT         NOT NULL,
    court_id                    TEXT         NOT NULL REFERENCES court(court_id),
    max_appeals                 SMALLINT     NOT NULL,
    initiator                   TEXT         NOT NULL,
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
    checkpoint                  BIGINT       NOT NULL,
    timestamp                   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP NOT NULL,
    checkpoint_timestamp_ms     BIGINT       NOT NULL,
    package                     TEXT         NOT NULL,
    digest                      TEXT         NOT NULL,
    event_digest                TEXT         NOT NULL
);

CREATE EXTENSION IF NOT EXISTS btree_gin;

CREATE INDEX idx_dispute_config ON dispute USING GIN 
(contract_id, court_id, max_appeals, options, options_party_mapping);

CREATE TABLE IF NOT EXISTS dispute_payment
(
    id                          BIGSERIAL    PRIMARY KEY,
    dispute_id                  TEXT         NOT NULL REFERENCES dispute(dispute_id),
    party                       TEXT         NOT NULL,
    amount                      BIGINT       NOT NULL,
    payment_type                SMALLINT     NOT NULL,
    sender                      TEXT         NOT NULL,
    checkpoint                  BIGINT       NOT NULL,
    timestamp                   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP NOT NULL,
    checkpoint_timestamp_ms     BIGINT       NOT NULL,
    package                     TEXT         NOT NULL,
    digest                      TEXT         NOT NULL,
    event_digest                TEXT         NOT NULL
);

CREATE INDEX idx_dispute_payment_party ON dispute_payment(party);

CREATE TABLE IF NOT EXISTS dispute_nivster
(
    dispute_id                  TEXT         NOT NULL REFERENCES dispute(dispute_id),
    nivster                     TEXT         NOT NULL,
    votes                       SMALLINT     NOT NULL,
    stake                       BIGINT       NOT NULL,
    PRIMARY KEY (dispute_id, nivster)
);

CREATE INDEX idx_dispute_nivster ON dispute_nivster(nivster);

CREATE TABLE IF NOT EXISTS dispute_event
(
    id                          BIGSERIAL    PRIMARY KEY,
    dispute_id                  TEXT         NOT NULL REFERENCES dispute(dispute_id),
    event_type                  SMALLINT     NOT NULL,
    result                      TEXT,
    votes_per_option            INTEGER[],
    sender                      TEXT         NOT NULL,
    checkpoint                  BIGINT       NOT NULL,
    timestamp                   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP NOT NULL,
    checkpoint_timestamp_ms     BIGINT       NOT NULL,
    package                     TEXT         NOT NULL,
    digest                      TEXT         NOT NULL,
    event_digest                TEXT         NOT NULL
);

CREATE INDEX idx_dispute_events_dispute_id ON dispute_event(dispute_id);
CREATE INDEX idx_dispute_events_timestamp ON dispute_event(checkpoint_timestamp_ms);