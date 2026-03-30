use std::net::SocketAddr;

use clap::Parser;
use nivra_indexer::NivraEnv;
use sui_indexer_alt_framework::{IndexerArgs, ingestion::streaming_client::StreamingClientArgs};
use sui_pg_db::DbArgs;
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
    
    Ok(())
}