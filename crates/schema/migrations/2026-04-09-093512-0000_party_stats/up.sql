-- Your SQL goes here

CREATE TABLE IF NOT EXISTS party_stats
(
    party                       TEXT         PRIMARY KEY,
    total_cases                 BIGINT       NOT NULL,
    cases_won                   BIGINT       NOT NULL,
    cases_lost                  BIGINT       NOT NULL,
    cases_cancelled             BIGINT       NOT NULL,
    modified_at                 TIMESTAMP    DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX idx_party_stats_modified ON party_stats(modified_at);