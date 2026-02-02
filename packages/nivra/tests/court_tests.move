#[test_only]
module nivra::court_tests;

use nivra::court::nivsters_take;
use sui::test_scenario;
use nivra::court::create_court_for_testing;
use token::nvr::NVR;
use sui::coin;
use nivra::court_registry::get_root_privileges_for_testing;
use sui::clock;
use sui::sui::SUI;
use nivra::dispute::Dispute;
use nivra::constants::dispute_status_tallied;
use nivra::dispute::PartyCap;
use nivra::court::dispute_fee;
use nivra::constants::dispute_status_active;
use sui::random::Random;
use nivra::constants::dispute_status_draw;
use nivra::constants::dispute_status_tie;
use nivra::result::Result;
use sui::clock::Clock;

#[test]
fun test_staking() {
    let alice = @0xA;
    let min_stake = 10_000_000;

    let mut scenario = test_scenario::begin(alice);
    let court = 
    {
        let mut court = create_court_for_testing(scenario.ctx());
        let tokens = coin::mint_for_testing<NVR>(
            min_stake, 
            scenario.ctx()
        );

        court.stake(tokens, scenario.ctx());

        let (nvr, sui) = court.withdraw(5_000_000, 0, scenario.ctx());
        sui.destroy_zero();
        
        //Test re-staking to make up the min stake
        court.stake(nvr, scenario.ctx());

        let alice_stake = court.stakes().borrow(alice);
        assert!(alice_stake.amount() == min_stake);

        court
    };
    test_scenario::end(scenario);

    court.destroy_court_for_testing();
}

#[test, expected_failure(abort_code = 3, location = nivra::court)]
fun test_staking_under_min_stake() {
    let alice = @0xA;
    let min_stake = 10_000_000;

    let mut scenario = test_scenario::begin(alice);
    let court = 
    {
        let mut court = create_court_for_testing(scenario.ctx());
        let tokens = coin::mint_for_testing<NVR>(
            min_stake - 1, 
            scenario.ctx()
        );

        court.stake(tokens, scenario.ctx());
        court
    };
    test_scenario::end(scenario);

    court.destroy_court_for_testing();
}

#[test, expected_failure(abort_code = 3, location = nivra::court)]
fun test_staking_topping_under_min_stake() {
    let alice = @0xA;
    let min_stake = 10_000_000;

    let mut scenario = test_scenario::begin(alice);
    let court = 
    {
        let mut court = create_court_for_testing(scenario.ctx());
        let tokens = coin::mint_for_testing<NVR>(
            min_stake, 
            scenario.ctx()
        );

        court.stake(tokens, scenario.ctx());
        let (mut nvr, sui) = court.withdraw(5_000_000, 0, scenario.ctx());
        nvr.split_and_transfer(1, alice, scenario.ctx());
        sui.destroy_zero();

        court.stake(nvr, scenario.ctx());
        court
    };
    test_scenario::end(scenario);

    court.destroy_court_for_testing();
}

#[test, expected_failure(abort_code = 4, location = nivra::court)]
fun test_staking_halted() {
    let alice = @0xA;
    let min_stake = 10_000_000;

    let mut scenario = test_scenario::begin(alice);
    {
        let (court_registry, admin_cap) = 
            get_root_privileges_for_testing(scenario.ctx());
        let mut court = create_court_for_testing(scenario.ctx());
        let tokens = coin::mint_for_testing<NVR>(
            min_stake, 
            scenario.ctx()
        );

        // Halt court
        court.halt_operation(&admin_cap, &court_registry);
        court.stake(tokens, scenario.ctx());

        court.destroy_court_for_testing();
        court_registry.destroy_court_registry_for_testing();
        admin_cap.destroy_admin_cap_for_testing();
    };
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = 2, location = nivra::court)]
fun test_staking_zero() {
    let alice = @0xA;

    let mut scenario = test_scenario::begin(alice);
    {
        let mut court = create_court_for_testing(scenario.ctx());
        let tokens = coin::mint_for_testing<NVR>(
            0, 
            scenario.ctx()
        );

        court.stake(tokens, scenario.ctx());

        court.destroy_court_for_testing();
    };
    test_scenario::end(scenario);
}

#[test]
fun test_staking_with_worker_pool() {
    let alice = @0xA;
    let min_stake = 10_000_000;

    let mut scenario = test_scenario::begin(alice);
    {
        let mut court = create_court_for_testing(scenario.ctx());
        let tokens = coin::mint_for_testing<NVR>(
            min_stake, 
            scenario.ctx()
        );

        court.stake(tokens, scenario.ctx());
        court.join_worker_pool(scenario.ctx());

        let stake = court.stakes().borrow(alice);
        let worker_pool = court.worker_pool();
        let (_, amount) = worker_pool
            .get_idx(*stake.worker_pool_pos().borrow());

        assert!(amount == min_stake);

        let tokens = coin::mint_for_testing<NVR>(
            min_stake, 
            scenario.ctx()
        );

        court.stake(tokens, scenario.ctx());

        let stake = court.stakes().borrow(alice);
        let worker_pool = court.worker_pool();
        let (_, amount) = worker_pool
            .get_idx(*stake.worker_pool_pos().borrow());

        assert!(amount == min_stake * 2);

        court.destroy_court_for_testing();
    };
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = 6, location = nivra::court)]
fun test_over_withdraw_nvr() {
    let alice = @0xA;
    let min_stake = 10_000_000;

    let mut scenario = test_scenario::begin(alice);
    {
        let mut court = create_court_for_testing(scenario.ctx());
        let tokens = coin::mint_for_testing<NVR>(
            min_stake, 
            scenario.ctx()
        );

        court.stake(tokens, scenario.ctx());
        let (nvr, sui) = court.
            withdraw(min_stake + 1, 0, scenario.ctx());
        
        sui.destroy_zero();
        nvr.into_balance().destroy_for_testing();
        court.destroy_court_for_testing();
    };
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = 7, location = nivra::court)]
fun test_over_withdraw_sui() {
    let alice = @0xA;
    let min_stake = 10_000_000;

    let mut scenario = test_scenario::begin(alice);
    {
        let mut court = create_court_for_testing(scenario.ctx());
        let tokens = coin::mint_for_testing<NVR>(
            min_stake, 
            scenario.ctx()
        );

        court.stake(tokens, scenario.ctx());
        let (nvr, sui) = court.
            withdraw(min_stake, 100, scenario.ctx());
        
        sui.destroy_zero();
        nvr.into_balance().destroy_for_testing();
        court.destroy_court_for_testing();
    };
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = 8, location = nivra::court)]
fun test_withdraw_zero() {
    let alice = @0xA;
    let min_stake = 10_000_000;

    let mut scenario = test_scenario::begin(alice);
    {
        let mut court = create_court_for_testing(scenario.ctx());
        let tokens = coin::mint_for_testing<NVR>(
            min_stake, 
            scenario.ctx()
        );

        court.stake(tokens, scenario.ctx());
        let (nvr, sui) = court.
            withdraw(0, 0, scenario.ctx());
        
        sui.destroy_zero();
        nvr.into_balance().destroy_for_testing();
        court.destroy_court_for_testing();
    };
    test_scenario::end(scenario);
}

#[test]
fun test_withdraw_worker_pool() {
    let (alice, alice_stake) = (@0xA, 10_000_000);
    let (bob, bob_stake) = (@0xB, 15_000_000);
    let (charlie, charlie_stake) = (@0xC, 25_000_000);

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let mut court = create_court_for_testing(scenario.ctx());
        court.stake(
            coin::mint_for_testing<NVR>(
                alice_stake, 
                scenario.ctx()
            ), 
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());
        court
    };
    scenario.next_tx(bob);
    {
        court.stake(
            coin::mint_for_testing<NVR>(
                bob_stake, 
                scenario.ctx()
            ), 
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());
    };
    scenario.next_tx(charlie);
    {
        court.stake(
            coin::mint_for_testing<NVR>(
                charlie_stake, 
                scenario.ctx()
            ), 
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());
    };
    scenario.next_tx(alice);
    {
        // Withdraw balance under the min stake, removing alice from the
        // worker pool.
        let (nvr, sui) = court.withdraw(1, 0, scenario.ctx());
        nvr.into_balance().destroy_for_testing();
        sui.destroy_zero();

        // Check worker pool balances for charlie and bob.
        let c_stake = court.stakes().borrow(charlie);
        let b_stake = court.stakes().borrow(bob);
        let worker_pool = court.worker_pool();
        let (_, c_amount) = worker_pool
            .get_idx(*c_stake.worker_pool_pos().borrow());
        let (_, b_amount) = worker_pool
            .get_idx(*b_stake.worker_pool_pos().borrow());

        assert!(c_amount == charlie_stake);
        assert!(b_amount == bob_stake);
    };
    scenario.next_tx(bob);
    {
        // Withdraw the excess stake, keeping bob in the worker pool.
        let (nvr, sui) = court.withdraw(5_000_000, 0, scenario.ctx());
        nvr.into_balance().destroy_for_testing();
        sui.destroy_zero();

        let b_stake = court.stakes().borrow(bob);
        let worker_pool = court.worker_pool();
        let (_, b_amount) = worker_pool
            .get_idx(*b_stake.worker_pool_pos().borrow());

        assert!(b_amount == bob_stake - 5_000_000);
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test, expected_failure]
fun test_withdraw_no_stake() {
    let alice = @0xA;

    let mut scenario = test_scenario::begin(alice);
    {
        let mut court = create_court_for_testing(scenario.ctx());
        let (nvr, sui) = court.
            withdraw(0, 0, scenario.ctx());
        
        sui.destroy_zero();
        nvr.into_balance().destroy_for_testing();
        court.destroy_court_for_testing();
    };
    test_scenario::end(scenario);
}

#[test]
fun test_leave_worker_pool() {
    let (alice, alice_stake) = (@0xA, 10_000_000);
    let (bob, bob_stake) = (@0xB, 15_000_000);

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let mut court = create_court_for_testing(scenario.ctx());
        court.stake(
            coin::mint_for_testing<NVR>(
                alice_stake, 
                scenario.ctx()
            ), 
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());
        court
    };
    scenario.next_tx(bob);
    {
        court.stake(
            coin::mint_for_testing<NVR>(
                bob_stake, 
                scenario.ctx()
            ), 
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());
    };
    scenario.next_tx(alice);
    {
        court.leave_worker_pool(scenario.ctx());
        assert!(court.worker_pool().length() == 1);

        let a_stake = court.stakes().borrow(alice);
        assert!(a_stake.worker_pool_pos().is_none());
        assert!(a_stake.amount() == alice_stake);
    };
    scenario.next_tx(bob);
    {
        court.leave_worker_pool(scenario.ctx());
        assert!(court.worker_pool().length() == 0);

        let b_stake = court.stakes().borrow(bob);
        assert!(b_stake.worker_pool_pos().is_none());
        assert!(b_stake.amount() == bob_stake);
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test, expected_failure(abort_code = 5, location = nivra::court)]
fun test_join_worker_pool_twice() {
    let (alice, alice_stake) = (@0xA, 10_000_000);

    let mut scenario = test_scenario::begin(alice);
    let court = 
    {
        let mut court = create_court_for_testing(scenario.ctx());
        court.stake(
            coin::mint_for_testing<NVR>(
                alice_stake, 
                scenario.ctx()
            ), 
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());
        court.join_worker_pool(scenario.ctx());
        court
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test, expected_failure(abort_code = 6, location = nivra::court)]
fun test_join_worker_pool_insufficient_stake() {
    let (alice, alice_stake) = (@0xA, 10_000_000);

    let mut scenario = test_scenario::begin(alice);
    let court = 
    {
        let mut court = create_court_for_testing(scenario.ctx());
        court.stake(
            coin::mint_for_testing<NVR>(
                alice_stake, 
                scenario.ctx()
            ), 
            scenario.ctx()
        );
        let (nvr, sui) = court.withdraw(1, 0, scenario.ctx());
        nvr.into_balance().destroy_for_testing();
        sui.destroy_zero();
        court.join_worker_pool(scenario.ctx());
        court
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test, expected_failure(abort_code = 4, location = nivra::court)]
fun test_join_worker_pool_halted() {
    let (alice, alice_stake) = (@0xA, 10_000_000);

    let mut scenario = test_scenario::begin(alice);
    let court = 
    {
        let (cr, ac) = get_root_privileges_for_testing(scenario.ctx());
        let mut court = create_court_for_testing(scenario.ctx());
        court.stake(
            coin::mint_for_testing<NVR>(
                alice_stake, 
                scenario.ctx()
            ), 
            scenario.ctx()
        );
        court.halt_operation(&ac, &cr);
        court.join_worker_pool(scenario.ctx());

        cr.destroy_court_registry_for_testing();
        ac.destroy_admin_cap_for_testing();
        court
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test, expected_failure(abort_code = 10, location = nivra::court)]
fun test_leave_worker_pool_without_joining() {
    let (alice, alice_stake) = (@0xA, 10_000_000);

    let mut scenario = test_scenario::begin(alice);
    let court = 
    {
        let mut court = create_court_for_testing(scenario.ctx());
        court.stake(
            coin::mint_for_testing<NVR>(
                alice_stake, 
                scenario.ctx()
            ), 
            scenario.ctx()
        );
        court.leave_worker_pool(scenario.ctx());
        court
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test, expected_failure]
fun test_join_worker_pool_without_stake() {
    let alice = @0xA;

    let mut scenario = test_scenario::begin(alice);
    let court = 
    {
        let mut court = create_court_for_testing(scenario.ctx());
        court.join_worker_pool(scenario.ctx());
        court
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test, expected_failure]
fun test_leave_worker_pool_without_stake() {
    let alice = @0xA;

    let mut scenario = test_scenario::begin(alice);
    let court = 
    {
        let mut court = create_court_for_testing(scenario.ctx());
        court.leave_worker_pool(scenario.ctx());
        court
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test]
fun test_open_dispute() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "A Test Dispute", 
            vector[alice, bob], 
            vector["yes", "no"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        clock.destroy_for_testing();
        contract_placeholder.delete();
    };
    scenario.next_tx(alice);
    {
        let dispute = scenario.take_shared<Dispute>();
        assert!(dispute.parties() == vector[alice, bob]);
        assert!(dispute.options() == vector["yes", "no"]);

        dispute.destroy_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test, expected_failure(abort_code = 4, location = nivra::court)]
fun test_open_dispute_halted() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let (cr, ac) = get_root_privileges_for_testing(scenario.ctx());
        let mut court = create_court_for_testing(scenario.ctx());
        court.halt_operation(&ac, &cr);

        cr.destroy_court_registry_for_testing();
        ac.destroy_admin_cap_for_testing();
        court
    };
    scenario.next_tx(alice);
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "A Test Dispute", 
            vector[alice, bob], 
            vector["yes", "no"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        clock.destroy_for_testing();
        contract_placeholder.delete();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test, expected_failure(abort_code = 11, location = nivra::court)]
fun test_open_dispute_invalid_fee() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee + 1, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "A Test Dispute", 
            vector[alice, bob], 
            vector["yes", "no"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        clock.destroy_for_testing();
        contract_placeholder.delete();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test, expected_failure(abort_code = 12, location = nivra::court)]
fun test_open_dispute_invalid_party_count() {
    let alice = @0xA;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "A Test Dispute", 
            vector[alice, alice], 
            vector["yes", "no"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        clock.destroy_for_testing();
        contract_placeholder.delete();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test, expected_failure(abort_code = 13, location = nivra::court)]
fun test_open_dispute_initiator_not_party() {
    let alice = @0xA;
    let bob = @0xB;
    let charlie = @0xC;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "A Test Dispute", 
            vector[bob, charlie], 
            vector["yes", "no"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        clock.destroy_for_testing();
        contract_placeholder.delete();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test, expected_failure(abort_code = 14, location = nivra::court)]
fun test_open_dispute_invalid_appeal_count() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "A Test Dispute", 
            vector[alice, bob], 
            vector["yes", "no"], 
            4, 
            &clock, 
            scenario.ctx()
        );

        clock.destroy_for_testing();
        contract_placeholder.delete();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test, expected_failure(abort_code = 15, location = nivra::court)]
fun test_open_dispute_too_long_description() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());
        let description = vector::tabulate!(2001, |_| 0u8);

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            description.to_string(), 
            vector[alice, bob], 
            vector["yes", "no"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        clock.destroy_for_testing();
        contract_placeholder.delete();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test, expected_failure(abort_code = 16, location = nivra::court)]
fun test_open_dispute_one_option() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        clock.destroy_for_testing();
        contract_placeholder.delete();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test, expected_failure(abort_code = 16, location = nivra::court)]
fun test_open_dispute_too_many_options() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "maybe", "somehow", "true", "false"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        clock.destroy_for_testing();
        contract_placeholder.delete();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test, expected_failure(abort_code = 17, location = nivra::court)]
fun test_open_dispute_duplicate_options() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ", "somehow", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        clock.destroy_for_testing();
        contract_placeholder.delete();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test, expected_failure(abort_code = 18, location = nivra::court)]
fun test_open_dispute_option_too_long() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());
        let long_option = vector::tabulate!(256, |_| 0u8);

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", long_option.to_string()], 
            3, 
            &clock, 
            scenario.ctx()
        );

        clock.destroy_for_testing();
        contract_placeholder.delete();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test, expected_failure(abort_code = 19, location = nivra::court)]
fun test_reopen_dispute_with_same_configs() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[bob, alice], 
            vector["お問い合わせ", "no", "yes"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        clock.destroy_for_testing();
        contract_placeholder.delete();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test]
fun test_reopen_dispute_with_different_configs() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["お問い合わせ", "no"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        clock.destroy_for_testing();
        contract_placeholder.delete();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test, expected_failure(abort_code = 44, location = nivra::court)]
fun test_open_dispute_zero_len_option() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        clock.destroy_for_testing();
        contract_placeholder.delete();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
}

#[test]
fun test_open_appeal() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let mut clock = 
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        contract_placeholder.delete();
        clock
    };
    scenario.next_tx(alice);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();
        let appeal_period_start = dispute.evidence_period_ms() + 
            dispute.voting_period_ms();

        // Trigger appeal period tallied
        dispute.set_status(dispute_status_tallied());
        clock.increment_for_testing(appeal_period_start + 1);

        court.open_appeal(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        assert!(dispute.appeals_used() == 1);

        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = 20, location = nivra::court)]
fun test_open_appeal_invalid_party() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let mut clock = 
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        contract_placeholder.delete();
        clock
    };
    scenario.next_tx(alice);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();
        let mut party_cap = scenario.take_from_sender<PartyCap>();
        let appeal_period_start = dispute.evidence_period_ms() + 
            dispute.voting_period_ms();

        // Trigger appeal period tallied
        dispute.set_status(dispute_status_tallied());
        clock.increment_for_testing(appeal_period_start + 1);

        // Change ID to an invalid dispute
        let dispute_placeholder = object::new(scenario.ctx());
        party_cap.set_id_for_testing(dispute_placeholder.to_inner());

        court.open_appeal(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        assert!(dispute.appeals_used() == 1);

        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
        dispute_placeholder.delete();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = 21, location = nivra::court)]
fun test_open_appeal_invalid_period() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let mut clock = 
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        contract_placeholder.delete();
        clock
    };
    scenario.next_tx(alice);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();
        let appeal_period_start = dispute.evidence_period_ms() + 
            dispute.voting_period_ms();

        // Try to open dispute before votes are tallied.
        dispute.set_status(dispute_status_active());
        clock.increment_for_testing(appeal_period_start + 1);

        court.open_appeal(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        assert!(dispute.appeals_used() == 1);

        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = 21, location = nivra::court)]
fun test_open_appeal_dispute_completed() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let mut clock = 
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        contract_placeholder.delete();
        clock
    };
    scenario.next_tx(alice);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();
        let appeal_period_start = dispute.evidence_period_ms() + 
            dispute.voting_period_ms() + dispute.appeal_period_ms();

        // Try to open dispute after appeal window is closed.
        dispute.set_status(dispute_status_tallied());
        clock.increment_for_testing(appeal_period_start + 1);

        court.open_appeal(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        assert!(dispute.appeals_used() == 1);

        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = 22, location = nivra::court)]
fun test_open_appeal_no_appeals_left() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let mut clock = 
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            0, 
            &clock, 
            scenario.ctx()
        );

        contract_placeholder.delete();
        clock
    };
    scenario.next_tx(alice);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();
        let appeal_period_start = dispute.evidence_period_ms() + 
            dispute.voting_period_ms();

        // Try to open dispute before votes are tallied.
        dispute.set_status(dispute_status_tallied());
        clock.increment_for_testing(appeal_period_start + 1);

        court.open_appeal(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        assert!(dispute.appeals_used() == 1);

        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = 11, location = nivra::court)]
fun test_open_appeal_invalid_fee() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let mut clock = 
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        contract_placeholder.delete();
        clock
    };
    scenario.next_tx(alice);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();
        let appeal_period_start = dispute.evidence_period_ms() + 
            dispute.voting_period_ms();

        dispute.set_status(dispute_status_tallied());
        clock.increment_for_testing(appeal_period_start + 1);

        court.open_appeal(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1) + 1, 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        assert!(dispute.appeals_used() == 1);

        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test]
fun test_accept_dispute() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let clock = 
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        contract_placeholder.delete();
        clock
    };
    scenario.next_tx(bob);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test]
fun test_accept_dispute_appeal() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let mut clock = 
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        contract_placeholder.delete();
        clock
    };
    scenario.next_tx(bob);
    let mut dispute = {
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        let appeal_period_start = dispute.evidence_period_ms() + 
            dispute.voting_period_ms();

        dispute.set_status(dispute_status_tallied());
        clock.increment_for_testing(appeal_period_start + 1);

        court.open_appeal(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        party_cap.destroy_party_cap_for_testing();
        dispute
    };
    scenario.next_tx(alice);
    {
        let party_cap = scenario.take_from_sender<PartyCap>();
        let dispute_fee = dispute.dispute_fee();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    dispute.destroy_for_testing();
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test]
fun test_accept_dispute_appeal_vice_versa() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let mut clock = 
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        contract_placeholder.delete();
        clock
    };
    scenario.next_tx(bob);
    let (mut dispute, bob_party_cap) = {
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );
        
        (dispute, party_cap)
    };
    scenario.next_tx(alice);
    {
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        let appeal_period_start = dispute.evidence_period_ms() + 
            dispute.voting_period_ms();

        dispute.set_status(dispute_status_tallied());
        clock.increment_for_testing(appeal_period_start + 1);

        court.open_appeal(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        party_cap.destroy_party_cap_for_testing();
    };
    scenario.next_tx(bob);
    {
        let dispute_fee = dispute.dispute_fee();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1), 
                scenario.ctx()
            ),  
            &bob_party_cap, 
            &clock
        );
    };
    test_scenario::end(scenario);
    dispute.destroy_for_testing();
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
    bob_party_cap.destroy_party_cap_for_testing();
}

#[test, expected_failure(abort_code = 9, location = nivra::court)]
fun test_accept_dispute_not_response_period() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let mut clock = 
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        contract_placeholder.delete();
        clock
    };
    scenario.next_tx(bob);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();
        
        clock.increment_for_testing(dispute.response_period_ms() + 1);

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = 20, location = nivra::court)]
fun test_accept_dispute_invalid_party_cap() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let clock = 
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        contract_placeholder.delete();
        clock
    };
    scenario.next_tx(bob);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();
        let mut party_cap = scenario.take_from_sender<PartyCap>();
        
        let dispute_placeholder = object::new(scenario.ctx());

        party_cap.set_id_for_testing(dispute_placeholder.to_inner());

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
        dispute_placeholder.delete();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = 23, location = nivra::court)]
fun test_accept_dispute_same_party() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let clock = 
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        contract_placeholder.delete();
        clock
    };
    scenario.next_tx(alice);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = 23, location = nivra::court)]
fun test_accept_dispute_appeal_same_party() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let mut clock = 
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        contract_placeholder.delete();
        clock
    };
    scenario.next_tx(bob);
    let dispute = {
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        let appeal_period_start = dispute.evidence_period_ms() + 
            dispute.voting_period_ms();

        dispute.set_status(dispute_status_tallied());
        clock.increment_for_testing(appeal_period_start + 1);

        court.open_appeal(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1), 
                scenario.ctx()
            ),  
            &party_cap, 
            &clock
        );

        party_cap.destroy_party_cap_for_testing();
        dispute
    };
    test_scenario::end(scenario);
    dispute.destroy_for_testing();
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = 23, location = nivra::court)]
fun test_accept_dispute_appeal_same_party_vice_versa() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let mut clock = 
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        contract_placeholder.delete();
        clock
    };
    scenario.next_tx(bob);
    let (mut dispute, bob_party_cap) = {
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );
        
        (dispute, party_cap)
    };
    scenario.next_tx(alice);
    {
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        let appeal_period_start = dispute.evidence_period_ms() + 
            dispute.voting_period_ms();

        dispute.set_status(dispute_status_tallied());
        clock.increment_for_testing(appeal_period_start + 1);

        court.open_appeal(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    dispute.destroy_for_testing();
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
    bob_party_cap.destroy_party_cap_for_testing();
}

#[test, expected_failure(abort_code = 11, location = nivra::court)]
fun test_accept_dispute_invalid_fee() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let clock = 
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        contract_placeholder.delete();
        clock
    };
    scenario.next_tx(bob);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0) + 1, 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = 9, location = nivra::court)]
fun test_accept_dispute_twice() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let clock = 
    {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            1, 
            &clock, 
            scenario.ctx()
        );

        contract_placeholder.delete();
        clock
    };
    scenario.next_tx(bob);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test]
fun test_draw_new_nivsters() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let clock = {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        court.stake(
            coin::mint_for_testing<NVR>(
                10_000_000, 
                scenario.ctx()
            ),  
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());

        contract_placeholder.delete();
        clock
    };
    scenario.create_system_objects();
    scenario.next_tx(bob);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let random = scenario.take_shared<Random>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        court.draw_new_nivsters(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        test_scenario::return_shared(random);
        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = 43, location = nivra::court)]
fun test_draw_new_nivsters_twice() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let clock = {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        court.stake(
            coin::mint_for_testing<NVR>(
                10_000_000, 
                scenario.ctx()
            ),  
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());

        contract_placeholder.delete();
        clock
    };
    scenario.create_system_objects();
    scenario.next_tx(bob);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let random = scenario.take_shared<Random>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        court.stake(
            coin::mint_for_testing<NVR>(
                10_000_000, 
                scenario.ctx()
            ),  
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        court.draw_new_nivsters(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        court.draw_new_nivsters(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        test_scenario::return_shared(random);
        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = 24, location = nivra::court)]
fun test_draw_new_nivsters_no_nivsters() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let clock = {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        contract_placeholder.delete();
        clock
    };
    scenario.create_system_objects();
    scenario.next_tx(bob);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let random = scenario.take_shared<Random>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        court.draw_new_nivsters(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        test_scenario::return_shared(random);
        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test]
fun test_draw_new_nivsters_appeal_round() {
    let alice = @0xA;
    let bob = @0xB;
    let charlie = @0xC;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(charlie);
    {
        court.stake(
            coin::mint_for_testing<NVR>(
                10_000_000, 
                scenario.ctx()
            ),  
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());
    };
    scenario.next_tx(alice);
    let mut clock = {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        court.stake(
            coin::mint_for_testing<NVR>(
                10_000_000, 
                scenario.ctx()
            ),  
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());

        contract_placeholder.delete();
        clock
    };
    scenario.create_system_objects();
    scenario.next_tx(bob);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let random = scenario.take_shared<Random>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        court.stake(
            coin::mint_for_testing<NVR>(
                10_000_000, 
                scenario.ctx()
            ),  
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());

        court.draw_new_nivsters(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        // skip to the appeal period
        let appeal_period_start = dispute.evidence_period_ms() + 
            dispute.voting_period_ms();

        dispute.set_status(dispute_status_tallied());
        clock.increment_for_testing(appeal_period_start + 1);

        court.open_appeal(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        // skip to the draw period
        dispute.set_status(dispute_status_draw());

        court.draw_new_nivsters(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        // The remaining 2 stakers should have been drawn from the worker pool.
        assert!(court.worker_pool().length() == 0);

        test_scenario::return_shared(random);
        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test]
fun test_handle_dispute_tie() {
    let alice = @0xA;
    let bob = @0xB;
    let charlie = @0xC;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(charlie);
    {
        court.stake(
            coin::mint_for_testing<NVR>(
                10_000_000, 
                scenario.ctx()
            ),  
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());
    };
    scenario.next_tx(alice);
    let mut clock = {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        contract_placeholder.delete();
        clock
    };
    scenario.create_system_objects();
    scenario.next_tx(bob);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let random = scenario.take_shared<Random>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        court.stake(
            coin::mint_for_testing<NVR>(
                10_000_000, 
                scenario.ctx()
            ),  
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());

        court.draw_new_nivsters(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        // skip to the appeal period (tie)
        let appeal_period_start = dispute.evidence_period_ms() + 
            dispute.voting_period_ms();

        dispute.set_status(dispute_status_tie());
        clock.increment_for_testing(appeal_period_start + 1);

        court.handle_dispute_tie(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        assert!(court.worker_pool().length() == 0);

        test_scenario::return_shared(random);
        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test, expected_failure(abort_code = 25, location = nivra::court)]
fun test_handle_dispute_tie_wrong_period() {
    let alice = @0xA;
    let bob = @0xB;
    let charlie = @0xC;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(charlie);
    {
        court.stake(
            coin::mint_for_testing<NVR>(
                10_000_000, 
                scenario.ctx()
            ),  
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());
    };
    scenario.next_tx(alice);
    let mut clock = {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        contract_placeholder.delete();
        clock
    };
    scenario.create_system_objects();
    scenario.next_tx(bob);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let random = scenario.take_shared<Random>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        court.stake(
            coin::mint_for_testing<NVR>(
                10_000_000, 
                scenario.ctx()
            ),  
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());

        court.draw_new_nivsters(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        // skip to the appeal period
        let appeal_period_start = dispute.evidence_period_ms() + 
            dispute.voting_period_ms();

        clock.increment_for_testing(appeal_period_start + 1);

        court.handle_dispute_tie(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        assert!(court.worker_pool().length() == 0);

        test_scenario::return_shared(random);
        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
}

#[test]
fun test_cancel_dispute_no_nivsters() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let (mut clock, contract) = {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        (clock, contract_placeholder)
    };
    scenario.create_system_objects();
    scenario.next_tx(bob);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        // skip to draw period end
        let draw_period_end = dispute.draw_period_ms();

        clock.increment_for_testing(draw_period_end + 1);

        // Dispute should be now cancelable since no nivsters have been drawn.
        court.cancel_dispute(
            &mut dispute, 
            &clock, 
            scenario.ctx()
        );

        assert!(court.reward_pool().value() == 0);

        // Open new dispute with same configs
        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
    contract.delete();
}

#[test]
fun test_cancel_dispute_no_votes() {
    let alice = @0xA;
    let bob = @0xB;
    let charlie = @0xC;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(charlie);
    {
        court.stake(
            coin::mint_for_testing<NVR>(
                10_000_000, 
                scenario.ctx()
            ),  
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());
    };
    scenario.next_tx(alice);
    let (mut clock, contract) = {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        (clock, contract_placeholder)
    };
    scenario.create_system_objects();
    scenario.next_tx(bob);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let random = scenario.take_shared<Random>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        court.draw_new_nivsters(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        dispute.set_status(dispute_status_active());
        let completed = dispute.evidence_period_ms() +
            dispute.voting_period_ms() + dispute.appeal_period_ms();

        clock.increment_for_testing(completed + 1);

        // Dispute should be now cancelable since no nivsters have been drawn.
        court.cancel_dispute(
            &mut dispute, 
            &clock, 
            scenario.ctx()
        );

        assert!(court.reward_pool().value() == 0);
        assert!(court.stakes().borrow(charlie).amount() == 10_000_000);

        // Open new dispute with same configs
        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
        test_scenario::return_shared(random);
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
    contract.delete();
}

#[test]
fun test_cancel_dispute_unresolved_tie() {
    let alice = @0xA;
    let bob = @0xB;
    let charlie = @0xC;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(charlie);
    {
        court.stake(
            coin::mint_for_testing<NVR>(
                10_000_000, 
                scenario.ctx()
            ),  
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());
    };
    scenario.next_tx(alice);
    let (mut clock, contract) = {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        (clock, contract_placeholder)
    };
    scenario.create_system_objects();
    scenario.next_tx(bob);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let random = scenario.take_shared<Random>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        court.draw_new_nivsters(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        dispute.set_status(dispute_status_tie());
        let completed = dispute.evidence_period_ms() +
            dispute.voting_period_ms() + dispute.appeal_period_ms();

        clock.increment_for_testing(completed + 1);

        // Dispute should be now cancelable since no nivsters have been drawn.
        court.cancel_dispute(
            &mut dispute, 
            &clock, 
            scenario.ctx()
        );

        assert!(court.reward_pool().value() == 0);
        assert!(court.stakes().borrow(charlie).amount() == 10_000_000);

        // Open new dispute with same configs
        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        test_scenario::return_shared(random);
        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
    contract.delete();
}

#[test, expected_failure(abort_code = 34, location = nivra::court)]
fun test_cancel_dispute_twice() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let (mut clock, contract) = {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        (clock, contract_placeholder)
    };
    scenario.create_system_objects();
    scenario.next_tx(bob);
    {
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        dispute.set_status(dispute_status_active());
        let completed = dispute.evidence_period_ms() +
            dispute.voting_period_ms() + dispute.appeal_period_ms();

        clock.increment_for_testing(completed + 1);

        court.cancel_dispute(
            &mut dispute, 
            &clock, 
            scenario.ctx()
        );

        court.cancel_dispute(
            &mut dispute, 
            &clock, 
            scenario.ctx()
        );

        dispute.destroy_for_testing();
        party_cap.destroy_party_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
    contract.delete();
}

#[test]
fun test_resolve_one_sided_dispute_no_nivsters() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let (mut clock, contract) = {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        (clock, contract_placeholder)
    };
    scenario.create_system_objects();
    scenario.next_tx(bob);
    {
        let (cr, ac) = get_root_privileges_for_testing(scenario.ctx());
        let mut dispute = scenario.take_shared<Dispute>();

        // Skip to the end of response period.
        clock.increment_for_testing(dispute.response_period_ms() + 1);

        court.resolve_one_sided_dispute(
            &mut dispute, 
            &cr, 
            &clock, 
            scenario.ctx()
        );

        assert!(court.reward_pool().value() == 0);

        dispute.destroy_for_testing();
        cr.destroy_court_registry_for_testing();
        ac.destroy_admin_cap_for_testing();
    };
    scenario.next_tx(bob);
    {
        let result = scenario.take_from_sender<Result>();

        assert!(result.winner_party() == alice);
        assert!(result.winner_option() == option::none());

        scenario.return_to_sender(result);
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
    contract.delete();
}

#[test]
fun test_resolve_one_sided_dispute_appeal() {
    let alice = @0xA;
    let bob = @0xB;
    let charlie = @0xC;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(charlie);
    {
        court.stake(
            coin::mint_for_testing<NVR>(
                10_000_000, 
                scenario.ctx()
            ),  
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());
    };
    scenario.next_tx(alice);
    let (mut clock, contract) = {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        (clock, contract_placeholder)
    };
    scenario.create_system_objects();
    scenario.next_tx(bob);
    let dispute = {
        let mut dispute = scenario.take_shared<Dispute>();
        let random = scenario.take_shared<Random>();
        let dispute_fee = dispute.dispute_fee();
        let party_cap = scenario.take_from_sender<PartyCap>();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        court.draw_new_nivsters(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        dispute.set_status(dispute_status_tallied());
        let appeal_period = dispute.evidence_period_ms() +
            dispute.voting_period_ms();

        clock.increment_for_testing(appeal_period + 1);

        court.open_appeal(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        let (cr, ac) = get_root_privileges_for_testing(scenario.ctx());
        clock.increment_for_testing(dispute.response_period_ms() + 1);

        court.resolve_one_sided_dispute(
            &mut dispute, 
            &cr, 
            &clock, 
            scenario.ctx()
        );

        cr.destroy_court_registry_for_testing();
        ac.destroy_admin_cap_for_testing();
        test_scenario::return_shared(random);
        party_cap.destroy_party_cap_for_testing();

        dispute
    };
    scenario.next_tx(alice);
    {
        let result = scenario.take_from_sender<Result>();

        assert!(result.winner_party() == bob);
        assert!(result.winner_option() == option::none());

        let charlie_stake = court.stakes().borrow(charlie);

        assert!(charlie_stake.amount() == 10_000_000);

        let reward = nivsters_take(
            dispute.dispute_fee(), 
            dispute.treasury_share(), 
            0, 
            dispute.init_nivster_count()
        );

        assert!(charlie_stake.reward_amount() == reward);
        assert!(court.reward_pool().value() == reward);

        scenario.return_to_sender(result);
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
    contract.delete();
    dispute.destroy_for_testing();
}

#[test, expected_failure(abort_code = 35, location = nivra::court)]
fun test_resolve_one_sided_dispute_twice() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let (mut clock, contract) = {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        (clock, contract_placeholder)
    };
    scenario.create_system_objects();
    scenario.next_tx(bob);
    {
        let (cr, ac) = get_root_privileges_for_testing(scenario.ctx());
        let mut dispute = scenario.take_shared<Dispute>();

        // Skip to the end of response period.
        clock.increment_for_testing(dispute.response_period_ms() + 1);

        court.resolve_one_sided_dispute(
            &mut dispute, 
            &cr, 
            &clock, 
            scenario.ctx()
        );

        court.resolve_one_sided_dispute(
            &mut dispute, 
            &cr, 
            &clock, 
            scenario.ctx()
        );

        dispute.destroy_for_testing();
        cr.destroy_court_registry_for_testing();
        ac.destroy_admin_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
    contract.delete();
}

#[test, expected_failure(abort_code = 19, location = nivra::court)]
fun test_resolve_one_sided_dispute_reopen_dispute() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let mut court = 
    {
        let court = create_court_for_testing(scenario.ctx());
        court
    };
    scenario.next_tx(alice);
    let (mut clock, contract) = {
        let contract_placeholder = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();
        let clock = clock::create_for_testing(scenario.ctx());

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract_placeholder.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        (clock, contract_placeholder)
    };
    scenario.create_system_objects();
    scenario.next_tx(bob);
    {
        let (cr, ac) = get_root_privileges_for_testing(scenario.ctx());
        let mut dispute = scenario.take_shared<Dispute>();

        // Skip to the end of response period.
        clock.increment_for_testing(dispute.response_period_ms() + 1);

        court.resolve_one_sided_dispute(
            &mut dispute, 
            &cr, 
            &clock, 
            scenario.ctx()
        );

        let dispute_fee = court.dispute_fee_internal();

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no", "お問い合わせ"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        dispute.destroy_for_testing();
        cr.destroy_court_registry_for_testing();
        ac.destroy_admin_cap_for_testing();
    };
    test_scenario::end(scenario);
    court.destroy_court_for_testing();
    clock.destroy_for_testing();
    contract.delete();
}

#[test]
fun test_complete_dispute_party_only_vote() {
    let (alice, alice_stake) = (@0xA, 10_000_000);
    let (bob, bob_stake) = (@0xB, 15_000_000);
    let (charlie, charlie_stake) = (@0xC, 25_000_000);

    let mut scenario = test_scenario::begin(alice);
    scenario.create_system_objects();
    let (mut clock, random, mut court) = {
        let clock = scenario.take_shared<Clock>();
        let random = scenario.take_shared<Random>();
        let court = create_court_for_testing(scenario.ctx());

        (clock, random, court)
    };
    
    vector[alice, bob, charlie].zip_do!(
        vector[alice_stake, bob_stake, charlie_stake], |addr, stake| {
            scenario.next_tx(addr);
            {
                court.stake(
                    coin::mint_for_testing<NVR>(
                        stake, 
                        scenario.ctx()
                    ),  
                    scenario.ctx()
                );
                court.join_worker_pool(scenario.ctx());
            };
        }
    );

    scenario.next_tx(alice);
    {
        let contract = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract.as_inner(), 
            "", 
            vector[alice, bob], 
            vector[], 
            3, 
            &clock, 
            scenario.ctx()
        );

        contract.delete();
    };
    scenario.next_tx(bob);
    let mut dispute = 
    {
        let party_cap = scenario.take_from_sender<PartyCap>();
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ),  
            &party_cap, 
            &clock
        );

        court.draw_new_nivsters(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        let appeal_period = dispute.evidence_period_ms() + 
            dispute.voting_period_ms();
        dispute.set_status(dispute_status_tallied());
        clock.increment_for_testing(appeal_period + 1);

        court.open_appeal(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1), 
                scenario.ctx()
            ),  
            &party_cap, 
            &clock
        );

        scenario.return_to_sender(party_cap);
        dispute
    };
    scenario.next_tx(alice);
    {
        let party_cap = scenario.take_from_sender<PartyCap>();
        let dispute_fee = dispute.dispute_fee();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        court.draw_new_nivsters(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        scenario.return_to_sender(party_cap);
    };

    // Spoof votes for testing.
    let a_voter_details = dispute.voters_mut().borrow_mut(alice);
    a_voter_details.set_party_vote(option::some(0));

    let b_voter_details = dispute.voters_mut().borrow_mut(bob);
    b_voter_details.set_party_vote(option::some(0));

    let c_voter_details = dispute.voters_mut().borrow_mut(charlie);
    c_voter_details.set_party_vote(option::some(1));

    dispute.set_party_results(vector[2, 1]);
    dispute.set_winner_party(option::some(0));

    scenario.next_tx(alice);
    {
        let (cr, ac) = get_root_privileges_for_testing(scenario.ctx());
        let timetable_end = dispute.evidence_period_ms() + 
            dispute.voting_period_ms() + dispute.response_period_ms();
        clock.increment_for_testing(timetable_end + 1);
        dispute.set_status(dispute_status_tallied());

        court.complete_dispute(
            &mut dispute, 
            &cr, 
            &clock, 
            scenario.ctx()
        );

        cr.destroy_court_registry_for_testing();
        ac.destroy_admin_cap_for_testing();
    };
    scenario.next_tx(bob);
    {
        let result = scenario.take_from_sender<Result>();

        assert!(result.winner_party() == alice);
        assert!(result.winner_option().is_none());

        let nivsters_share = nivsters_take(
            dispute.dispute_fee(), 
            dispute.treasury_share(), 
            dispute.appeals_used(), 
            dispute.init_nivster_count()
        );

        assert!(court.reward_pool().value() == nivsters_share);
        assert!(court.stake_pool().value() == 49_775_000);
        assert!(court.stakes().borrow(charlie).amount() == 23_500_000);
        assert!(court.stakes().borrow(alice).amount() == 10_637_500);
        assert!(court.stakes().borrow(bob).amount() == 15_637_500);

        scenario.return_to_sender(result);
    };

    test_scenario::return_shared(clock);
    test_scenario::return_shared(random);
    court.destroy_court_for_testing();
    dispute.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_complete_dispute() {
    let (alice, alice_stake) = (@0xA, 10_000_000);
    let (bob, bob_stake) = (@0xB, 15_000_000);
    let (charlie, charlie_stake) = (@0xC, 25_000_000);

    let mut scenario = test_scenario::begin(alice);
    scenario.create_system_objects();
    let (mut clock, random, mut court) = {
        let clock = scenario.take_shared<Clock>();
        let random = scenario.take_shared<Random>();
        let court = create_court_for_testing(scenario.ctx());

        (clock, random, court)
    };
    
    vector[alice, bob, charlie].zip_do!(
        vector[alice_stake, bob_stake, charlie_stake], |addr, stake| {
            scenario.next_tx(addr);
            {
                court.stake(
                    coin::mint_for_testing<NVR>(
                        stake, 
                        scenario.ctx()
                    ),  
                    scenario.ctx()
                );
                court.join_worker_pool(scenario.ctx());
            };
        }
    );

    scenario.next_tx(alice);
    {
        let contract = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        contract.delete();
    };
    scenario.next_tx(bob);
    let mut dispute = 
    {
        let party_cap = scenario.take_from_sender<PartyCap>();
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ),  
            &party_cap, 
            &clock
        );

        court.draw_new_nivsters(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        let appeal_period = dispute.evidence_period_ms() + 
            dispute.voting_period_ms();
        dispute.set_status(dispute_status_tallied());
        clock.increment_for_testing(appeal_period + 1);

        court.open_appeal(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1), 
                scenario.ctx()
            ),  
            &party_cap, 
            &clock
        );

        scenario.return_to_sender(party_cap);
        dispute
    };
    scenario.next_tx(alice);
    {
        let party_cap = scenario.take_from_sender<PartyCap>();
        let dispute_fee = dispute.dispute_fee();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 1), 
                scenario.ctx()
            ), 
            &party_cap, 
            &clock
        );

        court.draw_new_nivsters(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        scenario.return_to_sender(party_cap);
    };

    // Spoof votes for testing.
    let a_voter_details = dispute.voters_mut().borrow_mut(alice);
    a_voter_details.set_vote(option::some(0));
    a_voter_details.set_party_vote(option::some(0));

    let b_voter_details = dispute.voters_mut().borrow_mut(bob);
    b_voter_details.set_vote(option::some(0));
    b_voter_details.set_party_vote(option::some(0));

    let c_voter_details = dispute.voters_mut().borrow_mut(charlie);
    c_voter_details.set_vote(option::some(1));
    c_voter_details.set_party_vote(option::some(1));

    dispute.set_results(vector[2, 1]);
    dispute.set_party_results(vector[2, 1]);
    dispute.set_winner_option(option::some(0));
    dispute.set_winner_party(option::some(0));

    scenario.next_tx(alice);
    {
        let (cr, ac) = get_root_privileges_for_testing(scenario.ctx());
        let timetable_end = dispute.evidence_period_ms() + 
            dispute.voting_period_ms() + dispute.response_period_ms();
        clock.increment_for_testing(timetable_end + 1);
        dispute.set_status(dispute_status_tallied());

        court.complete_dispute(
            &mut dispute, 
            &cr, 
            &clock, 
            scenario.ctx()
        );

        cr.destroy_court_registry_for_testing();
        ac.destroy_admin_cap_for_testing();
    };
    scenario.next_tx(bob);
    {
        let result = scenario.take_from_sender<Result>();

        assert!(result.winner_party() == alice);
        assert!(*result.winner_option().borrow() == "yes");

        let nivsters_share = nivsters_take(
            dispute.dispute_fee(), 
            dispute.treasury_share(), 
            dispute.appeals_used(), 
            dispute.init_nivster_count()
        );

        assert!(court.reward_pool().value() == nivsters_share);
        assert!(court.stake_pool().value() == 49_775_000);
        assert!(court.stakes().borrow(charlie).amount() == 23_500_000);
        assert!(court.stakes().borrow(alice).amount() == 10_637_500);
        assert!(court.stakes().borrow(bob).amount() == 15_637_500);

        scenario.return_to_sender(result);
    };

    test_scenario::return_shared(clock);
    test_scenario::return_shared(random);
    court.destroy_court_for_testing();
    dispute.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_complete_dispute_majority_only() {
    let alice = @0xA;
    let bob = @0xB;
    let min_stake = 10_000_000;

    let mut scenario = test_scenario::begin(alice);
    scenario.create_system_objects();
    let (mut clock, random, mut court) = {
        let clock = scenario.take_shared<Clock>();
        let random = scenario.take_shared<Random>();
        let court = create_court_for_testing(scenario.ctx());

        (clock, random, court)
    };
    scenario.next_tx(bob);
    {
        court.stake(
            coin::mint_for_testing<NVR>(
                min_stake, 
                scenario.ctx()
            ),  
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());
    };

    scenario.next_tx(alice);
    {
        let contract = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        contract.delete();
    };
    scenario.next_tx(bob);
    let mut dispute = 
    {
        let party_cap = scenario.take_from_sender<PartyCap>();
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ),  
            &party_cap, 
            &clock
        );

        court.draw_new_nivsters(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        scenario.return_to_sender(party_cap);
        dispute
    };

    // Spoof votes for testing.
    let b_voter_details = dispute.voters_mut().borrow_mut(bob);
    b_voter_details.set_vote(option::some(1));
    b_voter_details.set_party_vote(option::some(0));

    dispute.set_results(vector[0, 1]);
    dispute.set_party_results(vector[1, 0]);
    dispute.set_winner_option(option::some(1));
    dispute.set_winner_party(option::some(0));

    scenario.next_tx(alice);
    {
        let (cr, ac) = get_root_privileges_for_testing(scenario.ctx());
        let timetable_end = dispute.evidence_period_ms() + 
            dispute.voting_period_ms() + dispute.response_period_ms();
        clock.increment_for_testing(timetable_end + 1);
        dispute.set_status(dispute_status_tallied());

        court.complete_dispute(
            &mut dispute, 
            &cr, 
            &clock, 
            scenario.ctx()
        );

        cr.destroy_court_registry_for_testing();
        ac.destroy_admin_cap_for_testing();
    };
    scenario.next_tx(bob);
    {
        let result = scenario.take_from_sender<Result>();

        assert!(result.winner_party() == alice);
        assert!(*result.winner_option().borrow() == "no");

        let nivsters_share = nivsters_take(
            dispute.dispute_fee(), 
            dispute.treasury_share(), 
            dispute.appeals_used(), 
            dispute.init_nivster_count()
        );

        assert!(court.reward_pool().value() == nivsters_share);
        assert!(court.stakes().borrow(bob).amount() == min_stake);
        assert!(court.stakes().borrow(bob).reward_amount() == nivsters_share);

        scenario.return_to_sender(result);
    };

    test_scenario::return_shared(clock);
    test_scenario::return_shared(random);
    court.destroy_court_for_testing();
    dispute.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_complete_dispute_party_vote_majority_only() {
    let alice = @0xA;
    let bob = @0xB;
    let min_stake = 10_000_000;

    let mut scenario = test_scenario::begin(alice);
    scenario.create_system_objects();
    let (mut clock, random, mut court) = {
        let clock = scenario.take_shared<Clock>();
        let random = scenario.take_shared<Random>();
        let court = create_court_for_testing(scenario.ctx());

        (clock, random, court)
    };
    scenario.next_tx(bob);
    {
        court.stake(
            coin::mint_for_testing<NVR>(
                min_stake, 
                scenario.ctx()
            ),  
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());
    };

    scenario.next_tx(alice);
    {
        let contract = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        contract.delete();
    };
    scenario.next_tx(bob);
    let mut dispute = 
    {
        let party_cap = scenario.take_from_sender<PartyCap>();
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ),  
            &party_cap, 
            &clock
        );

        court.draw_new_nivsters(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        scenario.return_to_sender(party_cap);
        dispute
    };

    // Spoof votes for testing.
    let b_voter_details = dispute.voters_mut().borrow_mut(bob);
    b_voter_details.set_party_vote(option::some(1));

    dispute.set_party_results(vector[0, 1]);
    dispute.set_winner_party(option::some(1));

    scenario.next_tx(alice);
    {
        let (cr, ac) = get_root_privileges_for_testing(scenario.ctx());
        let timetable_end = dispute.evidence_period_ms() + 
            dispute.voting_period_ms() + dispute.response_period_ms();
        clock.increment_for_testing(timetable_end + 1);
        dispute.set_status(dispute_status_tallied());

        court.complete_dispute(
            &mut dispute, 
            &cr, 
            &clock, 
            scenario.ctx()
        );

        cr.destroy_court_registry_for_testing();
        ac.destroy_admin_cap_for_testing();
    };
    scenario.next_tx(bob);
    {
        let result = scenario.take_from_sender<Result>();

        assert!(result.winner_party() == bob);
        assert!(result.winner_option().is_none());

        let nivsters_share = nivsters_take(
            dispute.dispute_fee(), 
            dispute.treasury_share(), 
            dispute.appeals_used(), 
            dispute.init_nivster_count()
        );

        assert!(court.reward_pool().value() == nivsters_share);
        assert!(court.stakes().borrow(bob).amount() == min_stake);
        assert!(court.stakes().borrow(bob).reward_amount() == nivsters_share);

        scenario.return_to_sender(result);
    };

    test_scenario::return_shared(clock);
    test_scenario::return_shared(random);
    court.destroy_court_for_testing();
    dispute.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = 26, location = nivra::court)]
fun test_complete_dispute_twice() {
    let alice = @0xA;
    let bob = @0xB;
    let min_stake = 10_000_000;

    let mut scenario = test_scenario::begin(alice);
    scenario.create_system_objects();
    let (mut clock, random, mut court) = {
        let clock = scenario.take_shared<Clock>();
        let random = scenario.take_shared<Random>();
        let court = create_court_for_testing(scenario.ctx());

        (clock, random, court)
    };
    scenario.next_tx(bob);
    {
        court.stake(
            coin::mint_for_testing<NVR>(
                min_stake, 
                scenario.ctx()
            ),  
            scenario.ctx()
        );
        court.join_worker_pool(scenario.ctx());
    };

    scenario.next_tx(alice);
    {
        let contract = object::new(scenario.ctx());
        let dispute_fee = court.dispute_fee_internal();

        court.open_dispute(
            coin::mint_for_testing<SUI>(
                dispute_fee, 
                scenario.ctx()
            ), 
            *contract.as_inner(), 
            "", 
            vector[alice, bob], 
            vector["yes", "no"], 
            3, 
            &clock, 
            scenario.ctx()
        );

        contract.delete();
    };
    scenario.next_tx(bob);
    let mut dispute = 
    {
        let party_cap = scenario.take_from_sender<PartyCap>();
        let mut dispute = scenario.take_shared<Dispute>();
        let dispute_fee = dispute.dispute_fee();

        court.accept_dispute(
            &mut dispute, 
            coin::mint_for_testing<SUI>(
                dispute_fee(dispute_fee, 0), 
                scenario.ctx()
            ),  
            &party_cap, 
            &clock
        );

        court.draw_new_nivsters(
            &mut dispute, 
            &clock, 
            &random, 
            scenario.ctx()
        );

        scenario.return_to_sender(party_cap);
        dispute
    };

    // Spoof votes for testing.
    let b_voter_details = dispute.voters_mut().borrow_mut(bob);
    b_voter_details.set_party_vote(option::some(1));

    dispute.set_party_results(vector[0, 1]);
    dispute.set_winner_party(option::some(1));

    scenario.next_tx(alice);
    {
        let (cr, ac) = get_root_privileges_for_testing(scenario.ctx());
        let timetable_end = dispute.evidence_period_ms() + 
            dispute.voting_period_ms() + dispute.response_period_ms();
        clock.increment_for_testing(timetable_end + 1);
        dispute.set_status(dispute_status_tallied());

        court.complete_dispute(
            &mut dispute, 
            &cr, 
            &clock, 
            scenario.ctx()
        );

        court.complete_dispute(
            &mut dispute, 
            &cr, 
            &clock, 
            scenario.ctx()
        );

        cr.destroy_court_registry_for_testing();
        ac.destroy_admin_cap_for_testing();
    };

    test_scenario::return_shared(clock);
    test_scenario::return_shared(random);
    court.destroy_court_for_testing();
    dispute.destroy_for_testing();
    scenario.end();
}

#[test]
fun test_nivsters_take() {
    let dispute_fee = 10_000_000_000;
    let treasury_share = 5; // in percentages scaled by 100
    let appeals = 0;
    let init_nivster_count = 10;

    // The expected cut is F(n) * (1 - a), where F(n) = dispute_fee and
    // a = treasury_share [0,1]
    let cut = nivsters_take(
        dispute_fee, 
        treasury_share, 
        appeals, 
        init_nivster_count
    );

    assert!(cut == 9_500_000_000);

    // The expected cut is F(n) * (1 - a) * (2^i + (2^i - 1) / N) + round(0) cut
    //, where i = appeals and N = init_nivster_count
    let appeals = 1;
    let cut = nivsters_take(
        dispute_fee, 
        treasury_share, 
        appeals, 
        init_nivster_count
    );

    assert!(cut == 29_450_000_000);

    let appeals = 2;
    let cut = nivsters_take(
        dispute_fee, 
        treasury_share, 
        appeals, 
        init_nivster_count
    );

    assert!(cut == 70_300_000_000);

    let dispute_fee = 9_999_999_997;
    let treasury_share = 25;
    let appeals = 0;
    let init_nivster_count = 3;

    let cut = nivsters_take(
        dispute_fee, 
        treasury_share, 
        appeals, 
        init_nivster_count
    );

    assert!(cut == 7_499_999_998);

    let appeals = 1;
    let cut = nivsters_take(
        dispute_fee, 
        treasury_share, 
        appeals, 
        init_nivster_count
    );

    assert!(cut == 24_999_999_993);
}