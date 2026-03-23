// © 2026 Nivra Labs Ltd.

module nivra::worker_pool;

// === Imports ===
use sui::dynamic_field;
use std::u64::bitwise_not;

// === Constants ===
const MAX_LENGTH: u64 = 10_000;
const SIZE: u64 = 10_000;
const SLICE_SIZE: u64 = 1000;

// === Errors ===
const EWorkerPoolFull: u64 = 1;
const EIndexOutOfBounds: u64 = 2;
const ENotEmpty: u64 = 3;

// === Structs ===
public struct WorkerPool has key, store {
    id: UID,
    length: u64,
}

public struct Slice has drop, store {
    bit: vector<Entry>,
}

public struct Entry has copy, drop, store {
    key: address,
    value: u64,
}

// === View Functions ===
public fun length(worker_pool: &WorkerPool): u64 {
    worker_pool.length
}

public fun max_length(): u64 {
    MAX_LENGTH
}

// === Package Functions ===
public(package) fun empty(ctx: &mut TxContext): WorkerPool {
    let mut worker_pool = WorkerPool { 
        id: object::new(ctx),
        length: 0,
    };

    let slices = 10u64;
    let mut i = 0u64;

    while (i < slices) {
        dynamic_field::add(
            &mut worker_pool.id, 
            i, 
            Slice { 
                bit: vector::tabulate!(SLICE_SIZE, |_| Entry { 
                    key: @0x0, 
                    value: 0,
                }),
            },
        );

        i = i + 1;
    };

    worker_pool
}

public(package) fun destroy_empty(worker_pool: WorkerPool) {
    assert!(worker_pool.length == 0, ENotEmpty);

    let WorkerPool {
        id,
        length: _,
    } = worker_pool;

    id.delete();
}

public(package) fun push_back(
    worker_pool: &mut WorkerPool, 
    key: address,
    value: u64,
): u64 {
    let idx = worker_pool.length;

    assert!(idx < MAX_LENGTH, EWorkerPoolFull);
    worker_pool.change_key(idx, key);
    worker_pool.add_bit_idx(idx, value);
    worker_pool.length = worker_pool.length + 1;

    idx
}

public(package) fun swap_remove(
    worker_pool: &mut WorkerPool, 
    idx: u64,
    idx_stake: u64,
    last_idx_stake: u64,
) {
    assert!(idx < worker_pool.length, EIndexOutOfBounds);

    let last_idx = worker_pool.length - 1;
    let last_key = worker_pool.change_key(last_idx, @0x0);
    worker_pool.sub_bit_idx(last_idx, last_idx_stake);

    if (idx != last_idx) {
        worker_pool.change_key(idx, last_key);

        if (idx_stake > last_idx_stake) {
            let delta = idx_stake - last_idx_stake;
            worker_pool.sub_bit_idx(idx, delta);
        };

        if (idx_stake < last_idx_stake) {
            let delta = last_idx_stake - idx_stake;
            worker_pool.add_bit_idx(idx, delta);
        };
    };

    worker_pool.length = worker_pool.length - 1;
}

public(package) fun prefix_sum(worker_pool: &WorkerPool, idx: u64): u64 {
    assert!(idx < worker_pool.length, EIndexOutOfBounds);

    let mut i = idx + 1;
    let mut sum = 0;

    while (i > 0) {
        sum = sum + worker_pool.bit_idx(i - 1);
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

        if (step < SIZE && sum + worker_pool.bit_idx(step - 1) < threshold) {
            sum = sum + worker_pool.bit_idx(step - 1);
            pos = step;
        };

        if (i == 0) {
            break
        };

        i = i - 1;
    };

    worker_pool.key(pos)
}

public(package) fun add_stake(worker_pool: &mut WorkerPool, idx: u64, val: u64) {
    assert!(idx < worker_pool.length, EIndexOutOfBounds);
    worker_pool.add_bit_idx(idx, val);
}

public(package) fun sub_stake(worker_pool: &mut WorkerPool, idx: u64, val: u64) {
    assert!(idx < worker_pool.length, EIndexOutOfBounds);
    worker_pool.sub_bit_idx(idx, val);
}

public(package) fun key(worker_pool: &WorkerPool, idx: u64): address {
    let (slice, sub_idx) = worker_pool.idx_location(idx);
    slice.bit[sub_idx].key
}

// === Private Functions ===
fun idx_location(self: &WorkerPool, idx: u64): (&Slice, u64) {
    let slice_idx = idx / SLICE_SIZE;
    let sub_idx = idx - slice_idx * SLICE_SIZE;
    let slice: &Slice = dynamic_field::borrow(&self.id, slice_idx);

    (slice, sub_idx)
}

fun idx_location_mut(self: &mut WorkerPool, idx: u64): (&mut Slice, u64) {
    let slice_idx = idx / SLICE_SIZE;
    let sub_idx = idx - slice_idx * SLICE_SIZE;
    let slice: &mut Slice = dynamic_field::borrow_mut(&mut self.id, slice_idx);

    (slice, sub_idx)
}

fun bit_idx(self: &WorkerPool, idx: u64): u64 {
    let (slice, sub_idx) = self.idx_location(idx);
    slice.bit[sub_idx].value
}

fun add_bit_individual_idx(self: &mut WorkerPool, idx: u64, val: u64) {
    let (slice, sub_idx) = self.idx_location_mut(idx);
    slice.bit[sub_idx].value = slice.bit[sub_idx].value + val;
}

fun sub_bit_individual_idx(self: &mut WorkerPool, idx: u64, val: u64) {
    let (slice, sub_idx) = self.idx_location_mut(idx);
    slice.bit[sub_idx].value = slice.bit[sub_idx].value - val;
}

fun add_bit_idx(worker_pool: &mut WorkerPool, idx: u64, val: u64) {
    let mut i = idx + 1;

    while (i <= SIZE) {
        worker_pool.add_bit_individual_idx( i - 1, val);

        i = i + (i & (bitwise_not(i) + 1));
    }
}

fun sub_bit_idx(worker_pool: &mut WorkerPool, idx: u64, val: u64) {
    let mut i = idx + 1;

    while (i <= SIZE) {
        worker_pool.sub_bit_individual_idx( i - 1, val);

        i = i + (i & (bitwise_not(i) + 1));
    }
}

fun change_key(worker_pool: &mut WorkerPool, idx: u64, key: address): address {
    let (slice, sub_idx) = worker_pool.idx_location_mut(idx);
    let prev_key = slice.bit[sub_idx].key;
    slice.bit[sub_idx].key = key;

    prev_key
}