// © 2026 Nivra Labs Ltd.

#[test_only]
module nivra::master_tests;

use sui::test_scenario::{Self, Scenario};
use sui::coin::{Self, Coin};
use sui::clock::{Self, Clock};
use sui::random::{Self, Random};
use token::nvr::NVR;
use sui::sui::SUI;
use std::string;
use nivra::registry::{Self, Registry};
use nivra::court::{
    Self, Court,
    create_metadata, create_timetable, create_economics, create_operation,
};
use nivra::dispute::{Self, Dispute};
use nivra::constants;
use sui::address::from_u256;

// === Test Addresses ===
const ADMIN:      address = @0x78b21978658505237a465ef20a4cf3ce2d418fda9cfb3ce4a0e4be7f9a16187d;
const PARTY_A:    address = @0xB0;
const PARTY_B:    address = @0xC0;
const NIVSTER_1:  address = @0xD1;
const NIVSTER_2:  address = @0xD2;
const NIVSTER_3:  address = @0xD3;
const KEY_SERVER: address = @0xE0;

// === Period lengths (ms) ===
const RESPONSE_MS:   u64 = 1_000;
const DRAW_MS:       u64 = 2_000;
const EVIDENCE_MS:   u64 = 3_000;
const VOTING_MS:     u64 = 4_000;
const APPEAL_MS:     u64 = 5_000;
// Full round: draw_ms + evidence_ms + voting_ms + appeal_ms
const FULL_ROUND_MS: u64 = 14_000;

const DISPUTE_FEE: u64 = 1_000;
const MIN_STAKE:   u64 = 500;

// === Helpers ===

fun mint_nvr(amount: u64, ctx: &mut TxContext): Coin<NVR> {
    coin::mint_for_testing<NVR>(amount, ctx)
}

fun mint_sui(amount: u64, ctx: &mut TxContext): Coin<SUI> {
    coin::mint_for_testing<SUI>(amount, ctx)
}

fun dummy_pk(): vector<u8> {
    vector[
        0u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    ]
}

/// Initialise the registry shared object.
fun setup_registry(): Scenario {
    let mut scenario = test_scenario::begin(ADMIN);
    {
        registry::init_for_testing(scenario.ctx());
    };
    scenario
}

/// Create a court with `init_nivsters` nivsters drawn per round.
fun setup_court(scenario: &mut Scenario, init_nivsters: u64) {
    scenario.next_tx(ADMIN);
    let mut registry = scenario.take_shared<Registry>();

    court::create_court(
        &mut registry,
        create_metadata(
            string::utf8(b"Test Court"),
            string::utf8(b"General"),
            string::utf8(b"Unit test court"),
            false,
        ),
        create_timetable(RESPONSE_MS, DRAW_MS, EVIDENCE_MS, VOTING_MS, APPEAL_MS),
        create_economics(
            MIN_STAKE,
            0,          // no reputation requirement
            init_nivsters,
            0,          // FIXED_PERCENTAGE_MODEL
            10,         // 10% penalty coefficient
            DISPUTE_FEE,
            10,         // 10% treasury_share_sui
            10,         // 10% treasury_share_nvr
            20,         // 20% empty_vote_penalty
        ),
        create_operation(0, vector[KEY_SERVER], vector[dummy_pk()], 1),
        scenario.ctx(),
    );

    test_scenario::return_shared(registry);
}

/// Stake NVR as `actor`.  Worker pool join happens automatically inside stake().
fun stake_nvr(scenario: &mut Scenario, actor: address, amount: u64) {
    scenario.next_tx(actor);
    let mut court = scenario.take_shared<Court>();
    let registry = scenario.take_shared<Registry>();
    let nvr = mint_nvr(amount, scenario.ctx());
    court::stake(&mut court, &registry, nvr, scenario.ctx());
    test_scenario::return_shared(registry);
    test_scenario::return_shared(court);
}

/// Open a dispute as PARTY_A against a fake contract.
fun open_dispute(scenario: &mut Scenario, clock: &Clock) {
    scenario.next_tx(PARTY_A);
    let mut court = scenario.take_shared<Court>();
    let fee = mint_sui(DISPUTE_FEE, scenario.ctx());

    court::open_dispute(
        &mut court,
        fee,
        object::id_from_address(@0xF0),
        string::utf8(b"Test dispute"),
        vector[string::utf8(b"Option A"), string::utf8(b"Option B")],
        vector[PARTY_A, PARTY_B],
        0,
        clock,
        scenario.ctx(),
    );

    test_scenario::return_shared(court);
}

/// Open a dispute as PARTY_A against a fake contract, specifying max_appeals.
fun open_dispute_with_appeals(scenario: &mut Scenario, clock: &Clock, max_appeals: u8) {
    scenario.next_tx(PARTY_A);
    let mut court = scenario.take_shared<Court>();
    let fee = mint_sui(DISPUTE_FEE, scenario.ctx());

    court::open_dispute(
        &mut court,
        fee,
        object::id_from_address(@0xF0),
        string::utf8(b"Test dispute"),
        vector[string::utf8(b"Option A"), string::utf8(b"Option B")],
        vector[PARTY_A, PARTY_B],
        max_appeals,
        clock,
        scenario.ctx(),
    );

    test_scenario::return_shared(court);
}

/// PARTY_B accepts the open dispute.
fun accept_dispute(scenario: &mut Scenario, clock: &Clock) {
    scenario.next_tx(PARTY_B);
    let mut court = scenario.take_shared<Court>();
    let mut dispute = scenario.take_shared<Dispute>();
    let fee = mint_sui(DISPUTE_FEE, scenario.ctx());

    court::accept_dispute(
        &mut court,
        &mut dispute,
        fee,
        clock,
        scenario.ctx(),
    );

    test_scenario::return_shared(dispute);
    test_scenario::return_shared(court);
}

/// Draw nivsters. Requires Random to exist (create via random::create_for_testing).
fun draw_nivsters(scenario: &mut Scenario, clock: &Clock) {
    scenario.next_tx(PARTY_A);
    let mut court = scenario.take_shared<Court>();
    let mut dispute = scenario.take_shared<Dispute>();
    let random = scenario.take_shared<Random>();

    court::draw_nivsters(
        &mut court,
        &mut dispute,
        clock,
        &random,
        scenario.ctx(),
    );

    test_scenario::return_shared(random);
    test_scenario::return_shared(dispute);
    test_scenario::return_shared(court);
}

// =============================================================================
// Tests
// =============================================================================

// --- 1. Staking and withdrawal ---

#[test]
fun test_stake_and_withdraw() {
    let mut scenario = setup_registry();
    setup_court(&mut scenario, 1);

    stake_nvr(&mut scenario, NIVSTER_1, 1000);

    scenario.next_tx(NIVSTER_1);
    {
        let mut court = scenario.take_shared<Court>();

        let (nvr, sui) = court::withdraw(&mut court, 300, 0, scenario.ctx());
        assert!(nvr.value() == 300);
        assert!(sui.value() == 0);

        nvr.into_balance().destroy_for_testing();
        sui.into_balance().destroy_for_testing();

        test_scenario::return_shared(court);
    };

    scenario.end();
}

// --- 2. Open dispute happy path ---

#[test]
fun test_open_dispute() {
    let mut scenario = setup_registry();
    setup_court(&mut scenario, 1);

    let clock = clock::create_for_testing(scenario.ctx());
    open_dispute(&mut scenario, &clock);

    scenario.next_tx(PARTY_A);
    {
        let dispute = scenario.take_shared<Dispute>();
        assert!(dispute::status(&dispute) == constants::dispute_status_response());
        assert!(dispute::is_response_period(&dispute, &clock));
        assert!(dispute::is_party(&dispute, PARTY_A));
        assert!(dispute::is_party(&dispute, PARTY_B));
        test_scenario::return_shared(dispute);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// --- 3. Wrong fee is rejected ---

#[test]
#[expected_failure(abort_code = court::EInvalidFee)]
fun test_open_dispute_wrong_fee() {
    let mut scenario = setup_registry();
    setup_court(&mut scenario, 1);

    let clock = clock::create_for_testing(scenario.ctx());

    scenario.next_tx(PARTY_A);
    {
        let mut court = scenario.take_shared<Court>();
        let fee = mint_sui(DISPUTE_FEE + 1, scenario.ctx());

        court::open_dispute(
            &mut court,
            fee,
            object::id_from_address(@0xF0),
            string::utf8(b"Test dispute"),
            vector[string::utf8(b"Option A"), string::utf8(b"Option B")],
            vector[PARTY_A, PARTY_B],
            0,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(court);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// --- 4. Accept dispute transitions to DRAW ---

#[test]
fun test_accept_dispute() {
    let mut scenario = setup_registry();
    setup_court(&mut scenario, 1);

    let clock = clock::create_for_testing(scenario.ctx());
    open_dispute(&mut scenario, &clock);
    accept_dispute(&mut scenario, &clock);

    scenario.next_tx(PARTY_A);
    {
        let dispute = scenario.take_shared<Dispute>();
        assert!(dispute::status(&dispute) == constants::dispute_status_draw());
        test_scenario::return_shared(dispute);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// --- 5. One-sided dispute: PARTY_B never pays ---

#[test]
fun test_one_sided_dispute() {
    let mut scenario = setup_registry();
    setup_court(&mut scenario, 1);

    let mut clock = clock::create_for_testing(scenario.ctx());
    open_dispute(&mut scenario, &clock);

    // Advance past response period — PARTY_B never paid.
    clock.increment_for_testing(RESPONSE_MS + 1);

    scenario.next_tx(PARTY_A);
    {
        let mut court = scenario.take_shared<Court>();
        let mut dispute = scenario.take_shared<Dispute>();
        let mut registry = scenario.take_shared<Registry>();

        assert!(dispute::party_failed_payment(&dispute, &clock));

        court::resolve_one_sided_dispute(
            &mut court,
            &mut dispute,
            &mut registry,
            &clock,
            scenario.ctx(),
        );

        assert!(
            dispute::status(&dispute) == 
                constants::dispute_status_completed_one_sided()
        );

        test_scenario::return_shared(registry);
        test_scenario::return_shared(dispute);
        test_scenario::return_shared(court);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// --- 6. Cancel dispute: draw period expires with no draw ---

#[test]
fun test_cancel_dispute_no_draw() {
    let mut scenario = setup_registry();
    setup_court(&mut scenario, 1);

    let mut clock = clock::create_for_testing(scenario.ctx());
    open_dispute(&mut scenario, &clock);
    accept_dispute(&mut scenario, &clock);

    // Advance past draw period without calling draw_nivsters.
    clock.increment_for_testing(DRAW_MS + 1);

    scenario.next_tx(PARTY_A);
    {
        let mut court = scenario.take_shared<Court>();
        let mut dispute = scenario.take_shared<Dispute>();

        assert!(dispute::is_incomplete(&dispute, &clock));

        court::cancel_dispute(
            &mut court,
            &mut dispute,
            &clock,
            scenario.ctx(),
        );

        assert!(
            dispute::status(&dispute) == constants::dispute_status_cancelled()
        );

        test_scenario::return_shared(dispute);
        test_scenario::return_shared(court);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// --- 7. Draw nivsters, then cancel when no votes submitted ---

#[test]
fun test_draw_nivsters_then_cancel_no_votes() {
    let mut scenario = setup_registry();
    setup_court(&mut scenario, 1);

    stake_nvr(&mut scenario, NIVSTER_1, MIN_STAKE);

    let mut clock = clock::create_for_testing(scenario.ctx());
    open_dispute(&mut scenario, &clock);
    accept_dispute(&mut scenario, &clock);

    // Create Random for draw (must be from @0x0 per Sui stdlib rules).
    scenario.next_tx(@0x0);
    random::create_for_testing(scenario.ctx());

    draw_nivsters(&mut scenario, &clock);

    // Confirm 1 voter selected and dispute is active.
    scenario.next_tx(PARTY_A);
    {
        let dispute = scenario.take_shared<Dispute>();
        assert!(dispute::voters(&dispute).length() == 1);
        assert!(dispute::status(&dispute) == constants::dispute_status_active());
        test_scenario::return_shared(dispute);
    };

    // Skip past entire round — no votes, no finalize_vote.
    clock.increment_for_testing(FULL_ROUND_MS + 1);

    scenario.next_tx(PARTY_A);
    {
        let mut court = scenario.take_shared<Court>();
        let mut dispute = scenario.take_shared<Dispute>();

        assert!(dispute::is_incomplete(&dispute, &clock));

        court::cancel_dispute(
            &mut court,
            &mut dispute,
            &clock,
            scenario.ctx(),
        );

        assert!(
            dispute::status(&dispute) == constants::dispute_status_cancelled()
        );

        test_scenario::return_shared(dispute);
        test_scenario::return_shared(court);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// --- 8. Reputation gate: fresh nivster blocked from high-rep court ---

#[test]
#[expected_failure(abort_code = court::ETooLowReputation)]
fun test_staking_reputation_gate() {
    let mut scenario = setup_registry();

    // Create a court with a 50% win-rate requirement.
    scenario.next_tx(ADMIN);
    {
        let mut registry = scenario.take_shared<Registry>();

        court::create_court(
            &mut registry,
            create_metadata(
                string::utf8(b"Gated Court"),
                string::utf8(b"General"),
                string::utf8(b"Court requiring 50% win rate"),
                false,
            ),
            create_timetable(RESPONSE_MS, DRAW_MS, EVIDENCE_MS, VOTING_MS, APPEAL_MS),
            create_economics(
                MIN_STAKE, 50, 1, 0, 10, DISPUTE_FEE, 10, 10, 20,
            ),
            create_operation(0, vector[KEY_SERVER], vector[dummy_pk()], 1),
            scenario.ctx(),
        );

        test_scenario::return_shared(registry);
    };

    // NIVSTER_1 has no cases on record → reputation = 0 → should abort.
    scenario.next_tx(NIVSTER_1);
    {
        let mut court = scenario.take_shared<Court>();
        let registry = scenario.take_shared<Registry>();
        let nvr = mint_nvr(MIN_STAKE, scenario.ctx());
        court::stake(&mut court, &registry, nvr, scenario.ctx());
        test_scenario::return_shared(registry);
        test_scenario::return_shared(court);
    };

    scenario.end();
}

// --- 9. Draw fails when pool has fewer nivsters than required ---

#[test]
#[expected_failure(abort_code = court::ENotEnoughNivsters)]
fun test_draw_fails_not_enough_nivsters() {
    let mut scenario = setup_registry();
    setup_court(&mut scenario, 3); // court needs 3, only 1 staked

    stake_nvr(&mut scenario, NIVSTER_1, MIN_STAKE);

    let clock = clock::create_for_testing(scenario.ctx());
    open_dispute(&mut scenario, &clock);
    accept_dispute(&mut scenario, &clock);

    scenario.next_tx(@0x0);
    random::create_for_testing(scenario.ctx());

    draw_nivsters(&mut scenario, &clock); // should abort

    clock.destroy_for_testing();
    scenario.end();
}

// --- 10. Three nivsters drawn when exactly three are staked ---

#[test]
fun test_multiple_nivsters_drawn() {
    let mut scenario = setup_registry();
    setup_court(&mut scenario, 3);

    stake_nvr(&mut scenario, NIVSTER_1, MIN_STAKE);
    stake_nvr(&mut scenario, NIVSTER_2, MIN_STAKE);
    stake_nvr(&mut scenario, NIVSTER_3, MIN_STAKE);

    let clock = clock::create_for_testing(scenario.ctx());
    open_dispute(&mut scenario, &clock);
    accept_dispute(&mut scenario, &clock);

    scenario.next_tx(@0x0);
    random::create_for_testing(scenario.ctx());

    draw_nivsters(&mut scenario, &clock);

    scenario.next_tx(PARTY_A);
    {
        let dispute = scenario.take_shared<Dispute>();
        assert!(dispute::voters(&dispute).length() == 3);
        test_scenario::return_shared(dispute);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// --- 11. Full dispute to completion ---

#[test]
fun test_dispute_completion() {
    let mut scenario = setup_registry();
    setup_court(&mut scenario, 3); // court needs 3, 3 stakes

    stake_nvr(&mut scenario, NIVSTER_1, MIN_STAKE);
    stake_nvr(&mut scenario, NIVSTER_2, MIN_STAKE);
    stake_nvr(&mut scenario, NIVSTER_3, MIN_STAKE);

    let mut clock = clock::create_for_testing(scenario.ctx());
    open_dispute(&mut scenario, &clock);
    accept_dispute(&mut scenario, &clock);

    scenario.next_tx(@0x0);
    random::create_for_testing(scenario.ctx());

    draw_nivsters(&mut scenario, &clock);

    // Skip to voting/tally phase
    clock.increment_for_testing(EVIDENCE_MS + 1);

    // Inject fake decrypted votes directly
    scenario.next_tx(ADMIN);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        
        // Option 0 (Option A) gets 2 votes, Option 1 (Option B) gets 1 vote.
        dispute::add_fake_vote_for_testing(&mut dispute, NIVSTER_1, 0);
        dispute::add_fake_vote_for_testing(&mut dispute, NIVSTER_2, 0);
        dispute::add_fake_vote_for_testing(&mut dispute, NIVSTER_3, 1);
        
        dispute::tally_fake_votes_for_testing(&mut dispute);

        assert!(
            dispute::status(&dispute) == constants::dispute_status_tallied()
        );

        test_scenario::return_shared(dispute);
    };

    // Skip to appeal period end
    clock.increment_for_testing(VOTING_MS + APPEAL_MS + 1);

    scenario.next_tx(PARTY_A);
    {
        let mut court = scenario.take_shared<Court>();
        let mut dispute = scenario.take_shared<Dispute>();
        let mut registry = scenario.take_shared<Registry>();

        court::complete_dispute(
            &mut court,
            &mut dispute,
            &mut registry,
            &clock,
            scenario.ctx(),
        );

        assert!(
            dispute::status(&dispute) == constants::dispute_status_completed()
        );

        test_scenario::return_shared(registry);
        test_scenario::return_shared(dispute);
        test_scenario::return_shared(court);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// --- 12. Full dispute to completion with an appeal round ---

#[test]
fun test_dispute_appeal_completion() {
    let mut scenario = setup_registry();
    // Use init_nivsters = 1. First round needs 1 nivster. Appeal needs 2. 
    // Staking 3 total covers all possibilities.
    setup_court(&mut scenario, 1);

    stake_nvr(&mut scenario, NIVSTER_1, MIN_STAKE);
    stake_nvr(&mut scenario, NIVSTER_2, MIN_STAKE);
    stake_nvr(&mut scenario, NIVSTER_3, MIN_STAKE);

    let mut clock = clock::create_for_testing(scenario.ctx());
    
    // --- ROUND 0 ---
    open_dispute_with_appeals(&mut scenario, &clock, 1);
    accept_dispute(&mut scenario, &clock);

    scenario.next_tx(@0x0);
    random::create_for_testing(scenario.ctx());

    draw_nivsters(&mut scenario, &clock);

    // Skip past evidence phase to enter voting phase
    clock.increment_for_testing(EVIDENCE_MS + 1);

    // Inject fake decrypted vote: Option 0 wins
    scenario.next_tx(ADMIN);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        
        let nivsters = dispute::voters(&dispute).keys();
        assert!(nivsters.length() == 1, 0);
        let drawn_nivster = nivsters[0];

        dispute::add_fake_vote_for_testing(&mut dispute, drawn_nivster, 0);
        dispute::tally_fake_votes_for_testing(&mut dispute);

        assert!(dispute::status(&dispute) == constants::dispute_status_tallied(), 1);

        test_scenario::return_shared(dispute);
    };

    // Skip past voting phase to enter appeal phase
    clock.increment_for_testing(VOTING_MS);

    // --- APPEAL ROUND 1 ---
    let appeal_fee_amount = 2600; // 1000 * 13 / 5

    scenario.next_tx(PARTY_B);
    {
        let mut court = scenario.take_shared<Court>();
        let mut dispute = scenario.take_shared<Dispute>();
        let fee = mint_sui(appeal_fee_amount, scenario.ctx());

        court::open_appeal(
            &mut court,
            &mut dispute,
            fee,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(dispute);
        test_scenario::return_shared(court);
    };

    scenario.next_tx(PARTY_A);
    {
        let mut court = scenario.take_shared<Court>();
        let mut dispute = scenario.take_shared<Dispute>();
        let fee = mint_sui(appeal_fee_amount, scenario.ctx());

        court::accept_dispute(
            &mut court,
            &mut dispute,
            fee,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(dispute);
        test_scenario::return_shared(court);
    };

    // Draw for appeal round
    scenario.next_tx(@0x0);
    draw_nivsters(&mut scenario, &clock);

    // Skip past evidence phase of appeal round to enter voting phase
    clock.increment_for_testing(EVIDENCE_MS + 1);

    scenario.next_tx(ADMIN);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        
        let nivsters = dispute::voters(&dispute).keys();
        nivsters.do!(|drawn| {
            dispute::add_fake_vote_for_testing(&mut dispute, drawn, 1);
        });

        dispute::tally_fake_votes_for_testing(&mut dispute);

        assert!(dispute::status(&dispute) == constants::dispute_status_tallied(), 3);

        test_scenario::return_shared(dispute);
    };

    // Skip past voting phase AND appeal phase to complete the dispute
    clock.increment_for_testing(VOTING_MS + APPEAL_MS + 1);

    scenario.next_tx(PARTY_B);
    {
        let mut court = scenario.take_shared<Court>();
        let mut dispute = scenario.take_shared<Dispute>();
        let mut registry = scenario.take_shared<Registry>();

        court::complete_dispute(
            &mut court,
            &mut dispute,
            &mut registry,
            &clock,
            scenario.ctx(),
        );

        assert!(dispute::status(&dispute) == constants::dispute_status_completed(), 4);

        test_scenario::return_shared(registry);
        test_scenario::return_shared(dispute);
        test_scenario::return_shared(court);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// --- 13. Dispute reward distribution ---

#[test]
fun test_dispute_reward_distribution() {
    let mut scenario = setup_registry();
    setup_court(&mut scenario, 3); // court needs 3, 3 stakes

    stake_nvr(&mut scenario, NIVSTER_1, MIN_STAKE);
    stake_nvr(&mut scenario, NIVSTER_2, MIN_STAKE);
    stake_nvr(&mut scenario, NIVSTER_3, MIN_STAKE);

    let mut clock = clock::create_for_testing(scenario.ctx());
    open_dispute(&mut scenario, &clock);
    accept_dispute(&mut scenario, &clock);

    scenario.next_tx(@0x0);
    random::create_for_testing(scenario.ctx());
    draw_nivsters(&mut scenario, &clock);

    // Skip past evidence phase to enter voting phase
    clock.increment_for_testing(EVIDENCE_MS + 1);

    // Inject fake decrypted votes directly
    scenario.next_tx(ADMIN);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        
        let nivsters = dispute::voters(&dispute).keys();
        assert!(nivsters.length() == 3, 0);

        // Option 0 (Option A) gets 2 votes, Option 1 (Option B) gets 1 vote.
        dispute::add_fake_vote_for_testing(&mut dispute, NIVSTER_1, 0);
        dispute::add_fake_vote_for_testing(&mut dispute, NIVSTER_2, 0);
        dispute::add_fake_vote_for_testing(&mut dispute, NIVSTER_3, 1);
        
        dispute::tally_fake_votes_for_testing(&mut dispute);

        assert!(dispute::status(&dispute) == constants::dispute_status_tallied(), 1);

        test_scenario::return_shared(dispute);
    };

    // Skip past voting phase AND appeal phase to complete the dispute
    clock.increment_for_testing(VOTING_MS + APPEAL_MS + 1);

    scenario.next_tx(PARTY_A);
    {
        let mut court = scenario.take_shared<Court>();
        let mut dispute = scenario.take_shared<Dispute>();
        let mut registry = scenario.take_shared<Registry>();

        court::complete_dispute(
            &mut court,
            &mut dispute,
            &mut registry,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(registry);
        test_scenario::return_shared(dispute);
        test_scenario::return_shared(court);
    };

    // Check PARTY_A balance (should be exactly 1000 SUI dispute fee returned)
    scenario.next_tx(PARTY_A);
    {
        let sui_coin = scenario.take_from_address<Coin<SUI>>(PARTY_A);
        assert!(sui_coin.value() == 1000, 2);
        sui_coin.into_balance().destroy_for_testing();
    };

    // Check Treasury balance (10% of 1000 SUI = 100 SUI, 10% of 50 NVR = 5 NVR + 1 rounding remainder = 6 NVR)
    // The treasury address is the module publisher's address returned by registry::treasury_address(), 
    // which in test environments typically defaults to ADMIN.
    scenario.next_tx(ADMIN);
    {
        let sui_coin = scenario.take_from_address<Coin<SUI>>(ADMIN);
        assert!(sui_coin.value() == 100, 3);
        sui_coin.into_balance().destroy_for_testing();

        let nvr_coin = scenario.take_from_address<Coin<NVR>>(ADMIN);
        assert!(nvr_coin.value() == 6, 4);
        nvr_coin.into_balance().destroy_for_testing();
    };

    // Check NIVSTER_1 balance (should be 522 NVR, 450 SUI)
    scenario.next_tx(NIVSTER_1);
    {
        let mut court = scenario.take_shared<Court>();
        let (nvr, sui) = court::withdraw(&mut court, 522, 450, scenario.ctx());
        assert!(nvr.value() == 522, 5);
        assert!(sui.value() == 450, 6);
        nvr.into_balance().destroy_for_testing();
        sui.into_balance().destroy_for_testing();
        test_scenario::return_shared(court);
    };

    // Check NIVSTER_2 balance (should be 522 NVR, 450 SUI)
    scenario.next_tx(NIVSTER_2);
    {
        let mut court = scenario.take_shared<Court>();
        let (nvr, sui) = court::withdraw(&mut court, 522, 450, scenario.ctx());
        assert!(nvr.value() == 522, 7);
        assert!(sui.value() == 450, 8);
        nvr.into_balance().destroy_for_testing();
        sui.into_balance().destroy_for_testing();
        test_scenario::return_shared(court);
    };

    // Check NIVSTER_3 balance (should be 450 NVR, 0 SUI since they lost 50 NVR)
    scenario.next_tx(NIVSTER_3);
    {
        let mut court = scenario.take_shared<Court>();
        let (nvr, sui) = court::withdraw(&mut court, 450, 0, scenario.ctx());
        assert!(nvr.value() == 450, 9);
        assert!(sui.value() == 0, 10);
        nvr.into_balance().destroy_for_testing();
        sui.into_balance().destroy_for_testing();
        test_scenario::return_shared(court);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// --- 14. Dispute reward distribution ---
#[test]
fun test_large_dispute() {
    let mut scenario = setup_registry();
    setup_court(&mut scenario, 11);

    let mut i = 0;

    while (i < 50) {
        stake_nvr(&mut scenario, sui::address::from_u256(1000 + i), 10 * MIN_STAKE);
        i = i + 1;
    };

    scenario.end();
}