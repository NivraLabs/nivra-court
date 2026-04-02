use std::net::SocketAddr;

use anyhow::Context;
use clap::Parser;
use nivra_indexer::{NivraEnv, handlers::{admin_vote_finalized_handler::AdminVoteFinalizedHandler, admin_vote_handler::AdminVoteHandler, balance_event_handler::BalanceEventHandler, court_created_handler::CourtCreatedHandler, court_metadata_changed_handler::CourtMetadataChangedHandler, court_operation_changed_handler::CourtOperationChangedHandler, court_timetable_changed_handler::CourtTimetableChangedHandler, dispute_created_handler::DisputeCreatedHandler, dispute_event_handler::DisputeEventHandler, dispute_payment_handler::DisputePaymentHandler, evidence_created_handler::EvidenceCreatedHandler, evidence_modified_handler::EvidenceModifiedHandler, evidence_removed_handler::EvidenceRemovedHandler, nivster_selection_handler::NivsterSelectionHandler, worker_pool_event_handler::WorkerPoolEventHandler}};
use nivra_schema::MIGRATIONS;
use prometheus::Registry;
use sui_indexer_alt_framework::{Indexer, IndexerArgs, ingestion::{ClientArgs, IngestionConfig, ingestion_client::IngestionClientArgs, streaming_client::StreamingClientArgs}};
use sui_indexer_alt_metrics::{MetricsArgs, MetricsService, db::DbConnectionStatsCollector};
use sui_pg_db::{Db, DbArgs};
use url::Url;


#[derive(Debug, Clone, clap::ValueEnum)]
pub enum Package {
    Nivra,
}

#[derive(Parser)]
#[clap(rename_all = "kebab-case", author, version)]
struct Args {
    #[command(flatten)]
    db_args: DbArgs,
    #[command(flatten)]
    indexer_args: IndexerArgs,
    #[command(flatten)]
    streaming_args: StreamingClientArgs,
    #[clap(env, long, default_value = "0.0.0.0:9184")]
    metrics_address: SocketAddr,
    #[clap(
        env,
        long,
        default_value = "postgres://postgres:postgrespw@localhost:5432/nivra"
    )]
    database_url: Url,
    #[clap(env, long)]
    env: NivraEnv,
    #[clap(long, value_enum, default_values = ["nivra"])]
    packages: Vec<Package>,
}

#[tokio::main]
async fn main() -> Result<(), anyhow::Error> {
    let Args {
        db_args,
        indexer_args,
        streaming_args,
        metrics_address,
        database_url,
        env,
        packages,
    } = Args::parse();

    let ingestion_args = IngestionClientArgs {
        remote_store_url: Some(env.remote_store_url()),
        ..Default::default()
    };

    let registry = Registry::new_custom(Some("nivra".into()), None)
        .context("Failed to create Prometheus registry.")?;
    let metrics = MetricsService::new(MetricsArgs { metrics_address }, registry.clone());

    let store = Db::for_write(database_url, db_args)
        .await
        .context("Failed to connect to database")?;

    store
        .run_migrations(Some(&MIGRATIONS))
        .await
        .context("Failed to run pending migrations")?;

    registry.register(Box::new(DbConnectionStatsCollector::new(
        Some("nivra_indexer_db"),
        store.clone(),
    )))?;

    let mut indexer = Indexer::new(
        store,
        indexer_args,
        ClientArgs {
            ingestion: ingestion_args,
            streaming: streaming_args,
        },
        IngestionConfig::default(),
        None,
        metrics.registry(),
    )
    .await?;

    for package in &packages {
        match package {
            Package::Nivra => {
                indexer
                    .sequential_pipeline(AdminVoteHandler::new(env), Default::default())
                    .await?;
                indexer
                    .sequential_pipeline(AdminVoteFinalizedHandler::new(env), Default::default())
                    .await?;
                indexer
                    .sequential_pipeline(CourtCreatedHandler::new(env), Default::default())
                    .await?;
                indexer
                    .sequential_pipeline(CourtMetadataChangedHandler::new(env), Default::default())
                    .await?;
                indexer
                    .sequential_pipeline(CourtTimetableChangedHandler::new(env), Default::default())
                    .await?;
                indexer
                    .sequential_pipeline(CourtTimetableChangedHandler::new(env), Default::default())
                    .await?;
                indexer
                    .sequential_pipeline(CourtOperationChangedHandler::new(env), Default::default())
                    .await?;
                indexer
                    .sequential_pipeline(BalanceEventHandler::new(env), Default::default())
                    .await?;
                indexer
                    .sequential_pipeline(WorkerPoolEventHandler::new(env), Default::default())
                    .await?;
                indexer
                    .sequential_pipeline(DisputeCreatedHandler::new(env), Default::default())
                    .await?;
                indexer
                    .sequential_pipeline(DisputePaymentHandler::new(env), Default::default())
                    .await?;
                indexer
                    .sequential_pipeline(NivsterSelectionHandler::new(env), Default::default())
                    .await?;
                indexer
                    .sequential_pipeline(DisputeEventHandler::new(env), Default::default())
                    .await?;
                indexer
                    .sequential_pipeline(EvidenceCreatedHandler::new(env), Default::default())
                    .await?;
                indexer
                    .sequential_pipeline(EvidenceModifiedHandler::new(env), Default::default())
                    .await?;
                indexer
                    .sequential_pipeline(EvidenceRemovedHandler::new(env), Default::default())
                    .await?;
            },
        }
    }

    let s_indexer = indexer.run().await?;
    let s_metrics = metrics.run().await?;

    s_indexer.attach(s_metrics).main().await?;
    Ok(())
}