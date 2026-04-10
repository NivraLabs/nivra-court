use actix_cors::Cors;
use actix_web::{App, HttpResponse, HttpServer, Responder, error, get, web};
use chrono::DateTime;
use clap::Parser;
use diesel_async::RunQueryDsl;
use diesel::prelude::*;
use diesel_async::{AsyncPgConnection, pooled_connection::{AsyncDieselConnectionManager, bb8::Pool}};
use nivra_schema::{models::{CourtResponse, NivsterCourtBalanceResult}, schema::{court, nivster_court_balance}};
use serde::Deserialize;
use url::Url;


#[derive(Parser)]
#[clap(rename_all = "kebab-case", author, version)]
struct Args {
    #[clap(env, long, default_value_t = 8080)]
    server_port: u16,
    #[clap(
        env,
        long,
        default_value = "postgres://postgres:postgrespw@localhost:5432/nivra"
    )]
    database_url: Url,
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let Args {
        server_port,
        database_url,
    } = Args::parse();

    let pool = Pool::builder()
    .build(
        AsyncDieselConnectionManager::<diesel_async::AsyncPgConnection>
        ::new(database_url)
    )
    .await
    .expect("Failed to build database connection!");

    HttpServer::new(move || {
        App::new()
            .wrap(Cors::permissive())
            .app_data(web::Data::new(pool.clone()))
            .service(get_courts)
            .service(get_stakes_by_address)
    })
    .bind(("0.0.0.0", server_port))?
    .run()
    .await
}

// Request handlers

#[derive(Deserialize)]
struct CourtsQuery {
    modified: Option<i64>,
}

#[get("/courts")]
async fn get_courts(
    query_params: web::Query<CourtsQuery>,
    pool: web::Data<Pool<AsyncPgConnection>>,
) -> actix_web::Result<impl Responder> {
    let mut conn = pool.get().await
        .map_err(error::ErrorInternalServerError)?;

    let mut query = court::table.into_boxed();
    
    if let Some(timestamp) = query_params.modified {
        let dt = DateTime::from_timestamp_millis(timestamp)
            .map(|dt| dt.naive_local())
            .ok_or_else(|| error::ErrorBadRequest("invalid timestamp"))?;

        query = query.filter(court::modified.gt(dt));
    }
    
    let courts: Vec<CourtResponse> = query
        .select(CourtResponse::as_select())
        .load(&mut conn)
        .await
        .map_err(error::ErrorInternalServerError)?;

    Ok(HttpResponse::Ok().json(courts))
}

#[get("/stakes/{address}")]
async fn get_stakes_by_address(
    address: web::Path<String>,
    pool: web::Data<Pool<AsyncPgConnection>>,
) -> actix_web::Result<impl Responder> {
    let address = address.into_inner();

    let mut conn = pool.get().await
        .map_err(error::ErrorInternalServerError)?;

    let stakes = nivster_court_balance::table
        .filter(nivster_court_balance::nivster.eq(address))
        .select(NivsterCourtBalanceResult::as_select())
        .load(&mut conn)
        .await
        .map_err(error::ErrorInternalServerError)?;

    Ok(HttpResponse::Ok().json(stakes))
}