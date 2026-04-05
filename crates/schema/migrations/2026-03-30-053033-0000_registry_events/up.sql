-- Your SQL goes here

CREATE TABLE IF NOT EXISTS admin_vote 
(
    vote_id                     TEXT         PRIMARY KEY,
    vote_type                   SMALLINT     NOT NULL,
    vote_enforced               BOOLEAN      NOT NULL,
    sender                      TEXT         NOT NULL,
    checkpoint_timestamp_ms     BIGINT       NOT NULL
);

CREATE INDEX idx_admin_vote_timestamp_enforced ON admin_vote
(checkpoint_timestamp_ms, vote_enforced) INCLUDE (vote_id, vote_type);