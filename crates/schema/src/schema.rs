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
        nivster -> Text,
        court -> Text,
        event_type -> Int2,
        amount_nvr -> Int8,
        amount_sui -> Int8,
        lock_nvr -> Int8,
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
        result -> Nullable<Text>,
        votes_per_option -> Nullable<Array<Nullable<Int4>>>,
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
        censored -> Bool,
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
    watermarks (pipeline) {
        pipeline -> Text,
        epoch_hi_inclusive -> Int8,
        checkpoint_hi_inclusive -> Int8,
        tx_hi -> Int8,
        timestamp_ms_hi_inclusive -> Int8,
        reader_lo -> Int8,
        pruner_timestamp -> Timestamp,
        pruner_hi -> Int8,
        chain_id -> Nullable<Bytea>,
    }
}

diesel::table! {
    worker_pool (court, nivster) {
        court -> Text,
        nivster -> Text,
        active -> Bool,
    }
}

diesel::joinable!(balance_event -> court (court));
diesel::joinable!(balance_event -> dispute (dispute_id));
diesel::joinable!(dispute -> court (court_id));
diesel::joinable!(dispute_event -> dispute (dispute_id));
diesel::joinable!(dispute_nivster -> dispute (dispute_id));
diesel::joinable!(dispute_payment -> dispute (dispute_id));
diesel::joinable!(evidence -> dispute (dispute_id));
diesel::joinable!(worker_pool -> court (court));

diesel::allow_tables_to_appear_in_same_query!(
    admin_vote,
    balance_event,
    court,
    dispute,
    dispute_event,
    dispute_nivster,
    dispute_payment,
    evidence,
    watermarks,
    worker_pool,
);
