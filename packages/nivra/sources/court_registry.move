// © 2025 Nivra Labs Ltd.

/// The Court Registry manages courts, shared configuration, and administrative 
/// privileges within the Nivra protocol.
module nivra::court_registry;

// === Imports ===
use nivra::constants::current_version;
use std::string::String;
use sui::{
    table::{Self, Table},
    vec_map::{Self, VecMap},
    vec_set::{Self, VecSet},
    versioned::{Self, Versioned},
};

// === Constants ===
const ROOT_PRIVILEGE: u64 = 1;

// === Errors ===
const EWrongVersion: u64 = 1;
const ENotUpgrade: u64 = 2;
const EAdminCapBlacklisted: u64 = 3;
const ECannotDisableCurrentVersion: u64 = 4;
const EVersionNotEnabled: u64 = 5;
const ENoPrivileges: u64 = 6;

// === Structs ===
/// Administrative capability for the Nivra protocol.
/// 
/// This capability authorizes calls to privileged (admin-only) functions.
public struct NivraAdminCap has key, store {
    id: UID,
}

/// Metadata describing a court.
///
/// This struct contains user-facing information and participation requirements.
///
/// Fields:
/// - `category`: The category under which the court is classified.
/// - `name`: The court’s display name.
/// - `description`: A description of the court’s scope, topics, and governing rules.
/// - `skills`: A description of the skills required to participate.
/// - `min_stake`: The minimum NVR stake required for participation.
public struct CourtMetadata has copy, drop, store {
    category: String,            
    name: String,                         
    description: String,         
    skills: String,  
    min_stake: u64,
}

/// Versioned wrapper for the Court Registry.
///
/// This struct enables safe upgrades of the court registry by encapsulating
/// versioned internal state.
public struct CourtRegistry has key {
    id: UID,
    inner: Versioned,
}

/// Internal state of the Court Registry.
///
/// Fields:
/// - `admin_whitelist`: A map of active Nivra admin cap IDs and their
///   privilege level (lower values indicate higher privilege).
/// - `allowed_versions`: A list of allowed nivra package versions.
/// - `courts`: A table mapping court IDs to their associated metadata.
/// - `treasury_address`: The Nivra treasury address that receives collected fees.
public struct CourtRegistryInner has store {
    admin_whitelist: VecMap<ID, u64>,
    allowed_versions: VecSet<u64>,
    courts: Table<ID, CourtMetadata>,
    treasury_address: address,
}

/// Initialization of the court registry and the root admin cap.
fun init(ctx: &mut TxContext) {
    let admin = NivraAdminCap { 
        id: object::new(ctx),
    };

    let court_registry_inner = CourtRegistryInner {
        admin_whitelist: vec_map::from_keys_values(
            vector::singleton(object::id(&admin)), 
            vector::singleton(ROOT_PRIVILEGE)
        ),
        allowed_versions: vec_set::singleton(current_version()),
        courts: table::new<ID, CourtMetadata>(ctx),
        treasury_address: ctx.sender(),
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
    transfer::public_transfer(admin, ctx.sender());
}

// === View Functions ===
/// Nivra treasury address.
public fun treasury_address(self: &CourtRegistry): address {
    self.load_inner().treasury_address
}

// === Admin Functions ===
/// Validates a `NivraAdminCap` and returns its associated privilege level.
///
/// Aborts if:
/// - the admin capability is not present in the admin whitelist.
public fun validate_admin_privileges(self: &mut CourtRegistry, cap: &NivraAdminCap): u64 {
    let self: &CourtRegistryInner = self.inner.load_value();

    assert!(self.admin_whitelist.contains(&object::id(cap)), EAdminCapBlacklisted);
    *self.admin_whitelist.get(&object::id(cap))
}

/// Mints a new `NivraAdminCap` and transfers it to the specified receiver.
///
/// The newly minted admin capability is assigned a strictly lower privilege
/// than the caller by default (i.e., `privilege_level + 1`).
/// 
/// Aborts if:
/// - The caller’s admin capability is not authorized
public fun mint_admin_cap(
    self: &mut CourtRegistry, 
    cap: &NivraAdminCap, 
    receiver: address, 
    ctx: &mut TxContext
) {
    let privilege_level = self.validate_admin_privileges(cap);
    let self = self.load_inner_mut();
    let new_admin_cap = NivraAdminCap {
        id: object::new(ctx),
    };

    self.admin_whitelist.insert(object::id(&new_admin_cap), privilege_level + 1);
    transfer::public_transfer(new_admin_cap, receiver);
}

/// Revokes administrative privileges associated with a target admin capability.
///
/// The caller must have strictly higher privilege than the target admin
/// capability in order to blacklist it.
///
/// Aborts if:
/// - The caller’s admin capability is not authorized
/// - The caller does not have sufficient privilege to revoke the target
public fun blacklist_admin_cap(self: &mut CourtRegistry, cap: &NivraAdminCap, target_cap: ID) {
    let privilege_level = self.validate_admin_privileges(cap);
    let self = self.load_inner_mut();
    let target_privilege_level = *self.admin_whitelist.get(&target_cap);

    assert!(privilege_level < target_privilege_level, ENoPrivileges);
    self.admin_whitelist.remove(&target_cap);
}

/// Blacklists admin capabilities above a specified privilege threshold.
/// (i.e., `privilege_threshold` = 2, will purge caps at levels 3, 4, 5 ...)
/// 
/// The caller must have privilege equal to or higher than `privilege_threshold`
/// (i.e., `privilege_level <= privilege_threshold`).
///
/// Aborts if:
/// - The caller’s admin capability is not authorized
/// - The caller does not have sufficient privilege to perform the purge
public fun purge_admin_caps(self: &mut CourtRegistry, cap: &NivraAdminCap, privilege_threshold: u64) {
    let privilege_level = self.validate_admin_privileges(cap);
    let self = self.load_inner_mut();

    assert!(privilege_level <= privilege_threshold, ENoPrivileges);

    let mut purged_admin_whitelist: VecMap<ID, u64> = vec_map::empty();
    let mut i = 0;

    while (i < self.admin_whitelist.length()) {
        let (cap_id, cap_privilege) = self.admin_whitelist.get_entry_by_idx(i);

        if (*cap_privilege <= privilege_threshold) {
            purged_admin_whitelist.insert(*cap_id, *cap_privilege);
        };

        i = i + 1;
    };

    self.admin_whitelist = purged_admin_whitelist;
}

/// Updates the Nivra treasury address.
public fun set_treasury_address(self: &mut CourtRegistry, cap: &NivraAdminCap, treasury_address: address) {
    self.validate_admin_privileges(cap);

    let self = self.load_inner_mut();
    self.treasury_address = treasury_address;
}

/// Enables a package version.
///
/// Aborts if:
/// - The caller’s admin capability is not authorized
/// - the version is already enabled.
public fun enable_version(self: &mut CourtRegistry, cap: &NivraAdminCap, version: u64) {
    self.validate_admin_privileges(cap);

    let self: &mut CourtRegistryInner = self.inner.load_value_mut();
    assert!(!self.allowed_versions.contains(&version), ENotUpgrade);
    self.allowed_versions.insert(version);
}

/// Disables a previously enabled package version.
///
/// Aborts if:
/// - The caller’s admin capability is not authorized
/// - The version is the currently active version
/// - The version is not enabled
public fun disable_version(self: &mut CourtRegistry, cap: &NivraAdminCap, version: u64) {
    self.validate_admin_privileges(cap);

    let self: &mut CourtRegistryInner = self.inner.load_value_mut();
    assert!(version != current_version(), ECannotDisableCurrentVersion);
    assert!(self.allowed_versions.contains(&version), EVersionNotEnabled);
    self.allowed_versions.remove(&version);
}

// === Package Functions ===
/// Register a new court in the court registry. 
public(package) fun register_court(self: &mut CourtRegistry, court_id: ID, metadata: CourtMetadata) {
    let self = self.load_inner_mut();
    self.courts.add(court_id, metadata);
}

/// Unregister court from the court registry.
public(package) fun unregister_court(self: &mut CourtRegistry, court_id: ID) {
    let self = self.load_inner_mut();
    self.courts.remove(court_id);
}

// Create metadata for a court.
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
    let inner: &mut CourtRegistryInner = self.inner.load_value_mut();
    let package_version = current_version();
    assert!(inner.allowed_versions.contains(&package_version), EWrongVersion);

    inner
}

public(package) fun load_inner(self: &CourtRegistry): &CourtRegistryInner {
    let inner: &CourtRegistryInner = self.inner.load_value();
    let package_version = current_version();
    assert!(inner.allowed_versions.contains(&package_version), EWrongVersion);

    inner
}