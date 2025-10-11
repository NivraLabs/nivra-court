module token::nvr;

use sui::coin::create_currency;
use sui::url::new_unsafe_from_bytes;

public struct NVR has drop {}

fun init(otw: NVR, ctx: &mut TxContext) {
    let (mut treasury_cap, metadata) = create_currency<NVR>(
        otw, 
        6, 
        b"NVR", 
        b"Nivra Token", 
        b"The native token for the Nivra arbitration protocol.", 
        option::some(new_unsafe_from_bytes(b"https://static.nivracourt.io/icon.svg")), 
        ctx
    );

    let minted_coin = treasury_cap.mint(1_000_000_000_000_000, ctx);

    transfer::public_freeze_object(metadata);
    transfer::public_freeze_object(treasury_cap);
    transfer::public_transfer(minted_coin, ctx.sender());
}