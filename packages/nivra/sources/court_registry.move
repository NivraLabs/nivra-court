module nivra::court_registry;

use sui::versioned::{Self, Versioned};
use nivra::constants::current_version;

const EWrongVersion: u64 = 1;
const ENotUpgrade: u64 = 2;

public struct NivraAdminCap has key, store {
    id: UID,
}

public struct CourtRegistry has key {
    id: UID,
    inner: Versioned,
}

public struct CourtRegistryInner has store {

}

fun init(ctx: &mut TxContext) {
    let court_registry_inner = CourtRegistryInner {

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

public(package) fun load_inner_mut(self: &mut CourtRegistry): &mut CourtRegistryInner {
    assert!(self.inner.version() == current_version(), EWrongVersion);
    self.inner.load_value_mut()
}

#[test_only]
public fun get_admin_cap_for_testing(ctx: &mut TxContext): NivraAdminCap {
    NivraAdminCap { id: object::new(ctx) }
}