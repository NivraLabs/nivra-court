use std::sync::Arc;

use async_trait::async_trait;
use diesel::ExpressionMethods;
use nivra_schema::schema::admin_vote;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::pipeline::sequential::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_indexer_alt_framework::postgres::{Connection, Db};
use diesel::prelude::*;
use diesel_async::RunQueryDsl;

use crate::NivraEnv;
use crate::handlers::has_nivra_events;
use crate::models::nivra::registry::AdminVoteFinalizedEvent;
use crate::traits::MoveStruct;


pub struct AdminVoteFinalizedHandler {
    env: NivraEnv,
}

impl AdminVoteFinalizedHandler {
    pub fn new(env: NivraEnv) -> Self {
        Self { env }
    }
}

#[async_trait]
impl Processor for AdminVoteFinalizedHandler {
    const NAME: &'static str = "admin_vote_finalized_handler";
    type Value = String;

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> anyhow::Result<Vec<Self::Value>> {
        let mut results = vec![];

        for tx in &checkpoint.transactions {
            if !has_nivra_events(tx, self.env) {
                continue;
            }
            let Some(events) = &tx.events else {
                continue;
            };

            for (_, ev) in events.data.iter().enumerate() {
                if !AdminVoteFinalizedEvent::matches_event_type(&ev.type_, self.env) {
                    continue;
                }

                let event: AdminVoteFinalizedEvent = bcs::from_bytes(&ev.contents)?;
                results.push(event.vote.to_string());
            }
        }

        Ok(results)
    }
}

#[async_trait]
impl Handler for AdminVoteFinalizedHandler {
    type Store = Db;
    type Batch = Vec<Self::Value>;

    fn batch(&self, batch: &mut Self::Batch, values: std::vec::IntoIter<Self::Value>) {
        batch.extend(values);
    }

    async fn commit<'a>(&self, batch: &Self::Batch, conn: &mut Connection<'a>) -> anyhow::Result<usize> {
        let mut updated = 0;

        for vote_id in batch.iter() {
            diesel::update(admin_vote::table.find(vote_id))
                .set(admin_vote::vote_enforced.eq(true))
                .execute(conn)
                .await?;

            updated += 1;
        }

        Ok(updated)
    }
}