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
    balance_event (id) {
        id -> Int8,
        nivster -> Nullable<Text>,
        court -> Nullable<Text>,
        event_type -> Int2,
        amount_nvr -> Nullable<Int8>,
        amount_sui -> Nullable<Int8>,
        lock_nvr -> Nullable<Int8>,
        dispute_id -> Nullable<Text>,
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

diesel::table! {
    dispute (dispute_id) {
        dispute_id -> Text,
        contract_id -> Text,
        court_id -> Text,
        status -> Int2,
        round -> Int2,
        appeals_used -> Int2,
        result -> Nullable<Array<Nullable<Int4>>>,
        winner_option -> Nullable<Text>,
        cancellation_reason -> Nullable<Int2>,
        max_appeals -> Int2,
        initiator -> Text,
        options -> Array<Nullable<Text>>,
        options_party_mapping -> Array<Nullable<Text>>,
        round_init_ms -> Int8,
        response_period_ms -> Int8,
        draw_period_ms -> Int8,
        evidence_period_ms -> Int8,
        voting_period_ms -> Int8,
        appeal_period_ms -> Int8,
        init_nivster_count -> Int2,
        sanction_model -> Int2,
        coefficient -> Int2,
        dispute_fee -> Int8,
        treasury_share -> Int2,
        treasury_share_nvr -> Int2,
        empty_vote_penalty -> Int2,
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

diesel::table! {
    dispute_event (id) {
        id -> Int8,
        dispute_id -> Text,
        event_type -> Int2,
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
    dispute_nivster (dispute_id, nivster) {
        dispute_id -> Text,
        nivster -> Text,
        votes -> Int2,
        stake -> Int8,
    }
}

diesel::table! {
    dispute_payment (id) {
        id -> Int8,
        dispute_id -> Text,
        party -> Text,
        amount -> Int8,
        payment_type -> Int2,
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
    evidence (evidence_id) {
        evidence_id -> Text,
        dispute_id -> Text,
        owner -> Text,
        description -> Text,
        src -> Nullable<Text>,
        file_name -> Nullable<Text>,
        file_type -> Nullable<Text>,
        file_subtype -> Nullable<Text>,
        encrypted -> Bool,
        modified -> Nullable<Timestamp>,
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
    nivster (address) {
        address -> Text,
    }
}

diesel::table! {
    worker_pool (court, nivster) {
        court -> Text,
        nivster -> Text,
    }
}

diesel::joinable!(balance_event -> court (court));
diesel::joinable!(balance_event -> dispute (dispute_id));
diesel::joinable!(balance_event -> nivster (nivster));
diesel::joinable!(dispute -> court (court_id));
diesel::joinable!(dispute_event -> dispute (dispute_id));
diesel::joinable!(dispute_nivster -> dispute (dispute_id));
diesel::joinable!(dispute_nivster -> nivster (nivster));
diesel::joinable!(dispute_payment -> dispute (dispute_id));
diesel::joinable!(evidence -> dispute (dispute_id));
diesel::joinable!(worker_pool -> court (court));
diesel::joinable!(worker_pool -> nivster (nivster));

diesel::allow_tables_to_appear_in_same_query!(
    admin_vote,
    balance_event,
    court,
    dispute,
    dispute_event,
    dispute_nivster,
    dispute_payment,
    evidence,
    nivster,
    worker_pool,
);
