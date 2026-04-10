-- Your SQL goes here

CREATE TABLE IF NOT EXISTS nivster_notification
(
    id                          BIGSERIAL    PRIMARY KEY,
    nivster                     TEXT         NOT NULL,
    dispute                     TEXT         REFERENCES dispute(dispute_id),
    notification_type           SMALLINT     NOT NULL,
    custom_msg                  TEXT,
    valid_timestamp_ms          BIGINT       NOT NULL,
    expires_timestamp_ms        BIGINT       NOT NULL,
    checked                     BOOLEAN      NOT NULL,
    created_at                  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX idx_notification_nivster_created ON nivster_notification(created_at);

CREATE INDEX idx_notification_nivster ON nivster_notification
(nivster, valid_timestamp_ms, expires_timestamp_ms, checked) 
INCLUDE (id, notification_type, custom_msg, dispute);

CREATE TABLE IF NOT EXISTS party_notification
(
    id                          BIGSERIAL    PRIMARY KEY,
    party                       TEXT         NOT NULL,
    dispute                     TEXT         REFERENCES dispute(dispute_id),
    notification_type           SMALLINT     NOT NULL,
    custom_msg                  TEXT,
    valid_timestamp_ms          BIGINT       NOT NULL,
    expires_timestamp_ms        BIGINT       NOT NULL,
    checked                     BOOLEAN      NOT NULL,
    created_at                  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX idx_notification_party_created ON party_notification(created_at);

CREATE INDEX idx_notification_party ON party_notification
(party, valid_timestamp_ms, expires_timestamp_ms, checked) 
INCLUDE (id, notification_type, custom_msg);