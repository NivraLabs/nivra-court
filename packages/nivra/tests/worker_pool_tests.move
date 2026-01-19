#[test_only]
module nivra::worker_pool_tests;

use nivra::worker_pool;
use sui::test_scenario;
use sui::test_scenario::ctx;

#[test]
fun test_prefix_sum() {
    let (alice, alice_stake) = (@0x1, 100_000_000);
    let (bob, bob_stake) = (@0x2, 500_000_000);
    let (charlie, charlie_stake) = (@0x3, 300_000_000);

    let mut scenario = test_scenario::begin(alice);
    
    let mut worker_pool = worker_pool::empty(ctx(&mut scenario));
    worker_pool.push_back(alice, alice_stake);
    worker_pool.push_back(bob, bob_stake);
    worker_pool.push_back(charlie, charlie_stake);

    assert!(worker_pool.prefix_sum(2) == 900_000_000, 0);

    worker_pool.swap_remove(0); // Alice
    assert!(worker_pool.prefix_sum(1) == 800_000_000, 0);

    worker_pool.swap_remove(1); // Bob
    assert!(worker_pool.prefix_sum(0) == 300_000_000, 0);

    worker_pool.swap_remove(0); // Charlie
    worker_pool.destroy_empty();

    test_scenario::end(scenario);
}

#[test]
fun test_prefix_sum_100() {
    let mut scenario = test_scenario::begin(@0x0);
    let mut worker_pool = worker_pool::empty(ctx(&mut scenario));

    let mut i = 1;

    while (i <= 100) {
        worker_pool.push_back(sui::address::from_u256(i), i as u64);
        i = i + 1;
    };

    assert!(worker_pool.prefix_sum(99) == 5050, 0);
    assert!(worker_pool.prefix_sum(49) == 1275, 0);

    // Remove 100 from the end
    worker_pool.swap_remove(99);
    assert!(worker_pool.prefix_sum(98) == 4950, 0);

    // Remove 1 from the start
    worker_pool.swap_remove(0);
    assert!(worker_pool.prefix_sum(97) == 4949, 0);

    // Add 1000
    worker_pool.push_back(@0x0, 1000);
    assert!(worker_pool.prefix_sum(98) == 5949, 0);

    worker_pool.destroy();
    test_scenario::end(scenario);
}

#[test]
fun test_search() {
    let (alice, alice_stake) = (@0x1, 100_000_000);
    let (bob, bob_stake) = (@0x2, 500_000_000);
    let (charlie, charlie_stake) = (@0x3, 300_000_000);
    let (damien, damien_stake) = (@0x4, 100_000_000);

    let mut scenario = test_scenario::begin(alice);

    let mut worker_pool = worker_pool::empty(ctx(&mut scenario));
    worker_pool.push_back(alice, alice_stake);
    worker_pool.push_back(bob, bob_stake);
    worker_pool.push_back(charlie, charlie_stake);
    worker_pool.push_back(damien, damien_stake);

    assert!(worker_pool.search(0) == 0, 0);
    assert!(worker_pool.search(50_000_000) == 0, 0);
    assert!(worker_pool.search(100_000_000) == 0, 0);
    assert!(worker_pool.search(100_000_001) == 1, 0);
    assert!(worker_pool.search(450_000_000) == 1, 0);
    assert!(worker_pool.search(600_000_000) == 1, 0);
    assert!(worker_pool.search(600_000_001) == 2, 0);
    assert!(worker_pool.search(900_000_000) == 2, 0);
    assert!(worker_pool.search(900_000_001) == 3, 0);
    assert!(worker_pool.search(1_000_000_000) == 3, 0);

    worker_pool.destroy();
    test_scenario::end(scenario);
}

#[test]
fun test_search_100() {
    let mut scenario = test_scenario::begin(@0x0);
    let mut worker_pool = worker_pool::empty(ctx(&mut scenario));

    let mut i = 1;

    while (i <= 100) {
        worker_pool.push_back(sui::address::from_u256(i), i as u64);
        i = i + 1;
    };

    // (4950 - 5050] range
    assert!(worker_pool.search(5050) == 99, 0);
    assert!(worker_pool.search(5000) == 99, 0);
    // (4851 - 4950] range
    assert!(worker_pool.search(4950) == 98, 0);
    assert!(worker_pool.search(4925) == 98, 0);
    assert!(worker_pool.search(4852) == 98, 0);
    // [0 - 1] range
    assert!(worker_pool.search(1) == 0, 0);
    assert!(worker_pool.search(0) == 0, 0);

    // Remove 1 and swap with 100
    worker_pool.swap_remove(0);
    assert!(worker_pool.search(100) == 0, 0);
    assert!(worker_pool.search(50) == 0, 0);

    // (100 - 102] range
    assert!(worker_pool.search(101) == 1, 0);

    // (102 - 105] range
    assert!(worker_pool.search(105) == 2, 0);

    // Last element matches the new sum
    assert!(worker_pool.search(5049) == 98, 0);

    worker_pool.destroy();
    test_scenario::end(scenario);
}