/// Oversimplified example of a marketplace.
/// This module exists only so that escrows can be fetched directly
/// from on-chain data by the front end without indexer.
module marketplace::marketplace;

// === Constants ===
const MAX_LISTINGS: u64 = 10;

// === Errors ===
const EMarketplaceFull: u64 = 1;
const EListingNotFound: u64 = 2;

// === Structs ===
public struct MarketplaceAdminCap has key, store {
    id: UID,
}

public struct Marketplace has key {
    id: UID,
    listings: vector<ID>,
}

fun init(ctx: &mut TxContext) {
    let admin_cap = MarketplaceAdminCap {
        id: object::new(ctx),
    };

    let marketplace = Marketplace {
        id: object::new(ctx),
        listings: vector[],
    };

    transfer::public_transfer(admin_cap, ctx.sender());
    transfer::share_object(marketplace);
}

// === Admin Functions ===
public fun admin_remove_listing(
    marketplace: &mut Marketplace, 
    listing: ID,
    _cap: &MarketplaceAdminCap,
) {
    remove_listing(marketplace, listing);
}

// === Package Functions ===
public(package) fun new_listing(marketplace: &mut Marketplace, listing: ID) {
    assert!(marketplace.listings.length() < MAX_LISTINGS, EMarketplaceFull);
    marketplace.listings.push_back(listing);
}

public(package) fun remove_listing(marketplace: &mut Marketplace, listing: ID) {
    let idx = marketplace.listings.find_index!(|l| l == listing);

    assert!(idx.is_some(), EListingNotFound);
    marketplace.listings.remove(idx.destroy_some());
}