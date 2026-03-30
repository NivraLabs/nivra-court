// © 2026 Nivra Labs Ltd.

module nivra::registry;

// === Imports ===
use sui::vec_set::{Self, VecSet};
use nivra::constants::current_version;
use sui::dynamic_field as df;
use sui::event;
use std::string::String;
use nivra::constants::max_admins;
use nivra::constants::max_courts;
use nivra::constants::max_admin_desc_length;
use nivra::constants::min_vote_threshold;
use sui::clock::Clock;
use nivra::constants::min_vote_decay_ms;
use nivra::constants::reputation_threshold;
use nivra::constants::add_admin_vote;
use nivra::constants::blacklist_admin_vote;
use nivra::constants::change_treasury_vote;
use nivra::constants::change_threshold_vote;

// === Constants ===
// Founder members.
const NIVRA_PROTOCOL: address = 
    @0x78b21978658505237a465ef20a4cf3ce2d418fda9cfb3ce4a0e4be7f9a16187d;
const RASMUS: address = 
    @0x1;
const ELMERI: address = 
    @0x0eb4bdaf7b57fc5a7cdaf88c3187c4289ed5f2794e8ba87de82a05c859cebbc9;
const PATRIK: address = 
    @0x3;
const LUKA: address = 
    @0x4;

// === Errors ===
const EWrongVersion: u64 = 1;
const EVersionAlreadyEnabled: u64 = 2;
const ECannotDisableCurrentVersion: u64 = 3;
const EVersionNotEnabled: u64 = 4;
const EAdminBlacklisted: u64 = 5;
const ETooManyAdmins: u64 = 6;
const ECourtAlreadyExists: u64 = 7;
const ECourtDoesNotExist: u64 = 8;
const ETooManyCourts: u64 = 9;
const EVoteDescTooLong: u64 = 10;
const EAlreadySigned: u64 = 11;
const ENotEnoughSignatures: u64 = 12;
const EVoteAlreadyEnforced: u64 = 13;
const ETreasuryAlreadySet: u64 = 14;
const ETreasuryAddressNotAdmin: u64 = 15;
const EAdminCountUnderVoteThreshold: u64 = 16;
const EUserAlreadyAdmin: u64 = 17;
const EThresholdTooLow: u64 = 18;
const EThresholdTooHigh: u64 = 19;
const EThresholdNotDecayedYet: u64 = 20;

// === Structs ===
public struct Registry has key, store {
    id: UID,
    allowed_versions: VecSet<u64>,
    courts: VecSet<ID>,
    treasury_address: address,
    admin_whitelist: VecSet<address>,
    vote_threshold: u64,
    last_vote_timestamp: u64,
}

public struct Nivster has store {
    cases_won: u64,
    cases_total: u64,
    rewards_total_nvr: u128,
    slashes_total_nvr: u128,
    rewards_total_sui: u128,
}

public struct AdminVote has key {
    id: UID,
    admin: address,
    description: String,
    signatures: VecSet<address>,
    enforced: bool,
}

public struct AdminBlacklistVote has key {
    id: UID,
    admin: address,
    description: String,
    signatures: VecSet<address>,
    enforced: bool,
}

public struct TreasuryUpdateVote has key {
    id: UID,
    treasury: address,
    description: String,
    signatures: VecSet<address>,
    enforced: bool,
}

public struct ThresholdUpdateVote has key {
    id: UID,
    threshold: u64,
    description: String,
    signatures: VecSet<address>,
    enforced: bool,
}

// === Events ===
public struct AdminVoteEvent has copy, drop {
    vote: ID,
    vote_type: u8,
}

public struct AdminVoteFinalizedEvent has copy, drop {
    vote: ID,
}

// === Public Functions ===
fun init(ctx: &mut TxContext) {
    let admin_whitelist = vector[
        NIVRA_PROTOCOL, 
        RASMUS,
        ELMERI,
        PATRIK,
        LUKA,
    ];

    let registry = Registry {
        id: object::new(ctx),
        allowed_versions: vec_set::singleton(current_version()),
        courts: vec_set::empty(),
        treasury_address: NIVRA_PROTOCOL,
        admin_whitelist: vec_set::from_keys(admin_whitelist),
        vote_threshold: min_vote_threshold(),
        last_vote_timestamp: 0,
    };

    transfer::share_object(registry);
}

public fun validate_version(registry: &Registry) {
    assert!(
        registry.allowed_versions.contains(&current_version()), 
        EWrongVersion
    );
}

public fun nivster_reputation(registry: &Registry, nivster: address): u64 {
    if (!df::exists_(&registry.id, nivster)) {
        return 0
    };

    let nivster: &Nivster = df::borrow(&registry.id, nivster);

    if (nivster.cases_total >= reputation_threshold()) {
        nivster.cases_won * 100 / nivster.cases_total
    } else {
        0
    }
}

// === View Functions ===
public fun treasury_address(registry: &Registry): address {
    registry.validate_version();
    registry.treasury_address
}

public fun allowed_versions(registry: &Registry): VecSet<u64> {
    registry.validate_version();
    registry.allowed_versions
}

public fun admins(registry: &Registry): VecSet<address> {
    registry.validate_version();
    registry.admin_whitelist
}

// === Admin Functions ===
public fun validate_admin_privileges(
    registry: &Registry, 
    ctx: &mut TxContext,
) {
    assert!(
        registry.admin_whitelist.contains(&ctx.sender()), 
        EAdminBlacklisted
    );
}

public fun suggest_admin(
    registry: &Registry,
    admin: address,
    description: String,
    ctx: &mut TxContext
) {
    registry.validate_version();
    registry.validate_admin_privileges(ctx);

    assert!(description.length() < max_admin_desc_length(), EVoteDescTooLong);
    assert!(registry.admin_whitelist.length() < max_admins(), ETooManyAdmins);
    assert!(!registry.admin_whitelist.contains(&admin), EUserAlreadyAdmin);

    let vote = AdminVote {
        id: object::new(ctx),
        admin,
        description,
        signatures: vec_set::singleton(ctx.sender()),
        enforced: false,
    };
    let vote_id = object::id(&vote);

    transfer::share_object(vote);

    event::emit(AdminVoteEvent {
        vote: vote_id,
        vote_type: add_admin_vote(),
    });
}

public fun sign_admin_suggestion(
    admin_vote: &mut AdminVote,
    registry: &Registry,
    ctx: &mut TxContext,
) {
    registry.validate_version();
    registry.validate_admin_privileges(ctx);
    assert!(!admin_vote.signatures.contains(&ctx.sender()), EAlreadySigned);
    assert!(!admin_vote.enforced, EVoteAlreadyEnforced);

    admin_vote.signatures.insert(ctx.sender());
}

public fun approve_admin(
    admin_vote: &mut AdminVote,
    registry: &mut Registry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    registry.validate_version();
    registry.validate_admin_privileges(ctx);

    assert!(!admin_vote.enforced, EVoteAlreadyEnforced);
    assert!(registry.admin_whitelist.length() < max_admins(), ETooManyAdmins);
    assert!(
        !registry.admin_whitelist.contains(&admin_vote.admin), 
        EUserAlreadyAdmin
    );
    assert!(
        admin_vote.signatures.length() >= registry.vote_threshold,
        ENotEnoughSignatures
    );

    registry.admin_whitelist.insert(admin_vote.admin);
    registry.last_vote_timestamp = clock.timestamp_ms();
    admin_vote.enforced = true;

    event::emit(AdminVoteFinalizedEvent { 
        vote: object::id(admin_vote),
    });
}

public fun suggest_admin_blacklist(
    registry: &Registry, 
    admin: address,
    description: String,
    ctx: &mut TxContext,
) {
    registry.validate_version();
    registry.validate_admin_privileges(ctx);

    assert!(description.length() < max_admin_desc_length(), EVoteDescTooLong);
    assert!(registry.admin_whitelist.contains(&admin), EAdminBlacklisted);
    assert!(
        registry.admin_whitelist.length() > registry.vote_threshold, 
        EAdminCountUnderVoteThreshold
    );

    let vote = AdminBlacklistVote {
        id: object::new(ctx),
        admin,
        description,
        signatures: vec_set::singleton(ctx.sender()),
        enforced: false,
    };
    let vote_id = object::id(&vote);

    transfer::share_object(vote);

    event::emit(AdminVoteEvent {
        vote: vote_id,
        vote_type: blacklist_admin_vote(),
    });
}

public fun sign_admin_blacklist_suggestion(
    admin_blacklist_vote: &mut AdminBlacklistVote,
    registry: &Registry,
    ctx: &mut TxContext,
) {
    registry.validate_version();
    registry.validate_admin_privileges(ctx);

    assert!(!admin_blacklist_vote.enforced, EVoteAlreadyEnforced);
    assert!(
        !admin_blacklist_vote.signatures.contains(&ctx.sender()), 
        EAlreadySigned
    );

    admin_blacklist_vote.signatures.insert(ctx.sender());
}

public fun approve_blacklisting(
    admin_blacklist_vote: &mut AdminBlacklistVote,
    registry: &mut Registry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    registry.validate_version();
    registry.validate_admin_privileges(ctx);

    assert!(!admin_blacklist_vote.enforced, EVoteAlreadyEnforced);
    assert!(
        admin_blacklist_vote.signatures.length() >= registry.vote_threshold,
        ENotEnoughSignatures
    );
    assert!(
        registry.admin_whitelist.contains(&admin_blacklist_vote.admin),
        EAdminBlacklisted
    );
    assert!(
        registry.admin_whitelist.length() > registry.vote_threshold, 
        EAdminCountUnderVoteThreshold
    );

    registry.admin_whitelist.remove(&admin_blacklist_vote.admin);
    registry.last_vote_timestamp = clock.timestamp_ms();
    admin_blacklist_vote.enforced = true;

    event::emit(AdminVoteFinalizedEvent { 
        vote: object::id(admin_blacklist_vote),
    });
}

public fun suggest_treasury_update(
    registry: &Registry, 
    treasury_address: address,
    description: String,
    ctx: &mut TxContext,
) {
    registry.validate_version();
    registry.validate_admin_privileges(ctx);
    assert!(description.length() < max_admin_desc_length(), EVoteDescTooLong);
    assert!(registry.treasury_address != treasury_address, ETreasuryAlreadySet);
    assert!(
        registry.admin_whitelist.contains(&treasury_address), 
        ETreasuryAddressNotAdmin
    );

    let vote = TreasuryUpdateVote {
        id: object::new(ctx),
        treasury: treasury_address,
        description,
        signatures: vec_set::singleton(ctx.sender()),
        enforced: false,
    };
    let vote_id = object::id(&vote);

    transfer::share_object(vote);

    event::emit(AdminVoteEvent {
        vote: vote_id,
        vote_type: change_treasury_vote(),
    });
}

public fun sign_treasury_update(
    treasury_update_vote: &mut TreasuryUpdateVote,
    registry: &Registry,
    ctx: &mut TxContext,
) {
    registry.validate_version();
    registry.validate_admin_privileges(ctx);

    assert!(!treasury_update_vote.enforced, EVoteAlreadyEnforced);
    assert!(
        !treasury_update_vote.signatures.contains(&ctx.sender()), 
        EAlreadySigned
    );

    treasury_update_vote.signatures.insert(ctx.sender());
}

public fun approve_treasury_update(
    treasury_update_vote: &mut TreasuryUpdateVote,
    registry: &mut Registry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    registry.validate_version();
    registry.validate_admin_privileges(ctx);

    assert!(!treasury_update_vote.enforced, EVoteAlreadyEnforced);
    assert!(
        treasury_update_vote.signatures.length() >= registry.vote_threshold,
        ENotEnoughSignatures
    );
    assert!(
        registry.admin_whitelist.contains(&treasury_update_vote.treasury), 
        ETreasuryAddressNotAdmin
    );

    registry.treasury_address = treasury_update_vote.treasury;
    registry.last_vote_timestamp = clock.timestamp_ms();
    treasury_update_vote.enforced = true;

    event::emit(AdminVoteFinalizedEvent { 
        vote: object::id(treasury_update_vote),
    });
}

public fun suggest_threshold_update(
    registry: &Registry, 
    threshold: u64,
    description: String,
    ctx: &mut TxContext,
) {
    registry.validate_version();
    registry.validate_admin_privileges(ctx);

    assert!(description.length() < max_admin_desc_length(), EVoteDescTooLong);
    assert!(threshold >= min_vote_threshold(), EThresholdTooLow);
    assert!(
        threshold <= registry.admin_whitelist.length(),
        EThresholdTooHigh
    );

    let vote = ThresholdUpdateVote {
        id: object::new(ctx),
        threshold,
        description,
        signatures: vec_set::singleton(ctx.sender()),
        enforced: false,
    };
    let vote_id = object::id(&vote);

    transfer::share_object(vote);

    event::emit(AdminVoteEvent {
        vote: vote_id,
        vote_type: change_threshold_vote(),
    });
}

public fun sign_threshold_update(
    threshold_update_vote: &mut ThresholdUpdateVote,
    registry: &Registry,
    ctx: &mut TxContext,
) {
    registry.validate_version();
    registry.validate_admin_privileges(ctx);

    assert!(!threshold_update_vote.enforced, EVoteAlreadyEnforced);
    assert!(
        !threshold_update_vote.signatures.contains(&ctx.sender()), 
        EAlreadySigned
    );

    threshold_update_vote.signatures.insert(ctx.sender());
}

public fun approve_theshold_update(
    threshold_update_vote: &mut ThresholdUpdateVote,
    registry: &mut Registry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    registry.validate_version();
    registry.validate_admin_privileges(ctx);

    assert!(!threshold_update_vote.enforced, EVoteAlreadyEnforced);
    assert!(
        threshold_update_vote.signatures.length() >= registry.vote_threshold,
        ENotEnoughSignatures
    );
    assert!(
        threshold_update_vote.threshold >= min_vote_threshold(), 
        EThresholdTooLow
    );
    assert!(
        threshold_update_vote.threshold <= registry.admin_whitelist.length(),
        EThresholdTooHigh
    );

    registry.vote_threshold = threshold_update_vote.threshold;
    registry.last_vote_timestamp = clock.timestamp_ms();
    threshold_update_vote.enforced = true;

    event::emit(AdminVoteFinalizedEvent { 
        vote: object::id(threshold_update_vote),
    })
}

public fun reset_min_threshold(
    registry: &mut Registry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    registry.validate_version();
    registry.validate_admin_privileges(ctx);

    assert!(
        clock.timestamp_ms() - registry.last_vote_timestamp >= min_vote_decay_ms(),
        EThresholdNotDecayedYet
    );

    registry.vote_threshold = min_vote_threshold();
}

/// Enables a package version.
public fun enable_version(
    registry: &mut Registry,  
    version: u64,
    ctx: &mut TxContext,
) {
    registry.validate_admin_privileges(ctx);

    assert!(
        !registry.allowed_versions.contains(&version), 
        EVersionAlreadyEnabled
    );

    registry.allowed_versions.insert(version);
}

/// Disables a previously enabled package version.
public fun disable_version(
    registry: &mut Registry, 
    version: u64,
    ctx: &mut TxContext,
) {
    registry.validate_admin_privileges(ctx);

    assert!(version != current_version(), ECannotDisableCurrentVersion);
    assert!(registry.allowed_versions.contains(&version), EVersionNotEnabled);

    registry.allowed_versions.remove(&version);
}

// === Package Functions ===
/// Registers a new court in the court registry. 
public(package) fun register_court(
    registry: &mut Registry,
    court_id: ID, 
) {
    assert!(!registry.courts.contains(&court_id), ECourtAlreadyExists);
    assert!(registry.courts.length() < max_courts(), ETooManyCourts);

    registry.courts.insert(court_id);
}

/// Unregisters a court from the court registry.
public(package) fun unregister_court(
    registry: &mut Registry, 
    court_id: ID,
) {
    assert!(registry.courts.contains(&court_id), ECourtDoesNotExist);

    registry.courts.remove(&court_id);
}

public(package) fun register_case_lost(
    registry: &mut Registry,
    nivster: address,
    penalty: u64,
) {
    if (!df::exists_(&registry.id, nivster)) {
        df::add(
            &mut registry.id, 
            nivster, 
            Nivster {
                cases_won: 0,
                cases_total: 1,
                rewards_total_nvr: 0,
                slashes_total_nvr: penalty as u128,
                rewards_total_sui: 0,
            }
        );
    } else {
        let stats: &mut Nivster = df::borrow_mut(&mut registry.id, nivster);
        stats.cases_total = stats.cases_total + 1;
        stats.slashes_total_nvr = stats.slashes_total_nvr + (penalty as u128);
    };
}

public(package) fun register_case_won(
    registry: &mut Registry,
    nivster: address,
    reward_nvr: u64,
    reward_sui: u64,
) {
    if (!df::exists_(&registry.id, nivster)) {
        df::add(
            &mut registry.id, 
            nivster, 
            Nivster {
                cases_won: 1,
                cases_total: 1,
                rewards_total_nvr: reward_nvr as u128,
                slashes_total_nvr: 0,
                rewards_total_sui: reward_sui as u128,
            }
        );
    } else {
        let stats: &mut Nivster = df::borrow_mut(&mut registry.id, nivster);
        stats.cases_won = stats.cases_won + 1;
        stats.cases_total = stats.cases_total + 1;
        stats.rewards_total_nvr = stats.rewards_total_nvr + 
            (reward_nvr as u128);
        stats.rewards_total_sui = stats.rewards_total_sui +
            (reward_sui as u128);
    };
}

// === Test Functions ===
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}