// © 2025 Nivra Labs Ltd.

/// Court registry manages all registered courts within the Nivra protocol.
module nivra::court_registry;

// === Imports ===
use nivra::constants::current_version;
use std::string::String;
use sui::{
    table::{Self, Table},
    versioned::{Self, Versioned}
};

// === Errors ===
const EWrongVersion: u64 = 1;
const ENotUpgrade: u64 = 2;

// === Structs ===
public struct NivraAdminCap has key, store {
    id: UID,
}

public struct CourtMetadata has copy, drop, store {
    category: String,            
    name: String,                         
    description: String,         
    skills: String,  
    min_stake: u64,
}

public struct CourtRegistry has key {
    id: UID,
    inner: Versioned,
}

public struct CourtRegistryInner has store {
    treasury_address: address,
    courts: Table<ID, CourtMetadata>,
}

// === View Functions ===
public fun treasury_address(self: &CourtRegistry): address {
    self.load_inner().treasury_address
}

// === Admin Functions ===
public fun set_treasury_address(self: &mut CourtRegistry, _cap: &NivraAdminCap, treasury_address: address) {
    let self = self.load_inner_mut();
    self.treasury_address = treasury_address;
}

entry fun migrate(self: &mut CourtRegistry, _cap: &NivraAdminCap) {
    assert!(self.inner.version() < current_version(), ENotUpgrade);
    let (inner, cap) = self.inner.remove_value_for_upgrade<CourtRegistryInner>();
    self.inner.upgrade(current_version(), inner, cap);
}


// === Package Functions ===
public(package) fun register_court(self: &mut CourtRegistry, court_id: ID, metadata: CourtMetadata) {
    let self = self.load_inner_mut();
    self.courts.add(court_id, metadata);
}

public(package) fun create_metadata(
    category: String,
    name: String,
    description: String,
    skills: String,
    min_stake: u64,
): CourtMetadata {
    CourtMetadata {
        category,
        name,
        description,
        skills,
        min_stake,
    }
}

public(package) fun load_inner_mut(self: &mut CourtRegistry): &mut CourtRegistryInner {
    assert!(self.inner.version() == current_version(), EWrongVersion);
    self.inner.load_value_mut()
}

public(package) fun load_inner(self: &CourtRegistry): &CourtRegistryInner {
    assert!(self.inner.version() == current_version(), EWrongVersion);
    self.inner.load_value()
}

// === Private Functions ===
fun init(ctx: &mut TxContext) {
    let court_registry_inner = CourtRegistryInner {
        treasury_address: ctx.sender(),
        courts: table::new<ID, CourtMetadata>(ctx),
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

// === Test Functions ===
#[test_only]
public fun get_admin_cap_for_testing(ctx: &mut TxContext): NivraAdminCap {
    NivraAdminCap { id: object::new(ctx) }
}