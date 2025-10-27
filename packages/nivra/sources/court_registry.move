// © 2025 Nivra Labs Ltd.

/// # Court Registry Module 
/// 
/// The `court_registry` module manages all registered courts within the Nivra protocol.  
/// It maintains metadata, version control, and administrative capabilities for managing
/// and upgrading court-related data structures.
module nivra::court_registry;

// === Imports ===
use nivra::constants::current_version;
use std::ascii::String;
use sui::{
    table::{Self, Table},
    url::{Url, new_unsafe},
    versioned::{Self, Versioned}
};

// === Errors ===
const EWrongVersion: u64 = 1;
const ENotUpgrade: u64 = 2;
const ECourtAlreadyExists: u64 = 3;

// === Structs ===

/// ## `NivraAdminCap`
///
/// Capability granting administrative privileges for managing the Nivra system.
/// Holders of this capability can perform restricted administrative actions
/// such as updating treasury addresses or performing migrations.
public struct NivraAdminCap has key, store {
    id: UID,
}

/// ## `Metadata`
///
/// Represents metadata associated with a court.
///
/// ### Fields
/// - `category`: Category or classification of the court.
/// - `name`: Human-readable name of the court.
/// - `icon`: Optional URL representing the court’s icon.
/// - `description`: Text description providing details about the court.
/// - `skills`: List of required skills for jurors.
/// - `min_stake`: Minimum stake (in NVR) required to participate.
/// - `reward`: Expected reward (in SUI) for submitting a coherent vote.
public struct Metadata has copy, drop, store {
    category: String,            
    name: String,                
    icon: Option<Url>,           
    description: String,         
    skills: vector<String>,  
    min_stake: u64,          
    reward: u64,
    // TODO: Redesign reward logic for flexibility
}

/// ## `CourtRegistry`
///
/// Root object storing the versioned court registry data.
/// Wrapped in a `Versioned` container for safe upgrades.
public struct CourtRegistry has key {
    id: UID,
    inner: Versioned,
}


/// ## `CourtRegistryInner`
///
/// Internal structure storing registry data, including treasury address and court metadata.
/// This structure is stored inside a `Versioned` wrapper to support package migrations.
public struct CourtRegistryInner has store {
    treasury_address: address,
    courts: Table<ID, Metadata>,
}

// === View Functions ===

/// Returns the current treasury address associated with the court registry.
///
/// ### Parameters
/// - `self`: Reference to the `CourtRegistry`.
///
/// ### Returns
/// - The treasury `address`.
public fun treasury_address(self: &CourtRegistry): address {
    self.load_inner().treasury_address
}

// === Admin Functions ===

/// Updates the root treasury address for the registry.
///
/// This only updates the **registry-level** treasury address.  
/// Each individual court must be updated separately using
/// a dedicated court update function.
///
/// ### Parameters
/// - `self`: Mutable reference to the `CourtRegistry`.
/// - `treasury_address`: The new treasury address.
/// - `_cap`: Reference to the `NivraAdminCap` proving admin privileges.
public fun set_treasury_address(self: &mut CourtRegistry, treasury_address: address, _cap: &NivraAdminCap) {
    let self = self.load_inner_mut();
    self.treasury_address = treasury_address;
}

/// Migrates the court registry to the latest package version.
///
/// This function upgrades only the **registry object**.
/// Each court must be migrated individually.
///
/// ### Parameters
/// - `self`: Mutable reference to the `CourtRegistry`.
/// - `_cap`: Reference to the `NivraAdminCap` proving admin privileges.
///
/// ### Aborts
/// - `ENotUpgrade`: If the registry is already at the current version.
entry fun migrate(self: &mut CourtRegistry, _cap: &NivraAdminCap) {
    assert!(self.inner.version() < current_version(), ENotUpgrade);
    let (inner, cap) = self.inner.remove_value_for_upgrade<CourtRegistryInner>();
    self.inner.upgrade(current_version(), inner, cap);
}

// === Package Functions ===

/// Registers a new court in the registry.
///
/// ### Parameters
/// - `self`: Mutable reference to the `CourtRegistry`.
/// - `court_id`: Unique ID of the court.
/// - `metadata`: Metadata associated with the new court.
///
/// ### Aborts
/// - `ECourtAlreadyExists`: If a court with the same ID already exists.
public(package) fun register_court(self: &mut CourtRegistry, court_id: ID, metadata: Metadata) {
    let self = self.load_inner_mut();
    assert!(!self.courts.contains(court_id), ECourtAlreadyExists);
    self.courts.add(court_id, metadata);
}

/// Creates a new `Metadata` instance for a court.
///
/// ### Parameters
/// - `category`: Category or classification of the court.
/// - `name`: Human-readable court name.
/// - `icon`: Optional URL string representing the court’s icon.
/// - `description`: Court description.
/// - `skills`: List of required skills.
/// - `min_stake`: Minimum stake in NVR.
/// - `reward`: Expected reward in SUI.
///
/// ### Returns
/// - A fully constructed `Metadata` instance.
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

/// Loads a mutable reference to the inner registry data.
///
/// ### Parameters
/// - `self`: Mutable reference to the `CourtRegistry`.
///
/// ### Returns
/// - Mutable reference to the `CourtRegistryInner`.
///
/// ### Aborts
/// - `EWrongVersion`: If the registry version does not match the current package version.
public(package) fun load_inner_mut(self: &mut CourtRegistry): &mut CourtRegistryInner {
    assert!(self.inner.version() == current_version(), EWrongVersion);
    self.inner.load_value_mut()
}

/// Loads an immutable reference to the inner registry data.
///
/// ### Parameters
/// - `self`: Reference to the `CourtRegistry`.
///
/// ### Returns
/// - Immutable reference to the `CourtRegistryInner`.
///
/// ### Aborts
/// - `EWrongVersion`: If the registry version does not match the current package version.
public(package) fun load_inner(self: &CourtRegistry): &CourtRegistryInner {
    assert!(self.inner.version() == current_version(), EWrongVersion);
    self.inner.load_value()
}

// === Private Functions ===

// Initializes the court registry and the Nivra admin capability.
//
// This internal function:
// - Creates a new `CourtRegistry` object with the caller as the initial treasury owner.
// - Wraps the registry in a `Versioned` container for future upgrades.
// - Mints and transfers a `NivraAdminCap` to the transaction sender.
fun init(ctx: &mut TxContext) {
    let court_registry_inner = CourtRegistryInner {
        treasury_address: ctx.sender(),
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

// === Test Functions ===

/// Creates a new `NivraAdminCap` for testing purposes only.
///
/// ### Parameters
/// - `ctx`: Mutable reference to the transaction context.
///
/// ### Returns
/// - A newly created `NivraAdminCap` instance.
#[test_only]
public fun get_admin_cap_for_testing(ctx: &mut TxContext): NivraAdminCap {
    NivraAdminCap { id: object::new(ctx) }
}