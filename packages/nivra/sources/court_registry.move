module nivra::court_registry;

use sui::versioned::{Self, Versioned};
use nivra::constants::current_version;
use sui::table::{Self, Table};
use std::ascii::String;
use sui::url::Url;
use sui::url::new_unsafe;

const EWrongVersion: u64 = 1;
const ENotUpgrade: u64 = 2;
const ECourtAlreadyExists: u64 = 3;

public struct NivraAdminCap has key, store {
    id: UID,
}

public struct Metadata has copy, drop, store {
    category: String,
    name: String,
    icon: Option<Url>,
    description: String,
    skills: vector<String>,
    min_stake: u64, // (NVR)
    reward: u64, // (Sui)
}

public struct CourtRegistry has key {
    id: UID,
    inner: Versioned,
}

public struct CourtRegistryInner has store {
    courts: Table<ID, Metadata>,
}

fun init(ctx: &mut TxContext) {
    let court_registry_inner = CourtRegistryInner {
        courts: table::new<ID, Metadata>(ctx),
    };

    let court_registry = CourtRegistry {
        id: object::new(ctx),
        inner: versioned::create(
            current_version(), 
            court_registry_inner, 
            ctx
        ),
    };

    transfer::share_object(court_registry);

    let admin = NivraAdminCap { 
        id: object::new(ctx),
    };

    transfer::public_transfer(admin, ctx.sender());
}

entry fun migrate(self: &mut CourtRegistry, _cap: &NivraAdminCap) {
    assert!(self.inner.version() < current_version(), ENotUpgrade);
    let (inner, cap) = self.inner.remove_value_for_upgrade<CourtRegistryInner>();
    self.inner.upgrade(current_version(), inner, cap);
}

public(package) fun register_court(self: &mut CourtRegistry, court_id: ID, metadata: Metadata) {
    let self = self.load_inner_mut();
    assert!(!self.courts.contains(court_id), ECourtAlreadyExists);
    self.courts.add(court_id, metadata);
}

public(package) fun create_metadata(
    category: String,
    name: String,
    icon: Option<String>,
    description: String,
    skills: vector<String>,
    min_stake: u64,
    reward: u64,
): Metadata {
    Metadata {
        category,
        name,
        icon: icon.map!(|icon| new_unsafe(icon)),
        description,
        skills,
        min_stake,
        reward,
    }
}

public(package) fun load_inner_mut(self: &mut CourtRegistry): &mut CourtRegistryInner {
    assert!(self.inner.version() == current_version(), EWrongVersion);
    self.inner.load_value_mut()
}

#[test_only]
public fun get_admin_cap_for_testing(ctx: &mut TxContext): NivraAdminCap {
    NivraAdminCap { id: object::new(ctx) }
}