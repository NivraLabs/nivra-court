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
(court, nivster, checkpoint_timestamp_ms);

CREATE TABLE IF NOT EXISTS worker_pool
(
    court                       TEXT         REFERENCES court(court_id),
    nivster                     TEXT,
    active                      BOOLEAN      NOT NULL,
    PRIMARY KEY (court, nivster)
);

CREATE INDEX idx_worker_pool_court ON worker_pool(court);