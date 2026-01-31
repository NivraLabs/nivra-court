// © 2026 Nivra Labs Ltd.

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
const MAX_ADMIN_CAPS: u64 = 100;

// === Errors ===
const EWrongVersion: u64 = 1;
const ENotUpgrade: u64 = 2;
const EAdminCapBlacklisted: u64 = 3;
const ECannotDisableCurrentVersion: u64 = 4;
const EVersionNotEnabled: u64 = 5;
const ENoPrivileges: u64 = 6;
const ETooManyAdminCaps: u64 = 7;

// === Structs ===
public struct NivraAdminCap has key, store {
    id: UID,
}

public struct CourtMetadata has copy, drop, store {
    category: String,            
    name: String,                         
    description: String,         
    skills: String,
}

public struct CourtRegistry has key {
    id: UID,
    inner: Versioned,
}

public struct CourtRegistryInner has store {
    admin_whitelist: VecMap<ID, u64>,
    allowed_versions: VecSet<u64>,
    courts: Table<ID, CourtMetadata>,
    treasury_address: address,
}

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
public fun treasury_address(self: &CourtRegistry): address {
    self.load_inner().treasury_address
}

public fun allowed_versions(self: &CourtRegistry): VecSet<u64> {
    let self = self.load_inner();

    self.allowed_versions
}

// === Admin Functions ===
/// Validates a `NivraAdminCap` and returns its associated privilege level.
public fun validate_admin_privileges(
    self: &CourtRegistry, 
    cap: &NivraAdminCap
): u64 {
    let self: &CourtRegistryInner = self.inner.load_value();

    assert!(
        self.admin_whitelist.contains(&object::id(cap)), 
        EAdminCapBlacklisted
    );

    *self.admin_whitelist.get(&object::id(cap))
}

/// Mints a new `NivraAdminCap` and transfers it to the specified receiver.
///
/// The newly minted admin capability is assigned a strictly lower privilege
/// than the caller by default (i.e., `privilege_level + 1`).
public fun mint_admin_cap(
    self: &mut CourtRegistry, 
    cap: &NivraAdminCap, 
    receiver: address, 
    ctx: &mut TxContext
) {
    let privilege_level = self.validate_admin_privileges(cap);
    let self = self.load_inner_mut();

    assert!(self.admin_whitelist.length() < MAX_ADMIN_CAPS, ETooManyAdminCaps);

    let new_admin_cap = NivraAdminCap {
        id: object::new(ctx),
    };

    self.admin_whitelist.insert(
        object::id(&new_admin_cap), 
        privilege_level + 1
    );
    transfer::public_transfer(new_admin_cap, receiver);
}

/// Revokes administrative privileges associated with a target admin capability.
public fun blacklist_admin_cap(
    self: &mut CourtRegistry, 
    cap: &NivraAdminCap, 
    target_cap: ID
) {
    let privilege_level = self.validate_admin_privileges(cap);
    let self = self.load_inner_mut();
    let target_privilege_level = *self.admin_whitelist.get(&target_cap);

    assert!(privilege_level < target_privilege_level, ENoPrivileges);
    self.admin_whitelist.remove(&target_cap);
}

/// Blacklists admin capabilities above a specified privilege threshold.
/// (i.e., `privilege_threshold` = 2, will purge caps at levels 3, 4, 5 ...)
public fun purge_admin_caps(
    self: &mut CourtRegistry, 
    cap: &NivraAdminCap, 
    privilege_threshold: u64
) {
    let privilege_level = self.validate_admin_privileges(cap);
    let self = self.load_inner_mut();

    assert!(privilege_level <= privilege_threshold, ENoPrivileges);

    let mut purged_admin_whitelist: VecMap<ID, u64> = vec_map::empty();
    let mut i = 0;

    while (i < self.admin_whitelist.length()) {
        let (cap_id, cap_privilege) = self.admin_whitelist
        .get_entry_by_idx(i);

        if (*cap_privilege <= privilege_threshold) {
            purged_admin_whitelist.insert(*cap_id, *cap_privilege);
        };

        i = i + 1;
    };

    self.admin_whitelist = purged_admin_whitelist;
}

/// Updates the Nivra treasury address.
public fun set_treasury_address(
    self: &mut CourtRegistry, 
    cap: &NivraAdminCap, 
    treasury_address: address
) {
    let privilege_level = self.validate_admin_privileges(cap);

    assert!(privilege_level == ROOT_PRIVILEGE, ENoPrivileges);
    let self = self.load_inner_mut();
    self.treasury_address = treasury_address;
}

public fun change_court_metadata(
    self: &mut CourtRegistry, 
    cap: &NivraAdminCap,
    court_id: ID,
    category: String,
    name: String,
    description: String,
    skills: String,
) {
    self.validate_admin_privileges(cap);

    let self = self.load_inner_mut();
    let metadata = self.courts.borrow_mut(court_id);
    metadata.category = category;
    metadata.name = name;
    metadata.description = description;
    metadata.skills = skills;
}

/// Enables a package version.
public fun enable_version(
    self: &mut CourtRegistry, 
    cap: &NivraAdminCap, 
    version: u64
) {
    self.validate_admin_privileges(cap);

    let self: &mut CourtRegistryInner = self.inner.load_value_mut();
    assert!(!self.allowed_versions.contains(&version), ENotUpgrade);
    self.allowed_versions.insert(version);
}

/// Disables a previously enabled package version.
public fun disable_version(
    self: &mut CourtRegistry, 
    cap: &NivraAdminCap, 
    version: u64
) {
    self.validate_admin_privileges(cap);

    let self: &mut CourtRegistryInner = self.inner.load_value_mut();
    assert!(version != current_version(), ECannotDisableCurrentVersion);
    assert!(self.allowed_versions.contains(&version), EVersionNotEnabled);
    self.allowed_versions.remove(&version);
}

// === Package Functions ===
/// Registers a new court in the court registry. 
public(package) fun register_court(
    self: &mut CourtRegistry, 
    court_id: ID, 
    metadata: CourtMetadata
) {
    let self = self.load_inner_mut();
    self.courts.add(court_id, metadata);
}

/// Unregisters a court from the court registry.
public(package) fun unregister_court(self: &mut CourtRegistry, court_id: ID) {
    let self = self.load_inner_mut();
    self.courts.remove(court_id);
}

/// Creates metadata for a court.
public(package) fun create_metadata(
    category: String,
    name: String,
    description: String,
    skills: String,
): CourtMetadata {
    CourtMetadata {
        category,
        name,
        description,
        skills,
    }
}

public(package) fun load_inner_mut(
    self: &mut CourtRegistry
): &mut CourtRegistryInner {
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

// === Test Functions ===
#[test_only]
public fun get_root_privileges_for_testing(
    ctx: &mut TxContext
): (CourtRegistry, NivraAdminCap) {
    let admin = NivraAdminCap { id: object::new(ctx) };

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

    (court_registry, admin)
}

#[test_only]
public fun destroy_admin_cap_for_testing(
    admin_cap: NivraAdminCap,
) {
    let NivraAdminCap {
        id,
    } = admin_cap;

    id.delete();
}

#[test_only]
public fun destroy_court_registry_for_testing(
    court_registry: CourtRegistry
) {
    let CourtRegistry {
        id,
        inner,
    } = court_registry;

    id.delete();
    let court_registry_inner: CourtRegistryInner = inner.destroy();

    let CourtRegistryInner {
        admin_whitelist: _,
        allowed_versions: _,
        courts,
        treasury_address: _,
    } = court_registry_inner;

    courts.drop();
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun admin_whitelist(self: &CourtRegistry): VecMap<ID, u64> {
    let self = self.load_inner();
    self.admin_whitelist
}

#[test_only]
public fun courts(self: &mut CourtRegistry): &mut Table<ID, CourtMetadata> {
    let self = self.load_inner_mut();
    &mut self.courts
}

#[test_only]
public fun skills(self: &CourtMetadata): String {
    self.skills
}

#[test_only]
public fun category(self: &CourtMetadata): String {
    self.category
}

#[test_only]
public fun name(self: &CourtMetadata): String {
    self.name
}

#[test_only]
public fun description(self: &CourtMetadata): String {
    self.description
}