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
    addresses: vector<address>,
    stakes: vector<u64>,
    bit: vector<u64>,
}

// === View Functions ===
public fun length(self: &WorkerPool): u64 {
    self.length
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

    let slices: u8 = 10;
    let mut i: u8 = 0;

    while (i < slices) {
        dynamic_field::add(
            &mut worker_pool.id, 
            i, 
            Slice { 
                addresses: vector::tabulate!(SLICE_SIZE, |_| @0x0),
                stakes: vector::tabulate!(SLICE_SIZE, |_| 0),
                bit: vector::tabulate!(SLICE_SIZE, |_| 0),
            },
        );

        i = i + 1;
    };

    worker_pool
}

public(package) fun destroy_empty(self: WorkerPool) {
    assert!(self.length == 0, ENotEmpty);

    let WorkerPool {
        id,
        length: _,
    } = self;

    id.delete();
}

public(package) fun get_idx(self: &WorkerPool, idx: u64): (address, u64) {
    assert!(idx < self.length, EIndexOutOfBounds);
    let (slice, sub_idx) = self.idx_location(idx);
    let addr = slice.addresses[sub_idx];
    let stake = slice.stakes[sub_idx];

    (addr, stake)
}

public(package) fun push_back(
    self: &mut WorkerPool, 
    addr: address, 
    stake: u64
): u64 {
    let idx = self.length;

    assert!(idx < MAX_LENGTH, EWorkerPoolFull);
    self.change_stake_idx(idx, addr, stake);
    self.add_bit_idx(idx, stake);
    self.length = self.length + 1;

    idx
}

public(package) fun swap_remove(self: &mut WorkerPool, idx: u64) {
    assert!(idx < self.length, EIndexOutOfBounds);

    let last_idx = self.length - 1;
    let (last_addr, last_stake) = self.change_stake_idx(last_idx, @0x0, 0);
    self.sub_bit_idx(last_idx, last_stake);

    if (idx != last_idx) {
        let (_, stake_idx) = self.change_stake_idx(idx, last_addr, last_stake);

        if (stake_idx > last_stake) {
            let delta = stake_idx - last_stake;
            self.sub_bit_idx(idx, delta);
        };

        if (stake_idx < last_stake) {
            let delta = last_stake - stake_idx;
            self.add_bit_idx(idx, delta);
        };
    };

    self.length = self.length - 1;
}

public(package) fun prefix_sum(self: &WorkerPool, idx: u64): u64 {
    assert!(idx < self.length, EIndexOutOfBounds);

    let mut i = idx + 1;
    let mut sum = 0;

    while (i > 0) {
        sum = sum + self.bit_idx(i - 1);
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
public(package) fun search(self: &WorkerPool, threshold: u64): u64 {
    let mut sum = 0;
    let mut pos = 0;
    let mut i = 14; // LOG2(10_000)

    loop {
        let step = pos + (1 << i);

        if (step < SIZE && sum + self.bit_idx(step - 1) < threshold) {
            sum = sum + self.bit_idx(step - 1);
            pos = step;
        };

        if (i == 0) {
            break
        };

        i = i - 1;
    };

    pos
}

public(package) fun add_stake(self: &mut WorkerPool, idx: u64, val: u64) {
    assert!(idx < self.length, EIndexOutOfBounds);
    let (slice, sub_idx) = self.idx_location_mut(idx);
    let stake = vector::borrow_mut(&mut slice.stakes, sub_idx);
    *stake = *stake + val;

    self.add_bit_idx(idx, val);
}

public(package) fun sub_stake(self: &mut WorkerPool, idx: u64, val: u64) {
    assert!(idx < self.length, EIndexOutOfBounds);
    let (slice, sub_idx) = self.idx_location_mut(idx);
    let stake = vector::borrow_mut(&mut slice.stakes, sub_idx);
    *stake = *stake - val;

    self.sub_bit_idx(idx, val);
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
    slice.bit[sub_idx]
}

fun change_stake_idx(self: &mut WorkerPool, idx: u64, addr: address, stake: u64): (address, u64) {
    let (slice, sub_idx) = self.idx_location_mut(idx);
    let address_slot = vector::borrow_mut(&mut slice.addresses, sub_idx);
    let stake_slot = vector::borrow_mut(&mut slice.stakes, sub_idx);

    let previous_addr = *address_slot;
    let previous_stake = *stake_slot;

    *address_slot = addr;
    *stake_slot = stake;

    (previous_addr, previous_stake)
}

fun add_bit_individual_idx(self: &mut WorkerPool, idx: u64, val: u64) {
    let (slice, sub_idx) = self.idx_location_mut(idx);
    let bit_val = vector::borrow_mut(&mut slice.bit, sub_idx);
    *bit_val = *bit_val + val;
}

fun sub_bit_individual_idx(self: &mut WorkerPool, idx: u64, val: u64) {
    let (slice, sub_idx) = self.idx_location_mut(idx);
    let bit_val = vector::borrow_mut(&mut slice.bit, sub_idx);
    *bit_val = *bit_val - val;
}

fun add_bit_idx(self: &mut WorkerPool, idx: u64, val: u64) {
    let mut i = idx + 1;

    while (i <= SIZE) {
        add_bit_individual_idx(self, i - 1, val);

        i = i + (i & (bitwise_not(i) + 1));
    }
}

fun sub_bit_idx(self: &mut WorkerPool, idx: u64, val: u64) {
    let mut i = idx + 1;

    while (i <= SIZE) {
        sub_bit_individual_idx(self, i - 1, val);

        i = i + (i & (bitwise_not(i) + 1));
    }
}

// === Test Functions ===
#[test_only]
public(package) fun destroy(self: WorkerPool) {
    let WorkerPool {
        id,
        length: _,
    } = self;

    id.delete();
}