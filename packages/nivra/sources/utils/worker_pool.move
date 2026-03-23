// © 2026 Nivra Labs Ltd.

module nivra::worker_pool;

// === Imports ===
use std::u64::bitwise_not;

// === Constants ===
const MAX_LENGTH: u64 = 5_000;

// === Errors ===
const EWorkerPoolFull: u64 = 1;
const EIndexOutOfBounds: u64 = 2;

// === Structs ===
public struct WorkerPool has copy, drop, store {
    length: u64,
    bit: vector<Entry>,
}

public struct Entry has copy, drop, store {
    key: address,
    value: u64,
}

// === Public Functions ===
public fun empty(): WorkerPool {
    WorkerPool { 
        length: 0,
        bit: vector::tabulate!(MAX_LENGTH, |_| Entry { 
            key: @0x0, 
            value: 0, 
        }),
    }
}

public fun length(worker_pool: &WorkerPool): u64 {
    worker_pool.length
}

public fun push_back(
    worker_pool: &mut WorkerPool,
    nivster: address,
    stake: u64,
): u64 {
    let idx = worker_pool.length;
    assert!(idx < MAX_LENGTH, EWorkerPoolFull);

    worker_pool.bit[idx].key = nivster;
    worker_pool.add_bit_idx(idx, stake);
    worker_pool.length = worker_pool.length + 1;

    idx
}

public fun swap_remove(
    worker_pool: &mut WorkerPool,
    idx: u64,
    idx_val: u64,
    last_idx_val: u64,
) {
    assert!(idx < worker_pool.length, EIndexOutOfBounds);

    let last_idx = worker_pool.length - 1;
    let last_nivster = worker_pool.bit[last_idx].key;

    // Reset the last entry.
    worker_pool.bit[last_idx].key = @0x0;
    worker_pool.sub_bit_idx(last_idx, last_idx_val);

    // Swap the last entry with the target entry.
    if (idx != last_idx) {
        worker_pool.bit[idx].key = last_nivster;

        if (idx_val > last_idx_val) {
            let delta = idx_val - last_idx_val;
            worker_pool.sub_bit_idx(idx, delta);
        };

        if (idx_val < last_idx_val) {
            let delta = last_idx_val - idx_val;
            worker_pool.add_bit_idx(idx, delta);
        };
    };

    worker_pool.length = worker_pool.length - 1;
}

public fun prefix_sum(worker_pool: &WorkerPool, idx: u64): u64 {
    assert!(idx < worker_pool.length, EIndexOutOfBounds);

    let mut i = idx + 1;
    let mut sum = 0;

    while (i > 0) {
        sum = sum + worker_pool.bit[i - 1].value;
        i = i - (i & (bitwise_not(i) + 1));
    };

    sum
}

/// Returns the index of the first element in the pool where cumulative sum of stakes is equal 
/// or greater than the threshold. Threshold must be in range [0, total_cumulative_sum] or 
/// the result is incorrect. 
/// 
/// Total cumulative sum can be calculated with `prefix_sum()` function
/// using index `worker_pool.length() - 1`, but it is not checked in the runtime to save computing resources.
public(package) fun search(worker_pool: &WorkerPool, threshold: u64): address {
    let mut sum = 0;
    let mut pos = 0;
    let mut i = 14; // LOG2(10_000)

    loop {
        let step = pos + (1 << i);

        if (
            step < MAX_LENGTH && 
            sum + worker_pool.bit[step - 1].value < threshold
        ) {
            sum = sum + worker_pool.bit[step - 1].value;
            pos = step;
        };

        if (i == 0) {
            break
        };

        i = i - 1;
    };

    worker_pool.bit[pos].key
}

public fun nivster_by_idx(worker_pool: &WorkerPool, idx: u64): address {
    assert!(idx < worker_pool.length, EIndexOutOfBounds);
    worker_pool.bit[idx].key
}

public fun add_stake(worker_pool: &mut WorkerPool, idx: u64, val: u64) {
    assert!(idx < worker_pool.length, EIndexOutOfBounds);
    worker_pool.add_bit_idx(idx, val);
}

public(package) fun sub_stake(worker_pool: &mut WorkerPool, idx: u64, val: u64) {
    assert!(idx < worker_pool.length, EIndexOutOfBounds);
    worker_pool.sub_bit_idx(idx, val);
}

// === Private Functions ===
fun add_bit_idx(worker_pool: &mut WorkerPool, idx: u64, val: u64) {
    let mut i = idx + 1;

    while (i <= MAX_LENGTH) {
        worker_pool.bit[i - 1].value = worker_pool.bit[i - 1].value + val;

        i = i + (i & (bitwise_not(i) + 1));
    }
}

fun sub_bit_idx(worker_pool: &mut WorkerPool, idx: u64, val: u64) {
    let mut i = idx + 1;

    while (i <= MAX_LENGTH) {
        worker_pool.bit[i - 1].value = worker_pool.bit[i - 1].value - val;

        i = i + (i & (bitwise_not(i) + 1));
    }
}