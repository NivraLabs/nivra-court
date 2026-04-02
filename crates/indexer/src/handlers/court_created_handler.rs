use std::sync::Arc;

use async_trait::async_trait;
use nivra_schema::models::Court;
use nivra_schema::schema::court;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::pipeline::sequential::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_indexer_alt_framework::postgres::{Connection, Db};
use sui_types::transaction::TransactionDataAPI;
use diesel_async::RunQueryDsl;

use crate::NivraEnv;
use crate::handlers::{has_nivra_events, try_extract_move_call_package};
use crate::models::nivra::court::CourtCreatedEvent;
use crate::traits::MoveStruct;


pub struct CourtCreatedHandler {
    env: NivraEnv,
}

impl CourtCreatedHandler {
    pub fn new(env: NivraEnv) -> Self {
        Self { env }
    }
}

#[async_trait]
impl Processor for CourtCreatedHandler {
    const NAME: &'static str = "court_created_handler";
    type Value = Court;

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> anyhow::Result<Vec<Self::Value>> {
        let mut results = vec![];

        for tx in &checkpoint.transactions {
            if !has_nivra_events(tx, self.env) {
                continue;
            }
            let Some(events) = &tx.events else {
                continue;
            };

            let package = try_extract_move_call_package(tx).unwrap_or_default();
            let checkpoint_timestamp_ms = checkpoint.summary.timestamp_ms as i64;
            let checkpoint_seq = checkpoint.summary.sequence_number as i64;
            let digest = tx.transaction.digest();

            for (index, ev) in events.data.iter().enumerate() {
                if !CourtCreatedEvent::matches_event_type(&ev.type_, self.env) {
                    continue;
                }

                let event: CourtCreatedEvent = bcs::from_bytes(&ev.contents)?;
                let data = Court { 
                    court_id: event.court.to_string(), 
                    name: event.metadata.name, 
                    category: event.metadata.category, 
                    description: event.metadata.description, 
                    ai_court: event.metadata.ai_court, 
                    response_period_ms: event.timetable.response_period_ms as i64, 
                    draw_period_ms: event.timetable.draw_period_ms as i64, 
                    evidence_period_ms: event.timetable.evidence_period_ms as i64,
                    voting_period_ms: event.timetable.voting_period_ms as i64, 
                    appeal_period_ms: event.timetable.appeal_period_ms as i64, 
                    min_stake: event.economics.min_stake as i64, 
                    reputation_requirement: event.economics.reputation_requirement as i16, 
                    init_nivster_count: event.economics.init_nivster_count as i16, 
                    sanction_model: event.economics.sanction_model as i16, 
                    coefficient: event.economics.coefficient as i16, 
                    dispute_fee: event.economics.dispute_fee as i64, 
                    treasury_share: event.economics.treasury_share as i16, 
                    treasury_share_nvr: event.economics.treasury_share_nvr as i16, 
                    empty_vote_penalty: event.economics.empty_vote_penalty as i16, 
                    status: event.status as i16, 
                    sender: tx.transaction.sender().to_string(), 
                    checkpoint: checkpoint_seq, 
                    checkpoint_timestamp_ms, 
                    package: package.clone(), 
                    digest: digest.to_string(), 
                    event_digest: format!("{digest}{index}"), 
                };

                results.push(data);
            }
        }

        Ok(results)
    }
}

#[async_trait]
impl Handler for CourtCreatedHandler {
    type Store = Db;
    type Batch = Vec<Self::Value>;

    fn batch(&self, batch: &mut Self::Batch, values: std::vec::IntoIter<Self::Value>) {
        batch.extend(values);
    }

    async fn commit<'a>(&self, batch: &Self::Batch, conn: &mut Connection<'a>) -> anyhow::Result<usize> {
        let inserted = diesel::insert_into(court::table)
            .values(batch)
            .on_conflict_do_nothing()
            .execute(conn)
            .await?;

        Ok(inserted)
    }
}