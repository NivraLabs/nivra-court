-- Your SQL goes here

CREATE TABLE IF NOT EXISTS balance_event
(
    id                          BIGSERIAL    PRIMARY KEY,
    nivster                     TEXT         NOT NULL,
    court                       TEXT         NOT NULL REFERENCES court(court_id),
    event_type                  SMALLINT     NOT NULL,
    amount_nvr                  BIGINT       NOT NULL,
    amount_sui                  BIGINT       NOT NULL,
    lock_nvr                    BIGINT       NOT NULL,
    dispute_id                  TEXT         REFERENCES dispute(dispute_id),
    sender                      TEXT         NOT NULL,
    checkpoint_timestamp_ms     BIGINT       NOT NULL
);

CREATE INDEX idx_balance_court ON balance_event
(court, nivster, checkpoint_timestamp_ms, event_type);

CREATE TABLE IF NOT EXISTS nivster_court_balance
(
    court                       TEXT         REFERENCES court(court_id),
    nivster                     TEXT,
    nvr                         BIGINT       NOT NULL,
    sui                         BIGINT       NOT NULL,
    locked_nvr                  BIGINT       NOT NULL,
    in_worker_pool              BOOLEAN      NOT NULL,
    modified_at                 TIMESTAMP    DEFAULT CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (court, nivster)
);

CREATE INDEX idx_nivster_court_balance ON nivster_court_balance(nivster)
INCLUDE (court, nvr, sui, locked_nvr, in_worker_pool);

CREATE INDEX idx_worker_pool_court ON nivster_court_balance(court, in_worker_pool);

CREATE TABLE IF NOT EXISTS nivster_stats
(
    nivster                     TEXT         PRIMARY KEY,
    total_cases                 BIGINT       NOT NULL,
    cases_won                   BIGINT       NOT NULL,
    nvr_won                     BIGINT       NOT NULL,
    nvr_slashes                 BIGINT       NOT NULL,
    sui_won                     BIGINT       NOT NULL,
    modified_at                 TIMESTAMP    DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX idx_nivster_stats_modified ON nivster_stats(modified_at);