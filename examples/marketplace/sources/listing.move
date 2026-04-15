/// Example of an arbitrable contract with nivra used as a dispute management 
/// system.
module marketplace::listing;

// === Imports ===
use marketplace::marketplace::Marketplace;
use std::string::String;
use sui::url::{Self, Url};
use sui::balance::Balance;
use sui::sui::SUI;
use sui::coin::Coin;
use sui::clock::Clock;
use sui::dynamic_field;
use sui::vec_map;
use nivra::nivra_configuration::{Self, NivraConfiguration};
use nivra::nivra_result::NivraResult;

// === Constants ===
// Nivra config values.
const MAX_APPEALS: u8 = 2;

// Courts that the arbitrable contract can use.
const TESTNET_E_COMMERCE_COURT: address = 
    @0xd2ee7d9646916d1a330a334fae7bbd1688ffa27412c13c1aeed91ad461edea21;
const TESTNET_E_SERVICES_COURT: address =
    @0xeb72b410672fd1e09dbdd267ef937f2eceaef07d6537254ddc6121fcf77286a9;

// Dispute 1 voting options: Order not delivered yet.
const OPTION_FULL_REFUND: vector<u8> = 
    b"Full refund";
const OPTION_BUYER_FAULT: vector<u8> = 
    b"Buyer is at fault (buyer is refunded 70%)";
const OPTION_EXTEND_DELIVERY: vector<u8> = 
    b"Extend delivery time";

// Dispute 2 voting options: Order delivered.
const OPTION_PRODUCT_NOT_AS_DESCRIBED: vector<u8> = 
    b"Product not as described (buyer is refunded fully)";
const OPTION_REQUIRE_REDELIVERY: vector<u8> =
    b"Allow seller to correct the delivery";
const OPTION_PRODUCT_AS_DESCRIBED: vector<u8> = 
    b"Product is as described";

// Listing rules.
const MAX_QUANTITY: u64 = 50;
const MAX_TITLE_LENGTH: u64 = 255;
const MAX_DESCRIPTION_LENGTH: u64 = 2000;
const CASHOUT_PERIOD: u64 = 86_400_000; // 1 Day.

// === Errors ===
const EQuantityLimitExceeded: u64 = 1;
const ETitleLimitExceeded: u64 = 2;
const EDescriptionLimitExceeded: u64 = 3;
const ENotEnoughStock: u64 = 4;
const EInvalidPaymentAmount: u64 = 5;
const EOrderNotFound: u64 = 6;
const EOrderNotAcceptingDelivery: u64 = 7;
const EUserNotSeller: u64 = 8;
const EOrderNotDelivered: u64 = 9;
const ECashoutPeriodNotFinished: u64 = 10;
const EUserNotDisputeParty: u64 = 11;
const ENotDisputed: u64 = 12;
const ESelfPurchase: u64 = 13;

// === Structs ===
public struct Listing has key {
    id: UID,
    title: String,
    description: String,
    category: u8,
    picture: Option<Url>,
    price: u64,
    quantity: u64,
    seller: address,
    order_queue: vector<Order>,
}

public enum OrderStatus has copy, drop, store {
    Registered,
    Delivered,
    Disputed,
}

/// The arbitrable contract shall implement the key ability.
public struct Order has key, store {
    id: UID,
    status: OrderStatus,
    buyer: address,
    quantity: u64,
    funds: Balance<SUI>,
    description: String,
    last_updated: u64,
}

public struct Receipt has key, store {
    id: UID,
    order_id: ID,
    attachments: vector<Url>,
    description: String,
}

// === Functions ===
/// Create a new listing to the marketplace.
public fun new(
    marketplace: &mut Marketplace,
    title: String,
    description: String,
    category: u8,
    picture_url: Option<String>,
    price: u64,
    quantity: u64,
    ctx: &mut TxContext,
) {
    assert!(quantity <= MAX_QUANTITY, EQuantityLimitExceeded);
    assert!(title.length() <= MAX_TITLE_LENGTH, ETitleLimitExceeded);
    assert!(
        description.length() <= MAX_DESCRIPTION_LENGTH, 
        EDescriptionLimitExceeded
    );

    let listing = Listing {
        id: object::new(ctx),
        title,
        description,
        category,
        picture: picture_url
            .map!(|src| url::new_unsafe(src.to_ascii())),
        price,
        quantity,
        seller: ctx.sender(),
        order_queue: vector[]
    };

    marketplace.new_listing(object::id(&listing));
    transfer::share_object(listing);
}

/// Make a new order.
public fun order(
    listing: &mut Listing,
    quantity: u64,
    payment: Coin<SUI>,
    description: String,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(
        quantity > 0 && quantity <= listing.quantity, 
        ENotEnoughStock
    );
    assert!(
        description.length() <= MAX_DESCRIPTION_LENGTH, 
        EDescriptionLimitExceeded
    );
    assert!(payment.value() == listing.price * quantity, EInvalidPaymentAmount);
    assert!(ctx.sender() != listing.seller, ESelfPurchase);

    listing.quantity = listing.quantity - quantity;
    listing.order_queue.push_back(create_new_order(
        listing.seller, 
        ctx.sender(),
        choose_suitable_court(listing.category),
        quantity, 
        description, 
        payment, 
        clock, 
        ctx
    ));
}

/// Scenario 1: New order is created with an initial nivra configuration.
/// 
/// The buyer and the seller may both dispute the order as soon as it is placed.
fun create_new_order(
    seller: address,
    buyer: address,
    court: address,
    quantity: u64,
    description: String,
    payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): Order {
    let mut order = Order {
        id: object::new(ctx),
        status: OrderStatus::Registered,
        buyer,
        quantity,
        funds: payment.into_balance(),
        description,
        last_updated: clock.timestamp_ms(),
    };

    let nivra_config = nivra_configuration::create(
        court, 
        vec_map::from_keys_values(
            vector[
                OPTION_FULL_REFUND.to_string(), // Buyer's default option.
                OPTION_BUYER_FAULT.to_string(), // Seller's default option.
                OPTION_EXTEND_DELIVERY.to_string(),
            ], 
            vector[
                buyer,
                seller,
                seller,
            ],
        ), 
        MAX_APPEALS,
    );

    dynamic_field::add(
        &mut order.id, 
        b"nivra_key", // nivra_key shall be used for the SDK visibility.
        nivra_config,
    );

    order
}

/// Scenario 2: Order is delivered and voting options are changed to reflect
/// the new state. Changing the dispute config invalidates the earlier config
/// and its results (unless explicitly allowed)!
public fun deliver(
    listing: &mut Listing,
    order_id: ID,
    attachments: vector<String>,
    sha256_hashes: vector<vector<u8>>,
    description: String,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == listing.seller, EUserNotSeller);

    let order_idx = listing.order_queue
        .find_index!(|order| object::id(order) == order_id);

    assert!(order_idx.is_some(), EOrderNotFound);

    let order = listing.order_queue.borrow_mut(order_idx.destroy_some());

    assert!(
        order.status == OrderStatus::Registered, 
        EOrderNotAcceptingDelivery
    );

    order.status = OrderStatus::Delivered;
    order.last_updated = clock.timestamp_ms();

    let _: NivraConfiguration = dynamic_field::remove(
        &mut order.id, 
        b"nivra_key"
    );
    let mut new_config = nivra_configuration::create(
        choose_suitable_court(listing.category), 
        vec_map::from_keys_values(
            vector[
                OPTION_PRODUCT_NOT_AS_DESCRIBED.to_string(),
                OPTION_REQUIRE_REDELIVERY.to_string(),
                OPTION_PRODUCT_AS_DESCRIBED.to_string(),
            ], 
            vector[
                order.buyer,
                order.buyer,
                listing.seller,
            ],
        ), 
        MAX_APPEALS
    );

    // Add file hashes to the configuration.
    // File hashes can be used to prove validity of files in the nivra court.
    sha256_hashes.do!(|hash| new_config.add_file_hash_mut(hash));

    dynamic_field::add(
        &mut order.id, 
        b"nivra_key", 
        new_config,
    );

    let receipt = Receipt {
        id: object::new(ctx),
        order_id,
        attachments: attachments
            .map!(|link| url::new_unsafe(link.to_ascii())),
        description,
    };

    transfer::public_transfer(receipt, order.buyer);
}

/// Mark order as disputed on the moment of opening dispute, so order's dispute
/// config cannot change during the dispute.
/// 
/// Must be called on dispute opening.
public fun dispute_lock(
    listing: &mut Listing,
    order_id: ID,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let order_idx = listing.order_queue
        .find_index!(|order| object::id(order) == order_id);

    assert!(order_idx.is_some(), EOrderNotFound);

    let order = listing.order_queue.borrow_mut(order_idx.destroy_some());

    assert!(
        ctx.sender() == order.buyer || ctx.sender() == listing.seller,
        EUserNotDisputeParty
    );

    order.status = OrderStatus::Disputed;
    order.last_updated = clock.timestamp_ms();
}

/// Custom dispute resolution logic. 
/// In this contract, this is the only way to open the dispute lock.
/// 
/// NOTE: Only 1 dispute can be opened per arbitrable contract with the same
/// configuration. This quarantees that there aren't multiple differing results.
public fun resolve_dispute(
    marketplace: &mut Marketplace,
    listing: &mut Listing,
    order_id: ID,
    result: &NivraResult, // The NivraResult is send to both parties.
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let order_idx = listing.order_queue
        .find_index!(|order| object::id(order) == order_id);

    assert!(order_idx.is_some(), EOrderNotFound);

    // In our arbitration logic, the current order isn't used anymore.
    // After the first call, the resolve_dispute cannot be called again.
    let mut order = listing.order_queue.remove(order_idx.destroy_some());

    assert!(order.status == OrderStatus::Disputed, ENotDisputed);

    let config: NivraConfiguration = dynamic_field::remove(
        &mut order.id, 
        b"nivra_key",
    );

    let Order {
        id,
        status: _,
        buyer,
        quantity,
        mut funds,
        description,
        last_updated: _,
    } = order;

    id.delete();

    // This method validates the result to be from a vote that used the exact
    // latest nivra configuration and the arbitrable contract id.
    let winner_option = result.winner_option_by_config(
        order_id, 
        &config
    );

    // The delivery is extended, we open a new order with the original order
    // info. This way, a new dispute can be opened if necessary.
    if (
        winner_option == OPTION_EXTEND_DELIVERY.to_string() ||
        winner_option == OPTION_REQUIRE_REDELIVERY.to_string()
    ) {
        listing.order_queue.push_back(create_new_order(
            listing.seller,
            buyer,
            choose_suitable_court(listing.category),
            quantity,
            description,
            funds.into_coin(ctx),
            clock,
            ctx,
        ));
    }
    // Buyer is at fault, but the delivery hasn't been completed yet.
    // Refund the buyer 70% and terminate the order.
    else if (winner_option == OPTION_BUYER_FAULT.to_string()) {
        let buyer_refund = funds.value() * 7 / 10;

        transfer::public_transfer(
            funds.split(buyer_refund).into_coin(ctx), 
            buyer
        );
        transfer::public_transfer(funds.into_coin(ctx), listing.seller);
    }
    // Let the seller keep the funds and terminate the order.
    else if (winner_option == OPTION_PRODUCT_AS_DESCRIBED.to_string()) {
        transfer::public_transfer(funds.into_coin(ctx), listing.seller);
    }
    // Refund the buyer in full and terminate the order.
    // This handle occurs, if the result is OPTION_FULL_REFUND or 
    // OPTION_PRODUCT_NOT_AS_DESCRIBED.
    else {
        transfer::public_transfer(funds.into_coin(ctx), buyer);
    };

    // Remove listing if out of stock & no more orders.
    if (listing.quantity == 0 && listing.order_queue.is_empty()) {
        marketplace.remove_listing(object::id(listing));
    };
}

/// Claim order payment after the cashout period has passed.
public fun redeem_payment(
    marketplace: &mut Marketplace,
    listing: &mut Listing,
    order_id: ID,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<SUI> {
    assert!(ctx.sender() == listing.seller, EUserNotSeller);

    let order_idx = listing.order_queue
        .find_index!(|order| object::id(order) == order_id);

    assert!(order_idx.is_some(), EOrderNotFound);

    let order = listing.order_queue.remove(order_idx.destroy_some());

    assert!(
        order.status == OrderStatus::Delivered, 
        EOrderNotDelivered
    );

    let timestamp = clock.timestamp_ms();

    assert!(
        timestamp >= order.last_updated + CASHOUT_PERIOD,
        ECashoutPeriodNotFinished
    );

    let Order {
        id,
        status: _,
        buyer: _,
        quantity: _,
        funds,
        description: _,
        last_updated: _
    } = order;

    id.delete();

    // Remove listing if out of stock & no more orders.
    if (listing.quantity == 0 && listing.order_queue.is_empty()) {
        marketplace.remove_listing(object::id(listing));
    };

    funds.into_coin(ctx)
}

/// Choose suitable court based on category.
fun choose_suitable_court(
    category: u8,
): address {
    if (category == 0) {
        TESTNET_E_SERVICES_COURT
    } else {
        TESTNET_E_COMMERCE_COURT
    }
}