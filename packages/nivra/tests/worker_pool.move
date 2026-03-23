// © 2026 Nivra Labs Ltd.

#[test_only]
module nivra::worker_pool_tests {
    use nivra::worker_pool;

    #[test]
    fun test_fenwick_tree_search_boundary() {
        let mut pool = worker_pool::empty();

        // push_back
        worker_pool::push_back(&mut pool, @0xA, 10);
        worker_pool::push_back(&mut pool, @0xB, 20);

        // prefix_sum(0) should be 10. prefix_sum(1) should be 30.
        assert!(worker_pool::prefix_sum(&pool, 0) == 10, 0);
        assert!(worker_pool::prefix_sum(&pool, 1) == 30, 0);

        // Search thresholds:
        // 0..10 should map to A
        // 11..30 should map to B
        let addr_9 = worker_pool::search(&pool, 10);
        let addr_10 = worker_pool::search(&pool, 30);

        assert!(addr_9 == @0xA, 1);
        assert!(addr_10 == @0xB, 2);
    }

    #[test]
    fun test_push_and_prefix_sum() {
        let mut pool = worker_pool::empty();

        let idx1 = worker_pool::push_back(&mut pool, @0xA, 100);
        let idx2 = worker_pool::push_back(&mut pool, @0xB, 200);

        assert!(idx1 == 0, 0);
        assert!(idx2 == 1, 0);

        assert!(worker_pool::prefix_sum(&pool, 0) == 100, 0);
        assert!(worker_pool::prefix_sum(&pool, 1) == 300, 0);
        assert!(worker_pool::length(&pool) == 2, 0);
    }

    #[test]
    fun test_swap_remove() {
        let mut pool = worker_pool::empty();

        worker_pool::push_back(&mut pool, @0xA, 100);
        worker_pool::push_back(&mut pool, @0xB, 200);
        worker_pool::push_back(&mut pool, @0xC, 300);

        // Remove B (idx 1). Last is C (idx 2, val 300).
        worker_pool::swap_remove(&mut pool, 1, 200, 300);

        assert!(worker_pool::length(&pool) == 2, 0);

        // Current elements should be A @ idx 0, C @ idx 1
        assert!(worker_pool::nivster_by_idx(&pool, 0) == @0xA, 0);
        assert!(worker_pool::nivster_by_idx(&pool, 1) == @0xC, 0);

        assert!(worker_pool::prefix_sum(&pool, 0) == 100, 0); // A
        assert!(worker_pool::prefix_sum(&pool, 1) == 400, 0); // A + C
    }

    #[test]
    fun test_fenwick_tree_search_large_boundaries() {
        let mut pool = worker_pool::empty();

        // Push 100 elements, each with stake 10
        let mut i = 0;
        while (i < 100) {
            let addr = sui::address::from_u256(1000 + (i as u256));
            worker_pool::push_back(&mut pool, addr, 10);
            i = i + 1;
        };

        assert!(worker_pool::prefix_sum(&pool, 99) == 1000, 0);

        // Test boundary 0: sum = 10 [0, 10] maps to idx 0
        assert!(worker_pool::search(&pool, 0) == sui::address::from_u256(1000), 1);
        assert!(worker_pool::search(&pool, 10) == sui::address::from_u256(1000), 2);

        // Test boundary 10: sum = 20 [11, 20] maps to idx 1
        assert!(worker_pool::search(&pool, 11) == sui::address::from_u256(1001), 3);
        assert!(worker_pool::search(&pool, 20) == sui::address::from_u256(1001), 4);

        // Test boundary 50 (idx 5): sum = 60 [51, 60] maps to idx 5
        assert!(worker_pool::search(&pool, 51) == sui::address::from_u256(1005), 5);
        assert!(worker_pool::search(&pool, 60) == sui::address::from_u256(1005), 6);

        // Test boundary 630 (idx 63): sum = 640 [631, 640] maps to idx 63
        assert!(worker_pool::search(&pool, 631) == sui::address::from_u256(1063), 7);
        assert!(worker_pool::search(&pool, 640) == sui::address::from_u256(1063), 8);

        // Test boundary 640 (idx 64): sum = 650 [641, 650] maps to idx 64 (powers of 2 test)
        assert!(worker_pool::search(&pool, 641) == sui::address::from_u256(1064), 9);
        assert!(worker_pool::search(&pool, 650) == sui::address::from_u256(1064), 10);

        // Test boundary 990 (idx 99): sum = 1000 [991,1000] maps to idx 99
        assert!(worker_pool::search(&pool, 991) == sui::address::from_u256(1099), 11);
        assert!(worker_pool::search(&pool, 999) == sui::address::from_u256(1099), 12);
    }
}
