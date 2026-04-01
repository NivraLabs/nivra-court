use std::sync::Arc;

use async_trait::async_trait;
use nivra_schema::models::CourtEconomicsChangeset;
use nivra_schema::schema::court;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::pipeline::sequential::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_indexer_alt_framework::postgres::{Connection, Db};
use diesel::prelude::*;
use diesel_async::RunQueryDsl;

use crate::NivraEnv;
use crate::handlers::has_nivra_events;
use crate::models::nivra::court::CourtEconomicsChanged;
use crate::traits::MoveStruct;


pub struct CourtEconomicsChangedHandler {
    env: NivraEnv,
}

impl CourtEconomicsChangedHandler {
    pub fn new(env: NivraEnv) -> Self {
        Self { env }
    }
}

#[async_trait]
impl Processor for CourtEconomicsChangedHandler {
    const NAME: &'static str = "court_economics_changed_handler";
    type Value = CourtEconomicsChangeset;

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> anyhow::Result<Vec<Self::Value>> {
        let mut results = vec![];

        for tx in &checkpoint.transactions {
            if !has_nivra_events(tx, self.env) {
                continue;
            }
            let Some(events) = &tx.events else {
                continue;
            };

            for ev in events.data.iter() {
                if !CourtEconomicsChanged::matches_event_type(&ev.type_, self.env) {
                    continue;
                }

                let event: CourtEconomicsChanged = bcs::from_bytes(&ev.contents)?;
                let data = CourtEconomicsChangeset { 
                    court_id: event.court.to_string(), 
                    min_stake: event.economics.min_stake as i64, 
                    reputation_requirement: event.economics.reputation_requirement as i16, 
                    init_nivster_count: event.economics.init_nivster_count as i16, 
                    sanction_model: event.economics.sanction_model as i16, 
                    coefficient: event.economics.coefficient as i16, 
                    dispute_fee: event.economics.dispute_fee as i64, 
                    treasury_share: event.economics.treasury_share as i16, 
                    treasury_share_nvr: event.economics.treasury_share_nvr as i16, 
                    empty_vote_penalty: event.economics.empty_vote_penalty as i16, 
                };

                results.push(data);
            }
        }

        Ok(results)
    }
}

#[async_trait]
impl Handler for CourtEconomicsChangedHandler {
    type Store = Db;
    type Batch = Vec<Self::Value>;

    fn batch(&self, batch: &mut Self::Batch, values: std::vec::IntoIter<Self::Value>) {
        batch.extend(values);
    }

    async fn commit<'a>(&self, batch: &Self::Batch, conn: &mut Connection<'a>) -> anyhow::Result<usize> {
        let mut updated = 0;

        for metadata_changeset in batch.iter() {
            diesel::update(court::table.find(metadata_changeset.court_id.clone()))
                .set(metadata_changeset)
                .execute(conn)
                .await?;

            updated += 1;
        }

        Ok(updated)
    }
}