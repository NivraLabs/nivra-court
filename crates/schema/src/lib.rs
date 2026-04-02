use diesel_migrations::{EmbeddedMigrations, embed_migrations};

pub mod schema;
pub mod models;
pub mod constants;

pub const MIGRATIONS: EmbeddedMigrations = embed_migrations!("migrations");