use std::collections::HashSet;

use nivra_schema::{constants::{APPEAL_ACCEPTED, APPEAL_OPENED, APPEAL_PERIOD_STARTED, CANCELLATION_REASON_CENSORED, CANCELLATION_REASON_NO_NIVSTERS_DRAWN, CANCELLATION_REASON_UNKNOWN, CANCELLATION_REASON_UNRESOLVED_TIE, CANCELLATION_REASON_UNTALLIED, DISPUTE_ACCEPTED, DISPUTE_COMPLETED, DISPUTE_COMPLETED_ONE_SIDED, DISPUTE_OPENING_FEE, DISPUTE_RESOLVED_CANCELLED, DISPUTE_RESOLVED_COMPLETED, DISPUTE_RESOLVED_DEFAULTED, DISPUTE_STATUS_ACTIVE, DISPUTE_STATUS_CENSORED, DISPUTE_STATUS_DRAW, DISPUTE_STATUS_TIE, EVIDENCE_PERIOD_STARTED, NIVSTER_DISPUTE_RESOLVED_CANCELLED, NIVSTER_DISPUTE_RESOLVED_COMPLETED, NIVSTER_DISPUTE_RESOLVED_DEFAULTED, NIVSTER_NEW_ROUND_STARTED, NIVSTER_NEW_TIE_ROUND_STARTED, NIVSTER_SELECTED, NIVSTER_VOTING_PERIOD_STARTED}, models::{DisputeNivster, NewNivsterNotificationRef, NewPartyNotification, NewPartyNotificationRef}, schema::{dispute, dispute_nivster, dispute_payment, nivster_notification, party_notification}};
use sui_indexer_alt_framework::postgres::Connection;
use diesel_async::RunQueryDsl;
use diesel::prelude::*;

const MONTH_IN_MS: i64 = 2_629_746_000;
const WEEK_IN_MS: i64 = 604_800_000;


pub async fn notify_party_new_appeal<'a>(
    dispute_id: &String,
    conn: &mut Connection<'a>,
) -> anyhow::Result<usize> {
    let (party_a, payment_amount, r_init_ms, response_p_ms, parties) = dispute_payment::table
        .inner_join(dispute::table)
        .filter(dispute_payment::dispute_id.eq(dispute_id))
        .order(dispute_payment::checkpoint_timestamp_ms.desc())
        .select((
            dispute_payment::party, 
            dispute_payment::amount,
            dispute::round_init_ms,
            dispute::response_period_ms,
            dispute::options_party_mapping,
        ))
        .first::<(String, i64, i64, i64, Vec<Option<String>>)>(conn)
        .await?;

    let party_b = parties.into_iter()
        .map(|addr| addr.unwrap())
        .find(|p| p != &party_a)
        .unwrap();

    let notification = NewPartyNotificationRef {
        party: &party_b,
        dispute: Some(dispute_id),
        notification_type: APPEAL_OPENED,
        custom_msg: Some(&payment_amount.to_string()),
        valid_timestamp_ms: r_init_ms,
        expires_timestamp_ms: r_init_ms + response_p_ms,
        checked: false,
    };

    let rows = diesel::insert_into(party_notification::table)
        .values(&notification)
        .execute(conn)
        .await?;

    Ok(rows)
}

pub async fn notify_party_dispute_accepted<'a>(
    dispute_id: &String,
    conn: &mut Connection<'a>,
) -> anyhow::Result<usize> {
    let payments: Vec<(String, i16, i64, i64, i64)> = dispute_payment::table
        .inner_join(dispute::table)
        .filter(dispute_payment::dispute_id.eq(dispute_id))
        .order(dispute_payment::checkpoint_timestamp_ms.desc())
        .select((
            dispute_payment::party,
            dispute_payment::payment_type,
            dispute::round_init_ms,
            dispute::response_period_ms,
            dispute::draw_period_ms,
        ))
        .limit(2)
        .load(conn)
        .await?;

    let notification_type = if payments[0].1 == DISPUTE_OPENING_FEE {
        DISPUTE_ACCEPTED
    } else {
        APPEAL_ACCEPTED
    };

    let notification = NewPartyNotificationRef {
        party: &payments[1].0,
        dispute: Some(dispute_id),
        notification_type,
        custom_msg: None,
        valid_timestamp_ms: payments[0].2,
        expires_timestamp_ms: payments[0].2 + payments[0].3 + payments[0].4,
        checked: false,
    };

    let rows = diesel::insert_into(party_notification::table)
        .values(&notification)
        .execute(conn)
        .await?;

    Ok(rows)
}

pub async fn notify_parties_evidence_period<'a>(
    dispute_id: &String,
    conn: &mut Connection<'a>,
) -> anyhow::Result<usize> {
    let (r_init_ms, evidence_p_ms, parties) = dispute::table
        .find(dispute_id)
        .select((
            dispute::round_init_ms,
            dispute::evidence_period_ms,
            dispute::options_party_mapping,
        ))
        .get_result::<(i64, i64, Vec<Option<String>>)>(conn)
        .await?;

    let notifications: Vec<NewPartyNotification> = parties.into_iter()
        .map(|p| p.unwrap())
        .collect::<HashSet<String>>()
        .into_iter()
        .map(|party| NewPartyNotification {
            party,
            dispute: Some(dispute_id.clone()),
            notification_type: EVIDENCE_PERIOD_STARTED,
            custom_msg: None,
            valid_timestamp_ms: r_init_ms,
            expires_timestamp_ms: r_init_ms + evidence_p_ms,
            checked: false,
        })
        .collect();

    let rows = diesel::insert_into(party_notification::table)
        .values(notifications)
        .execute(conn)
        .await?;

    Ok(rows)
}

pub async fn notify_parties_appeal_period<'a>(
    dispute_id: &String,
    conn: &mut Connection<'a>,
) -> anyhow::Result<usize> {
    let (r_init_ms, evidence_p_ms, voting_p_ms, appeal_p_ms, parties) = dispute::table
        .find(dispute_id)
        .select((
            dispute::round_init_ms,
            dispute::evidence_period_ms,
            dispute::voting_period_ms,
            dispute::appeal_period_ms,
            dispute::options_party_mapping,
        ))
        .get_result::<(i64, i64, i64, i64, Vec<Option<String>>)>(conn)
        .await?;

    let notifications: Vec<NewPartyNotification> = parties.into_iter()
        .map(|p| p.unwrap())
        .collect::<HashSet<String>>()
        .into_iter()
        .map(|party| NewPartyNotification {
            party,
            dispute: Some(dispute_id.clone()),
            notification_type: APPEAL_PERIOD_STARTED,
            custom_msg: None,
            valid_timestamp_ms: r_init_ms + evidence_p_ms + voting_p_ms,
            expires_timestamp_ms: r_init_ms + evidence_p_ms + voting_p_ms + appeal_p_ms,
            checked: false,
        })
        .collect();

    let rows = diesel::insert_into(party_notification::table)
        .values(notifications)
        .execute(conn)
        .await?;

    Ok(rows)
}

pub async fn notify_parties_dispute_cancelled<'a>(
    dispute_id: &String,
    timestamp: i64,
    conn: &mut Connection<'a>,
) -> anyhow::Result<usize> {
    let (
        status,
        r_init_ms,
        draw_p_ms, 
        evidence_p_ms, 
        voting_p_ms, 
        appeal_p_ms, 
        parties
    ) = dispute::table
        .find(dispute_id)
        .select((
            dispute::dispute_status,
            dispute::round_init_ms,
            dispute::draw_period_ms,
            dispute::evidence_period_ms,
            dispute::voting_period_ms,
            dispute::appeal_period_ms,
            dispute::options_party_mapping,
        ))
        .get_result::<(i16, i64, i64, i64, i64, i64, Vec<Option<String>>)>(conn)
        .await?;

    let draw_period_end = r_init_ms + draw_p_ms;
    let round_end = r_init_ms + evidence_p_ms + voting_p_ms + appeal_p_ms;

    let cancellation_reason = if status == DISPUTE_STATUS_CENSORED {
        CANCELLATION_REASON_CENSORED
    } else if status == DISPUTE_STATUS_ACTIVE && timestamp > round_end {
        CANCELLATION_REASON_UNTALLIED
    } else if status == DISPUTE_STATUS_TIE && timestamp > round_end {
        CANCELLATION_REASON_UNRESOLVED_TIE
    } else if status == DISPUTE_STATUS_DRAW && timestamp > draw_period_end {
        CANCELLATION_REASON_NO_NIVSTERS_DRAWN
    } else {
        CANCELLATION_REASON_UNKNOWN
    };

    let notifications: Vec<NewPartyNotification> = parties.into_iter()
        .map(|p| p.unwrap())
        .collect::<HashSet<String>>()
        .into_iter()
        .map(|party| NewPartyNotification {
            party,
            dispute: Some(dispute_id.clone()),
            notification_type: DISPUTE_RESOLVED_CANCELLED,
            custom_msg: Some(cancellation_reason.to_string()),
            valid_timestamp_ms: timestamp,
            expires_timestamp_ms: timestamp + MONTH_IN_MS,
            checked: false,
        })
        .collect();

    let rows = diesel::insert_into(party_notification::table)
        .values(notifications)
        .execute(conn)
        .await?;

    Ok(rows)
}

pub async fn notify_parties_dispute_completed<'a>(
    dispute_id: &String,
    timestamp: i64,
    conn: &mut Connection<'a>,
) -> anyhow::Result<usize> {
    let (parties, winner_opt) = dispute::table
        .find(dispute_id)
        .select((
            dispute::options_party_mapping,
            dispute::winner_option,
        ))
        .get_result::<(Vec<Option<String>>, Option<String>)>(conn)
        .await?;

    let notifications: Vec<NewPartyNotification> = parties.into_iter()
        .map(|p| p.unwrap())
        .collect::<HashSet<String>>()
        .into_iter()
        .map(|party| NewPartyNotification {
            party,
            dispute: Some(dispute_id.clone()),
            notification_type: DISPUTE_RESOLVED_COMPLETED,
            custom_msg: winner_opt.clone(),
            valid_timestamp_ms: timestamp,
            expires_timestamp_ms: timestamp + MONTH_IN_MS,
            checked: false,
        })
        .collect();

    let rows = diesel::insert_into(party_notification::table)
        .values(notifications)
        .execute(conn)
        .await?;

    Ok(rows)
}

pub async fn notify_parties_dispute_defaulted<'a>(
    dispute_id: &String,
    timestamp: i64,
    conn: &mut Connection<'a>,
) -> anyhow::Result<usize> {
    let (parties, winner_opt) = dispute::table
        .find(dispute_id)
        .select((
            dispute::options_party_mapping,
            dispute::winner_option,
        ))
        .get_result::<(Vec<Option<String>>, Option<String>)>(conn)
        .await?;

    let notifications: Vec<NewPartyNotification> = parties.into_iter()
        .map(|p| p.unwrap())
        .collect::<HashSet<String>>()
        .into_iter()
        .map(|party| NewPartyNotification {
            party,
            dispute: Some(dispute_id.clone()),
            notification_type: DISPUTE_RESOLVED_DEFAULTED,
            custom_msg: winner_opt.clone(),
            valid_timestamp_ms: timestamp,
            expires_timestamp_ms: timestamp + MONTH_IN_MS,
            checked: false,
        })
        .collect();

    let rows = diesel::insert_into(party_notification::table)
        .values(notifications)
        .execute(conn)
        .await?;

    Ok(rows)
}

pub async fn notify_nivsters_dispute_selection<'a>(
    nivsters: &Vec<DisputeNivster>,
    conn: &mut Connection<'a>,
) -> anyhow::Result<usize> {
    let notifications: Vec<NewNivsterNotificationRef> = nivsters.iter()
        .map(|nivster_data| NewNivsterNotificationRef {
            nivster: &nivster_data.nivster,
            dispute: Some(&nivster_data.dispute_id),
            notification_type: NIVSTER_SELECTED,
            custom_msg: None,
            valid_timestamp_ms: nivster_data.checkpoint_timestamp_ms,
            expires_timestamp_ms: nivster_data.checkpoint_timestamp_ms + WEEK_IN_MS,
            checked: false,
        })
        .collect();

    let rows = diesel::insert_into(nivster_notification::table)
        .values(notifications)
        .execute(conn)
        .await?;

    Ok(rows)
}

pub async fn notify_nivsters_new_round<'a>(
    dispute_id: &String,
    tie_round: bool,
    conn: &mut Connection<'a>,
) -> anyhow::Result<usize> {
    let nivsters_with_periods: Vec<(String, i64, i64, i64)> = dispute_nivster::table
        .inner_join(dispute::table)
        .filter(dispute_nivster::dispute_id.eq(dispute_id))
        .select((
            dispute_nivster::nivster,
            dispute::round_init_ms,
            dispute::evidence_period_ms,
            dispute::voting_period_ms,
        ))
        .load(conn)
        .await?;

    let mut notifications: Vec<NewNivsterNotificationRef> = Vec::new();

    for data in nivsters_with_periods.iter() {
        let (voting_period_start, round_started_notification_type) = if tie_round {
            (data.1, NIVSTER_NEW_ROUND_STARTED)
        } else {
            (data.1 + data.2, NIVSTER_NEW_TIE_ROUND_STARTED)
        };

        notifications.push(NewNivsterNotificationRef {
            nivster: &data.0,
            dispute: Some(dispute_id),
            notification_type: round_started_notification_type,
            custom_msg: None,
            valid_timestamp_ms: data.1,
            expires_timestamp_ms: voting_period_start + data.3,
            checked: false,
        });

        notifications.push(NewNivsterNotificationRef {
            nivster: &data.0,
            dispute: Some(dispute_id),
            notification_type: NIVSTER_VOTING_PERIOD_STARTED,
            custom_msg: None,
            valid_timestamp_ms: voting_period_start,
            expires_timestamp_ms: voting_period_start + data.3,
            checked: false,
        });
    }

    let rows = diesel::insert_into(nivster_notification::table)
        .values(notifications)
        .execute(conn)
        .await?;

    Ok(rows)
}

pub async fn notify_nivsters_dispute_resolved<'a>(
    dispute_id: &String,
    dispute_event_type: i16,
    timestamp: i64,
    conn: &mut Connection<'a>,
) -> anyhow::Result<usize> {
    let nivsters: Vec<String> = dispute_nivster::table
        .filter(dispute_nivster::dispute_id.eq(dispute_id))
        .select(dispute_nivster::nivster)
        .load(conn)
        .await?;

    let notification_type = match dispute_event_type {
        DISPUTE_COMPLETED => NIVSTER_DISPUTE_RESOLVED_COMPLETED,
        DISPUTE_COMPLETED_ONE_SIDED => NIVSTER_DISPUTE_RESOLVED_DEFAULTED,
        _ => NIVSTER_DISPUTE_RESOLVED_CANCELLED,
    };

    let notifications: Vec<NewNivsterNotificationRef> = nivsters.iter()
        .map(|addr| NewNivsterNotificationRef {
            nivster: addr,
            dispute: Some(dispute_id),
            notification_type,
            custom_msg: None,
            valid_timestamp_ms: timestamp,
            expires_timestamp_ms: timestamp + MONTH_IN_MS,
            checked: false,
        })
        .collect();

    let rows = diesel::insert_into(nivster_notification::table)
        .values(notifications)
        .execute(conn)
        .await?;

    Ok(rows)
}