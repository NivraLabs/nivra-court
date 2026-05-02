use actix_cors::Cors;
use actix_web::{App, HttpResponse, HttpServer, Responder, error, get, web};
use chrono::DateTime;
use clap::Parser;
use diesel_async::RunQueryDsl;
use diesel::{dsl::count_star, prelude::*};
use diesel_async::{AsyncPgConnection, pooled_connection::{AsyncDieselConnectionManager, bb8::Pool}};
use nivra_schema::{constants::DISPUTE_STATUS_COMPLETED, models::{CourtDisputeOverview, CourtResponse, DisputeDetailsResponse, DisputeOutput, Evidence, EvidenceOutput, NivsterCourtBalanceResult, PartyStatsResponse}, schema::{court, dispute, dispute_party, nivster_court_balance, party_stats}};
use serde::Deserialize;
use url::Url;

use crate::models::{CourtOverviewResponse, DisputeOverviewResponse, DisputeResponse, PaginatedDisputesResponse};

pub(crate) mod models;


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
            .service(get_court_overview)
            .service(get_active_party_disputes_by_address)
            .service(get_resolved_party_disputes_by_address)
            .service(get_party_stats_by_address)
            .service(get_dispute_by_id)
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

#[get("/court_overview/{court_id}")]
async fn get_court_overview(
    court_id: web::Path<String>,
    pool: web::Data<Pool<AsyncPgConnection>>,
) -> actix_web::Result<impl Responder> {
    let court_id = court_id.into_inner();

    let mut conn = pool.get().await
        .map_err(error::ErrorInternalServerError)?;

    let worker_count = nivster_court_balance::table
        .filter(nivster_court_balance::court.eq(&court_id))
        .filter(nivster_court_balance::in_worker_pool.eq(true))
        .select(count_star())
        .single_value();

    let (overview, wp_count): (CourtDisputeOverview, Option<i64>) = court::table
        .find(&court_id)
        .select((
            CourtDisputeOverview::as_select(),
            worker_count,
        ))
        .first(&mut conn)
        .await
        .map_err(|e_type| {
            match e_type {
                diesel::result::Error::NotFound => error::ErrorNotFound(e_type),
                _ => error::ErrorInternalServerError(e_type),
            }
        })?;

    Ok(HttpResponse::Ok().json(CourtOverviewResponse { 
        status: overview.status, 
        name: overview.name, 
        ai_court: overview.ai_court, 
        response_period_ms: overview.response_period_ms, 
        evidence_period_ms: overview.evidence_period_ms, 
        voting_period_ms: overview.voting_period_ms, 
        appeal_period_ms: overview.appeal_period_ms, 
        init_nivster_count: overview.init_nivster_count, 
        dispute_fee: overview.dispute_fee, 
        worker_pool_count: wp_count.unwrap_or(0), 
    }))
}

#[derive(Deserialize)]
struct DisputesQuery {
    pub cursor: Option<i64>,
    pub limit: Option<i64>,
}

#[get("/active_party_disputes/{address}")]
async fn get_active_party_disputes_by_address(
    address: web::Path<String>,
    params: web::Query<DisputesQuery>,
    pool: web::Data<Pool<AsyncPgConnection>>,
) -> actix_web::Result<impl Responder> {
    let address = address.into_inner();

    // Pagination
    let limit = params.limit.unwrap_or(10).min(10);
    let cursor = params.cursor;

    let mut conn = pool.get().await
        .map_err(error::ErrorInternalServerError)?;

    let mut query = dispute_party::table
        .filter(dispute_party::party.eq(&address))
        .inner_join(dispute::table.inner_join(court::table))
        .filter(dispute::dispute_status.lt(DISPUTE_STATUS_COMPLETED))
        .order(dispute::checkpoint_timestamp_ms.desc())
        .into_boxed();

    if let Some(cursor) = cursor {
        query = query.filter(dispute::checkpoint_timestamp_ms.lt(cursor));
    }

    let result: Vec<(String, DisputeDetailsResponse)> = query
        .limit(limit + 1)
        .select((
            court::name,
            DisputeDetailsResponse::as_select(),
        ))
        .load::<(String, DisputeDetailsResponse)>(&mut conn)
        .await
        .map_err(error::ErrorInternalServerError)?;

    let has_more = result.len() > limit as usize;

    let resolved_disputes: Vec<DisputeOverviewResponse> = result
        .into_iter()
        .map(|(court_name, dispute_details)| DisputeOverviewResponse::from(court_name, dispute_details))
        .take(limit as usize)
        .collect();

    let next_cursor = if has_more {
        resolved_disputes
        .last()
        .map(|d| d.checkpoint_timestamp_ms)
    } else {
        None
    };

    Ok(HttpResponse::Ok().json(PaginatedDisputesResponse { 
        disputes: resolved_disputes, 
        cursor: next_cursor,
    }))
}

#[get("/resolved_party_disputes/{address}")]
async fn get_resolved_party_disputes_by_address(
    address: web::Path<String>,
    params: web::Query<DisputesQuery>,
    pool: web::Data<Pool<AsyncPgConnection>>,
) -> actix_web::Result<impl Responder> {
    let address = address.into_inner();

    // Pagination
    let limit = params.limit.unwrap_or(10).min(10);
    let cursor = params.cursor;

    let mut conn = pool.get().await
        .map_err(error::ErrorInternalServerError)?;

    let mut query = dispute_party::table
        .filter(dispute_party::party.eq(&address))
        .inner_join(dispute::table.inner_join(court::table))
        .filter(dispute::dispute_status.ge(DISPUTE_STATUS_COMPLETED))
        .order(dispute::checkpoint_timestamp_ms.desc())
        .into_boxed();

    if let Some(cursor) = cursor {
        query = query.filter(dispute::checkpoint_timestamp_ms.lt(cursor));
    }

    let result: Vec<(String, DisputeDetailsResponse)> = query
        .limit(limit + 1)
        .select((
            court::name,
            DisputeDetailsResponse::as_select(),
        ))
        .load::<(String, DisputeDetailsResponse)>(&mut conn)
        .await
        .map_err(error::ErrorInternalServerError)?;

    let has_more = result.len() > limit as usize;

    let resolved_disputes: Vec<DisputeOverviewResponse> = result
        .into_iter()
        .map(|(court_name, dispute_details)| DisputeOverviewResponse::from(court_name, dispute_details))
        .take(limit as usize)
        .collect();

    let next_cursor = if has_more {
        resolved_disputes
        .last()
        .map(|d| d.checkpoint_timestamp_ms)
    } else {
        None
    };

    Ok(HttpResponse::Ok().json(PaginatedDisputesResponse { 
        disputes: resolved_disputes, 
        cursor: next_cursor,
    }))
}

#[get("/party_stats/{address}")]
async fn get_party_stats_by_address(
    address: web::Path<String>,
    pool: web::Data<Pool<AsyncPgConnection>>,
) -> actix_web::Result<impl Responder> {
    let address = address.into_inner();

    let mut conn = pool.get().await
        .map_err(error::ErrorInternalServerError)?;

    let party_stats: PartyStatsResponse = party_stats::table
        .find(&address)
        .select(PartyStatsResponse::as_select())
        .first(&mut conn)
        .await
        .map_err(|e_type| {
            match e_type {
                diesel::result::Error::NotFound => error::ErrorNotFound(e_type),
                _ => error::ErrorInternalServerError(e_type),
            }
        })?;

    Ok(HttpResponse::Ok().json(party_stats))
}

#[get("/dispute/{dispute_id}")]
async fn get_dispute_by_id(
    dispute_id: web::Path<String>,
    pool: web::Data<Pool<AsyncPgConnection>>,
) -> actix_web::Result<impl Responder> {
    let dispute_id = dispute_id.into_inner();

    let mut conn = pool.get().await
        .map_err(error::ErrorInternalServerError)?;

    let (dispute, court_name) = dispute::table
        .find(&dispute_id)
        .inner_join(court::table)
        .select((
            DisputeOutput::as_select(),
            court::name,
        ))
        .first::<(DisputeOutput, String)>(&mut conn)
        .await
        .map_err(|e_type| {
            match e_type {
                diesel::result::Error::NotFound => error::ErrorNotFound(e_type),
                _ => error::ErrorInternalServerError(e_type),
            }
        })?;

    let evidence: Vec<EvidenceOutput> = Evidence::belonging_to(&dispute)
        .select(EvidenceOutput::as_select())
        .load(&mut conn)
        .await
        .map_err(error::ErrorInternalServerError)?;

    let res = DisputeResponse::from(dispute, court_name, evidence);

    Ok(HttpResponse::Ok().json(res))
}