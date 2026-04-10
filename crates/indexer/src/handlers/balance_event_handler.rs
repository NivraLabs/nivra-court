use std::sync::Arc;

use async_trait::async_trait;
use chrono::Utc;
use diesel::upsert::excluded;
use nivra_schema::constants::{BALANCE_DEPOSIT, BALANCE_LOCKED, BALANCE_UNLOCKED, BALANCE_UNLOCKED_WITH_PENALTY, BALANCE_UNLOCKED_WITH_REWARD, BALANCE_WITHDRAWAL};
use nivra_schema::models::{NewBalanceEvent, NivsterCourtBalance, NivsterStats};
use nivra_schema::schema::{balance_event, nivster_court_balance, nivster_stats};
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::pipeline::sequential::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_indexer_alt_framework::postgres::{Connection, Db};
use sui_types::transaction::TransactionDataAPI;
use diesel_async::RunQueryDsl;
use diesel::prelude::*;

use crate::NivraEnv;
use crate::handlers::has_nivra_events;
use crate::models::nivra::court::BalanceEvent as BalanceMoveEvent;
use crate::traits::MoveStruct;


pub struct BalanceEventHandler {
    env: NivraEnv,
}

impl BalanceEventHandler {
    pub fn new(env: NivraEnv) -> Self {
        Self { env }
    }
}

#[async_trait]
impl Processor for BalanceEventHandler {
    const NAME: &'static str = "balance_event_handler";
    type Value = NewBalanceEvent;

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
                if !BalanceMoveEvent::matches_event_type(&ev.type_, self.env) {
                    continue;
                }

                let event: BalanceMoveEvent = bcs::from_bytes(&ev.contents)?;
                let data = NewBalanceEvent {  
                    nivster: event.nivster.to_string(), 
                    court: event.court.to_string(), 
                    event_type: event.event_type as i16, 
                    amount_nvr: event.amount_nvr as i64, 
                    amount_sui: event.amount_sui as i64, 
                    lock_nvr: event.lock_nvr as i64, 
                    dispute_id: event.dispute_id.map(|id| id.to_string()), 
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
impl Handler for BalanceEventHandler {
    type Store = Db;
    type Batch = Vec<Self::Value>;

    fn batch(&self, batch: &mut Self::Batch, values: std::vec::IntoIter<Self::Value>) {
        batch.extend(values);
    }

    async fn commit<'a>(&self, batch: &Self::Batch, conn: &mut Connection<'a>) -> anyhow::Result<usize> {
        let mut nivster_court_balance_updates: Vec<NivsterCourtBalance> = Vec::new();
        let mut nivster_stats_updates: Vec<NivsterStats> = Vec::new();
        let modified_at = Utc::now().naive_utc();

        for balance_event in batch.iter() {
            match balance_event.event_type {
                BALANCE_DEPOSIT => {
                    nivster_court_balance_updates.push(NivsterCourtBalance { 
                        court: balance_event.court.clone(), 
                        nivster: balance_event.nivster.clone(), 
                        nvr: balance_event.amount_nvr, 
                        sui: 0, 
                        locked_nvr: 0, 
                        in_worker_pool: false, 
                        modified_at, 
                    });
                },
                BALANCE_WITHDRAWAL => {
                    nivster_court_balance_updates.push(NivsterCourtBalance { 
                        court: balance_event.court.clone(), 
                        nivster: balance_event.nivster.clone(), 
                        nvr: -balance_event.amount_nvr, 
                        sui: -balance_event.amount_sui, 
                        locked_nvr: 0, 
                        in_worker_pool: false, 
                        modified_at, 
                    });
                },
                BALANCE_LOCKED => {
                    nivster_court_balance_updates.push(NivsterCourtBalance { 
                        court: balance_event.court.clone(), 
                        nivster: balance_event.nivster.clone(), 
                        nvr: -balance_event.lock_nvr, 
                        sui: 0, 
                        locked_nvr: balance_event.lock_nvr, 
                        in_worker_pool: false, 
                        modified_at, 
                    });
                },
                BALANCE_UNLOCKED => {
                    nivster_court_balance_updates.push(NivsterCourtBalance { 
                        court: balance_event.court.clone(), 
                        nivster: balance_event.nivster.clone(), 
                        nvr: balance_event.lock_nvr, 
                        sui: 0, 
                        locked_nvr: -balance_event.lock_nvr, 
                        in_worker_pool: false, 
                        modified_at, 
                    });
                },
                BALANCE_UNLOCKED_WITH_PENALTY => {
                    nivster_court_balance_updates.push(NivsterCourtBalance { 
                        court: balance_event.court.clone(), 
                        nivster: balance_event.nivster.clone(), 
                        nvr: balance_event.lock_nvr - balance_event.amount_nvr, 
                        sui: 0, 
                        locked_nvr: -balance_event.lock_nvr, 
                        in_worker_pool: false, 
                        modified_at, 
                    });

                    nivster_stats_updates.push(NivsterStats { 
                        nivster: balance_event.nivster.clone(), 
                        total_cases: 1, 
                        cases_won: 0, 
                        nvr_won: 0, 
                        nvr_slashes: balance_event.amount_nvr, 
                        sui_won: 0, 
                        modified_at,
                    });
                },
                BALANCE_UNLOCKED_WITH_REWARD => {
                    nivster_court_balance_updates.push(NivsterCourtBalance { 
                        court: balance_event.court.clone(), 
                        nivster: balance_event.nivster.clone(), 
                        nvr: balance_event.lock_nvr + balance_event.amount_nvr, 
                        sui: balance_event.amount_sui, 
                        locked_nvr: -balance_event.lock_nvr, 
                        in_worker_pool: false, 
                        modified_at, 
                    });

                    nivster_stats_updates.push(NivsterStats { 
                        nivster: balance_event.nivster.clone(), 
                        total_cases: 1, 
                        cases_won: 1, 
                        nvr_won: balance_event.amount_nvr, 
                        nvr_slashes: 0, 
                        sui_won: balance_event.amount_sui, 
                        modified_at,
                    });
                },
                _ => (),
            }
        }

        let inserted = diesel::insert_into(balance_event::table)
            .values(batch)
            .on_conflict_do_nothing()
            .execute(conn)
            .await?;

        if !nivster_court_balance_updates.is_empty() {
            diesel::insert_into(nivster_court_balance::table)
                .values(nivster_court_balance_updates)
                .on_conflict((
                    nivster_court_balance::court,
                    nivster_court_balance::nivster,
                ))
                .do_update()
                .set((
                    nivster_court_balance::nvr.eq(nivster_court_balance::nvr + excluded(nivster_court_balance::nvr)),
                    nivster_court_balance::sui.eq(nivster_court_balance::sui + excluded(nivster_court_balance::sui)),
                    nivster_court_balance::locked_nvr.eq(nivster_court_balance::locked_nvr + excluded(nivster_court_balance::locked_nvr)),
                    nivster_court_balance::modified_at.eq(&modified_at),
                ))
                .execute(conn)
                .await?;
        }

        if !nivster_stats_updates.is_empty() {
            diesel::insert_into(nivster_stats::table)
                .values(nivster_stats_updates)
                .on_conflict(nivster_stats::nivster)
                .do_update()
                .set((
                    nivster_stats::total_cases.eq(nivster_stats::total_cases + excluded(nivster_stats::total_cases)),
                    nivster_stats::cases_won.eq(nivster_stats::cases_won + excluded(nivster_stats::cases_won)),
                    nivster_stats::nvr_won.eq(nivster_stats::nvr_won + excluded(nivster_stats::nvr_won)),
                    nivster_stats::nvr_slashes.eq(nivster_stats::nvr_slashes + excluded(nivster_stats::nvr_slashes)),
                    nivster_stats::sui_won.eq(nivster_stats::sui_won + excluded(nivster_stats::sui_won)),
                    nivster_stats::modified_at.eq(&modified_at),
                ))
                .execute(conn)
                .await?;
        }

        Ok(inserted)
    }
}