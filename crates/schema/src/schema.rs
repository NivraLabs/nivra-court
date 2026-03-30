// @generated automatically by Diesel CLI.

diesel::table! {
    admin_vote (vote_id) {
        vote_id -> Text,
        vote_type -> Int2,
        vote_enforced -> Bool,
        sender -> Text,
        checkpoint -> Int8,
        timestamp -> Timestamp,
        checkpoint_timestamp_ms -> Int8,
        package -> Text,
        digest -> Text,
        event_digest -> Text,
    }
}

diesel::table! {
    court (court_id) {
        court_id -> Text,
        name -> Text,
        category -> Text,
        description -> Text,
        ai_court -> Bool,
        response_period_ms -> Int8,
        draw_period_ms -> Int8,
        evidence_period_ms -> Int8,
        voting_period_ms -> Int8,
        appeal_period_ms -> Int8,
        dispute_time_ms -> Int8,
        min_stake -> Int8,
        reputation_requirement -> Int2,
        init_nivster_count -> Int2,
        sanction_model -> Int2,
        coefficient -> Int2,
        dispute_fee -> Int8,
        treasury_share -> Int2,
        treasury_share_nvr -> Int2,
        empty_vote_penalty -> Int2,
        status -> Int2,
        key_servers -> Array<Nullable<Text>>,
        public_keys -> Array<Nullable<Text>>,
        threshold -> Int2,
        sender -> Text,
        checkpoint -> Int8,
        timestamp -> Timestamp,
        checkpoint_timestamp_ms -> Int8,
        package -> Text,
        digest -> Text,
        event_digest -> Text,
    }
}

diesel::allow_tables_to_appear_in_same_query!(admin_vote, court,);
