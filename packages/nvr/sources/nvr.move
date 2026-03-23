module nvr::nvr;

use sui::coin_registry::new_currency_with_otw;

public struct NVR has drop {}

fun init(otw: NVR, ctx: &mut TxContext) {
    let (mut init, mut treasury_cap) = new_currency_with_otw<NVR>(
        otw, 
        6, 
        b"NVR".to_string(), 
        b"Nivra".to_string(), 
        b"The native token for the Nivra arbitration protocol.".to_string(), 
        b"https://static.nivracourt.io/icon.svg".to_string(), 
        ctx,
    );

    let minted_coin = treasury_cap.mint(1_000_000_000_000_000, ctx);
    init.make_supply_fixed(treasury_cap);
    init.finalize_and_delete_metadata_cap(ctx);

    transfer::public_transfer(minted_coin, ctx.sender());
}