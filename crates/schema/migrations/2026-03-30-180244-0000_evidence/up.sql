-- Your SQL goes here

CREATE TABLE IF NOT EXISTS evidence
(
    evidence_id                 TEXT         PRIMARY KEY,
    dispute_id                  TEXT         NOT NULL REFERENCES dispute(dispute_id),
    owner                       TEXT         NOT NULL,
    description                 TEXT         NOT NULL,
    src                         TEXT,
    file_name                   TEXT,
    file_type                   TEXT,
    file_subtype                TEXT,
    encrypted                   BOOLEAN      NOT NULL,
    censored                    BOOLEAN      NOT NULL,
    modified                    TIMESTAMP,
    sender                      TEXT         NOT NULL,
    checkpoint_timestamp_ms     BIGINT       NOT NULL
);

CREATE INDEX idx_evidence_dispute ON evidence
(dispute_id, owner, checkpoint_timestamp_ms);