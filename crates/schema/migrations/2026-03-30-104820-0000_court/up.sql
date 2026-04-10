-- Your SQL goes here

CREATE TABLE IF NOT EXISTS court
(
    court_id                    TEXT         PRIMARY KEY,
    name                        TEXT         NOT NULL,
    category                    TEXT         NOT NULL,
    description                 TEXT         NOT NULL,
    ai_court                    BOOLEAN      NOT NULL,
    response_period_ms          BIGINT       NOT NULL,
    draw_period_ms              BIGINT       NOT NULL,
    evidence_period_ms          BIGINT       NOT NULL,
    voting_period_ms            BIGINT       NOT NULL,
    appeal_period_ms            BIGINT       NOT NULL,
    dispute_time_ms             BIGINT       NOT NULL GENERATED ALWAYS AS 
                                             (
                                              evidence_period_ms + 
                                              voting_period_ms + 
                                              appeal_period_ms
                                             ),
    min_stake                   BIGINT       NOT NULL,
    reputation_requirement      SMALLINT     NOT NULL,
    init_nivster_count          SMALLINT     NOT NULL,
    sanction_model              SMALLINT     NOT NULL,
    coefficient                 SMALLINT     NOT NULL,
    dispute_fee                 BIGINT       NOT NULL,
    treasury_share              SMALLINT     NOT NULL,
    treasury_share_nvr          SMALLINT     NOT NULL,
    empty_vote_penalty          SMALLINT     NOT NULL,
    status                      SMALLINT     NOT NULL,
    sender                      TEXT         NOT NULL,
    checkpoint_timestamp_ms     BIGINT       NOT NULL,
    modified                    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX idx_court_modified ON court(modified);
CREATE INDEX idx_court_category ON court(category);