module nivra::court;

use sui::versioned::Versioned;
use nivra::constants::current_version;
use nivra::court_registry::NivraAdminCap;

const EWrongVersion: u64 = 1;
const ENotUpgrade: u64 = 2;

public struct Court has key {
    id: UID,
    inner: Versioned,
}

public struct CourtInner has store {

}

entry fun migrate(self: &mut Court, _cap: &NivraAdminCap) {
    assert!(self.inner.version() < current_version(), ENotUpgrade);
    let (inner, cap) = self.inner.remove_value_for_upgrade<CourtInner>();
    self.inner.upgrade(current_version(), inner, cap);
}

public(package) fun load_inner_mut(self: &mut Court): &mut CourtInner {
    assert!(self.inner.version() == current_version(), EWrongVersion);
    self.inner.load_value_mut()
}