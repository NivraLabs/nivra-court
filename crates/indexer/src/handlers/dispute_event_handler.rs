use std::collections::HashSet;
use std::sync::Arc;

use async_trait::async_trait;
use chrono::Utc;
use diesel::upsert::excluded;
use nivra_schema::constants::{DISPUTE_APPEAL_FEE, DISPUTE_CANCELLED, DISPUTE_CENSORED, DISPUTE_COMPLETED, DISPUTE_COMPLETED_ONE_SIDED, DISPUTE_STATUS_ACTIVE, DISPUTE_STATUS_CANCELLED, DISPUTE_STATUS_CENSORED, DISPUTE_STATUS_COMPLETED, DISPUTE_STATUS_COMPLETED_ONE_SIDED, DISPUTE_STATUS_DRAW, DISPUTE_STATUS_RESPONSE, DISPUTE_STATUS_TALLIED, DISPUTE_STATUS_TIE, START_DRAW_PERIOD, START_NEW_ROUND, START_RESPONSE_PERIOD, START_TIE_ROUND, VOTE_FINALIZED};
use nivra_schema::models::{NewDisputeEvent, NewNivsterNotification, NewPartyNotification, PartyStats};
use nivra_schema::schema::dispute::{options, options_party_mapping};
use nivra_schema::schema::{dispute, dispute_event, dispute_payment, nivster_notification, party_notification, party_stats};
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::pipeline::sequential::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_indexer_alt_framework::postgres::{Connection, Db};
use sui_types::transaction::TransactionDataAPI;
use diesel_async::RunQueryDsl;
use diesel::prelude::*;

use crate::NivraEnv;
use crate::handlers::has_nivra_events;
use crate::models::nivra::dispute::DisputeEvent;
use crate::notifications::{notify_nivsters_dispute_resolved, notify_nivsters_new_round, notify_parties_appeal_period, notify_parties_dispute_cancelled, notify_parties_dispute_completed, notify_parties_dispute_defaulted, notify_parties_evidence_period, notify_party_dispute_accepted, notify_party_new_appeal};
use crate::traits::MoveStruct;


pub struct DisputeEventHandler {
    env: NivraEnv,
}

impl DisputeEventHandler {
    pub fn new(env: NivraEnv) -> Self {
        Self { env }
    }
}

#[async_trait]
impl Processor for DisputeEventHandler {
    const NAME: &'static str = "dispute_event_handler";
    type Value = NewDisputeEvent;

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> anyhow::Result<Vec<Self::Value>> {
        let mut results = vec![];

        for tx in &checkpoint.transactions {
            if !has_nivra_events(tx, self.env) {
                continue;
            }
            let Some(events) = &tx.events else {
                continue;
            };

            let checkpoint_timestamp_ms = checkpoint.summary.timestamp_ms as i64;

            for ev in events.data.iter() {
                if !DisputeEvent::matches_event_type(&ev.type_, self.env) {
                    continue;
                }

                let event: DisputeEvent = bcs::from_bytes(&ev.contents)?;
                let data = NewDisputeEvent { 
                    dispute_id: event.dispute.to_string(), 
                    event_type: event.event_type as i16, 
                    result: event.result, 
                    votes_per_option: event.votes_per_option.map(|res| 
                        res.iter().map(|val| *val as i32).collect()
                    ),
                    timestamp: event.timestamp as i64,
                    sender: tx.transaction.sender().to_string(),
                    checkpoint_timestamp_ms, 
                };

                results.push(data);
            }
        }

        Ok(results)
    }
}

#[async_trait]
impl Handler for DisputeEventHandler {
    type Store = Db;
    type Batch = Vec<Self::Value>;

    fn batch(&self, batch: &mut Self::Batch, values: std::vec::IntoIter<Self::Value>) {
        batch.extend(values);
    }

    async fn commit<'a>(&self, batch: &Self::Batch, conn: &mut Connection<'a>) -> anyhow::Result<usize> {
        let mut party_notifications: Vec<NewPartyNotification> = Vec::new();
        let mut party_stats_updates: Vec<PartyStats> = Vec::new();
        let mut nivster_notifications: Vec<NewNivsterNotification> = Vec::new();
        
        for ev in batch.iter() {
            match ev.event_type  {
                START_RESPONSE_PERIOD => {
                    diesel::update(dispute::table.find(&ev.dispute_id))
                        .set((
                            dispute::dispute_status.eq(DISPUTE_STATUS_RESPONSE),
                            dispute::round_init_ms.eq(ev.timestamp),
                        ))
                        .execute(conn)
                        .await?;

                    let notification = notify_party_new_appeal(&ev.dispute_id, conn).await?;
                    party_notifications.push(notification);
                },
                START_DRAW_PERIOD => {
                    diesel::update(dispute::table.find(&ev.dispute_id))
                        .set((
                            dispute::dispute_status.eq(DISPUTE_STATUS_DRAW),
                            dispute::round_init_ms.eq(ev.timestamp),
                        ))
                        .execute(conn)
                        .await?;

                    let notification = notify_party_dispute_accepted(&ev.dispute_id, conn).await?;
                    party_notifications.push(notification);
                },
                START_NEW_ROUND => {
                    let last_payment_type = dispute_payment::table
                        .filter(dispute_payment::dispute_id.eq(&ev.dispute_id))
                        .order(dispute_payment::checkpoint_timestamp_ms.desc())
                        .select(dispute_payment::payment_type)
                        .first::<i16>(conn)
                        .await?;

                    let appeal_used = if last_payment_type == DISPUTE_APPEAL_FEE { 1 } else { 0 };

                    diesel::update(dispute::table.find(&ev.dispute_id))
                        .set((
                            dispute::dispute_status.eq(DISPUTE_STATUS_ACTIVE),
                            dispute::vote_result.eq::<Option<Vec<i32>>>(None),
                            dispute::round_init_ms.eq(ev.timestamp),
                            dispute::current_round.eq(dispute::current_round + 1),
                            dispute::appeals_used.eq(dispute::appeals_used + appeal_used),
                        ))
                        .execute(conn)
                        .await?;

                    let mut notifications = notify_parties_evidence_period(&ev.dispute_id, conn).await?;
                    party_notifications.append(&mut notifications);

                    let mut n_notifications = notify_nivsters_new_round(&ev.dispute_id, false, conn).await?;
                    nivster_notifications.append(&mut n_notifications);
                },
                START_TIE_ROUND => {
                    diesel::update(dispute::table.find(&ev.dispute_id))
                        .set((
                            dispute::dispute_status.eq(DISPUTE_STATUS_ACTIVE),
                            dispute::vote_result.eq::<Option<Vec<i32>>>(None),
                            dispute::round_init_ms.eq(ev.timestamp),
                            dispute::current_round.eq(dispute::current_round + 1),
                        ))
                        .execute(conn)
                        .await?;

                    let mut n_notifications = notify_nivsters_new_round(&ev.dispute_id, true, conn).await?;
                    nivster_notifications.append(&mut n_notifications);
                },
                VOTE_FINALIZED => {
                    let votes_per_option = ev.votes_per_option.as_ref().unwrap();
                    let (_, is_tie) = vote_outcome(votes_per_option);

                    let dispute_status = if is_tie {DISPUTE_STATUS_TIE} else {DISPUTE_STATUS_TALLIED};

                    diesel::update(dispute::table.find(&ev.dispute_id))
                        .set((
                            dispute::dispute_status.eq(dispute_status),
                            dispute::vote_result.eq(&ev.votes_per_option),
                        ))
                        .execute(conn)
                        .await?;

                    if dispute_status == DISPUTE_STATUS_TALLIED {
                        let mut notifications = notify_parties_appeal_period(&ev.dispute_id, conn).await?;
                        party_notifications.append(&mut notifications);
                    }
                },
                DISPUTE_CENSORED => {
                    diesel::update(dispute::table.find(&ev.dispute_id))
                        .set(dispute::dispute_status.eq(DISPUTE_STATUS_CENSORED))
                        .execute(conn)
                        .await?;
                },
                DISPUTE_CANCELLED => {
                    diesel::update(dispute::table.find(&ev.dispute_id))
                        .set(dispute::dispute_status.eq(DISPUTE_STATUS_CANCELLED))
                        .execute(conn)
                        .await?;

                    let (mut notifications, mut party_stats_u) = notify_parties_dispute_cancelled(
                        &ev.dispute_id, 
                        ev.checkpoint_timestamp_ms, 
                        conn
                    ).await?;

                    party_notifications.append(&mut notifications);
                    party_stats_updates.append(&mut party_stats_u);

                    let mut n_notifications = notify_nivsters_dispute_resolved(
                        &ev.dispute_id, 
                        DISPUTE_CANCELLED, 
                        ev.checkpoint_timestamp_ms, 
                        conn
                    ).await?;

                    nivster_notifications.append(&mut n_notifications);
                },
                DISPUTE_COMPLETED => {
                    let result = &ev.result;
                    let dispute_id = &ev.dispute_id;

                    let (parties, winner_p) = update_dispute_with_winner(
                        dispute_id, 
                        result,
                        DISPUTE_STATUS_COMPLETED,
                        conn,
                    ).await?;

                    let (mut notifications, mut party_stats_u) = notify_parties_dispute_completed(
                        dispute_id,
                        parties,
                        winner_p,
                        result,
                        ev.checkpoint_timestamp_ms,
                    );

                    party_notifications.append(&mut notifications);
                    party_stats_updates.append(&mut party_stats_u);

                    let mut n_notifications = notify_nivsters_dispute_resolved(
                        dispute_id, 
                        DISPUTE_COMPLETED, 
                        ev.checkpoint_timestamp_ms, 
                        conn
                    ).await?;

                    nivster_notifications.append(&mut n_notifications);
                },
                DISPUTE_COMPLETED_ONE_SIDED => {
                    let result = &ev.result;
                    let dispute_id = &ev.dispute_id;

                    let (parties, winner_p) = update_dispute_with_winner(
                        dispute_id, 
                        result,
                        DISPUTE_STATUS_COMPLETED_ONE_SIDED,
                        conn
                    ).await?;

                    let (mut notifications, mut party_stats_u) = notify_parties_dispute_defaulted(
                        dispute_id,
                        parties,
                        winner_p,
                        result,
                        ev.checkpoint_timestamp_ms
                    );

                    party_notifications.append(&mut notifications);
                    party_stats_updates.append(&mut party_stats_u);

                    let mut n_notifications = notify_nivsters_dispute_resolved(
                        dispute_id, 
                        DISPUTE_COMPLETED_ONE_SIDED, 
                        ev.checkpoint_timestamp_ms, 
                        conn
                    ).await?;

                    nivster_notifications.append(&mut n_notifications);
                },
                _ => (),
            }
        }

        let inserted = diesel::insert_into(dispute_event::table)
            .values(batch)
            .on_conflict_do_nothing()
            .execute(conn)
            .await?;

        if !party_stats_updates.is_empty() {
            let _ = diesel::insert_into(party_stats::table)
                .values(party_stats_updates)
                .on_conflict(party_stats::party)
                .do_update()
                .set((
                    party_stats::cases_won.eq(party_stats::cases_won + excluded(party_stats::cases_won)),
                    party_stats::cases_lost.eq(party_stats::cases_lost + excluded(party_stats::cases_lost)),
                    party_stats::cases_cancelled.eq(party_stats::cases_cancelled + excluded(party_stats::cases_cancelled)),
                    party_stats::modified_at.eq(Utc::now().naive_utc()),
                ))
                .execute(conn)
                .await?;
        }

        if !party_notifications.is_empty() {
            let _ = diesel::insert_into(party_notification::table)
                .values(party_notifications)
                .on_conflict_do_nothing()
                .execute(conn)
                .await?;
        }

        if !nivster_notifications.is_empty() {
            let _ = diesel::insert_into(nivster_notification::table)
                .values(nivster_notifications)
                .on_conflict_do_nothing()
                .execute(conn)
                .await?;
        }

        Ok(inserted)
    }
}

async fn update_dispute_with_winner<'a>(
    dispute_id: &String,
    result: &Option<String>,
    status_code: i16,
    conn: &mut Connection<'a>,
) -> anyhow::Result<(HashSet<String>, String)> {
    let (opts, mappings) = dispute::table.find(dispute_id)
        .select((options, options_party_mapping))
        .get_result::<(Vec<Option<String>>, Vec<Option<String>>)>(conn)
        .await?;

    let winner_pos = opts.iter()
        .position(|e| e == result)
        .unwrap();

    let winner_p = mappings[winner_pos].clone();

    diesel::update(dispute::table.find(dispute_id))
        .set((
            dispute::dispute_status.eq(status_code),
            dispute::winner_option.eq(result),
            dispute::winner_party.eq(&winner_p)
        ))
        .execute(conn)
        .await?;

    let parties = mappings.into_iter()
        .map(|p| p.unwrap())
        .collect::<HashSet<String>>();


    Ok((parties, winner_p.unwrap()))
}

fn vote_outcome(
    votes_per_option: &Vec<i32>,
) -> (i32, bool) {
    let mut max_value = votes_per_option[0];
    let mut indices = vec![0];

    for (i, &v) in votes_per_option.iter().enumerate().skip(1) {
        if v > max_value {
            max_value = v;
            indices.clear();
            indices.push(i);
        } else if v == max_value {
            indices.push(i);
        }
    }

    (max_value, indices.len() >= 2)
}