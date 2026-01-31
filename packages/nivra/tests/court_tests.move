#[test_only]
module nivra::court_tests;

use nivra::court::nivsters_take;
use sui::test_scenario;
use nivra::court::create_court_for_testing;
use token::nvr::NVR;
use sui::coin;
use nivra::court_registry::get_root_privileges_for_testing;

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