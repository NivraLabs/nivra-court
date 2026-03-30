// © 2026 Nivra Labs Ltd.

module nivra::court;

// === Imports ===
use std::string::String;
use sui::table::{Self, Table};
use sui::linked_table::{Self, LinkedTable};
use nivra::worker_pool::{Self, WorkerPool};
use sui::balance::{Self, Balance};
use sui::vec_set::VecSet;
use nvr::nvr::NVR;
use sui::sui::SUI;
use sui::coin::Coin;
use sui::event;
use nivra::constants::max_category_length;
use nivra::constants::max_name_length;
use nivra::constants::max_description_length;
use nivra::registry::Registry;
use sui::clock::Clock;
use nivra::constants::max_appeals_limit;
use nivra::constants::max_dispute_description_length;
use nivra::constants::min_option_count;
use nivra::constants::max_option_count;
use nivra::constants::max_option_len;
use sui::vec_map::{Self, VecMap};
use nivra::constants::min_party_size;
use nivra::constants::max_party_size;
use nivra::dispute::create_dispute_schedule;
use nivra::dispute::create_dispute_economics;
use nivra::dispute::create_dispute_operation;
use nivra::dispute::create_dispute;
use nivra::dispute::Dispute;
use sui::random::Random;
use sui::random::new_generator;
use nivra::constants::tie_nivster_count;
use nivra::constants::status_active;
use nivra::constants::status_halted;
use nivra::vec_map_unsafe::{Self, VecMapUnsafe};
use nivra::dispute::VoterDetails;
use nivra::constants::max_init_nivster_count;
use nivra::constants::max_voter_count;
use nivra::constants::current_version;

// === Constants ===
// Sanction models
const FIXED_PERCENTAGE_MODEL: u64 = 0;
const MINORITY_SCALED_MODEL: u64 = 1;
const QUADRATIC_MODEL: u64 = 2;

// === Errors ===
const ENotOperational: u64 = 2;
const EZeroDeposit: u64 = 3;
const ETooLowReputation: u64 = 5;
const EDepositUnderMinStake: u64 = 6;
const ENotEnoughNVR: u64 = 7;
const ENotEnoughSUI: u64 = 8;
const ENoWithdrawAmount: u64 = 9;
const ECategoryTooLong: u64 = 10;
const ENameTooLong: u64 = 11;
const EDescTooLong: u64 = 12;
const EZeroMinStake: u64 = 13;
const EInvalidReputationRequirement: u64 = 14;
const EInvalidSanctionModel: u64 = 15;
const EInvalidCoefficient: u64 = 16;
const EInvalidTreasuryShare: u64 = 17;
const EInvalidEmptyVotePenalty: u64 = 18;
const EZeroInitNivsters: u64 = 19;
const EZeroKeyServers: u64 = 20;
const EInvalidKeyConfig: u64 = 21;
const EInvalidThreshold: u64 = 22;
const EAlreadyInWorkerPool: u64 = 23;
const ENotInWorkerPool: u64 = 24;
const EInvalidFee: u64 = 25;
const EInvalidAppealCount: u64 = 27;
const EDescriptionTooLong: u64 = 28;
const ETooLittleOptions: u64 = 29;
const ETooManyOptions: u64 = 30;
const EOptionEmpty: u64 = 31;
const EOptionTooLong: u64 = 32;
const EInvalidPartySize: u64 = 33;
const EInitiatorNotParty: u64 = 34;
const EDisputeAlreadyExists: u64 = 35;
const ENotResponsePeriod: u64 = 36;
const ENotDisputeParty: u64 = 37;
const EWrongParty: u64 = 38;
const EInvalidCourt: u64 = 39;
const ENotDrawPeriod: u64 = 40;
const ENotEnoughNivsters: u64 = 41;
const ENotAppealPeriodTallied: u64 = 42;
const ENoAppealsLeft: u64 = 43;
const EDisputeNotTie: u64 = 44;
const EDisputeNotCancellable: u64 = 45;
const EDisputeNotOneSided: u64 = 46;
const EInvalidStatus: u64 = 49;
const EDisputeNotCompleted: u64 = 50;
const ETooHighInitNivsterCount: u64 = 51;
const ETooManyVoters: u64 = 52;
const EWrongVersion: u64 = 53;

// === Structs ===
public struct Court has key, store {
    id: UID,
    allowed_versions: VecSet<u64>,
    cases: Table<vector<u8>, ID>,
    metadata: Metadata,
    timetable: Timetable,
    economics: Economics,
    operation: Operation,
    stakes: LinkedTable<address, Stake>,
    worker_pool: WorkerPool,
    stake_pool: Balance<NVR>,
    reward_pool: Balance<SUI>,
}

public struct Metadata has copy, drop, store {
    name: String,
    category: String,
    description: String,
    ai_court: bool,
}

public struct Timetable has copy, drop, store {
    response_period_ms: u64,
    draw_period_ms: u64,
    evidence_period_ms: u64,
    voting_period_ms: u64,
    appeal_period_ms: u64,
}

public struct Economics has copy, drop, store {
    min_stake: u64,
    reputation_requirement: u64,
    init_nivster_count: u64,
    sanction_model: u64,
    coefficient: u64,
    dispute_fee: u64,
    treasury_share: u64,
    treasury_share_nvr: u64,
    empty_vote_penalty: u64,
}

public struct Operation has copy, drop, store {
    status: u8,
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
    threshold: u8,
}

public struct Stake has drop, store {
    amount: u64,
    locked_amount: u64,
    reward_amount: u64,
    worker_pool_pos: Option<u64>,
}

// === Events ===
public struct BalanceDepositEvent has copy, drop {
    court: ID,
    nivster: address,
    amount_nvr: u64,
}

public struct BalanceWithdrawalEvent has copy, drop {
    court: ID,
    nivster: address,
    amount_nvr: u64,
    amount_sui: u64,
}

public struct BalanceLockedEvent has copy, drop {
    court: ID,
    nivster: address,
    locked_nvr: u64,
    dispute_id: ID,
}

public struct BalanceUnlockEvent has copy, drop {
    court: ID,
    nivster: address,
    unlocked_nvr: u64,
    dispute_id: ID,
}

public struct BalancePenaltyEvent has copy, drop {
    court: ID,
    nivster: address,
    amount_nvr: u64,
    unlocked_nvr: u64,
    dispute_id: ID,
}

public struct BalanceRewardEvent has copy, drop {
    court: ID,
    nivster: address,
    amount_nvr: u64,
    amount_sui: u64,
    unlocked_nvr: u64,
    dispute_id: ID,
}

public struct WorkerPoolEvent has copy, drop {
    court: ID,
    nivster: address,
    entry: bool,
}

public struct CourtCreatedEvent has copy, drop {
    court: ID,
    metadata: Metadata,
    timetable: Timetable,
    economics: Economics,
    operation: Operation,
}

public struct CourtMetadataChanged has copy, drop {
    court: ID,
    metadata: Metadata,
}

public struct CourtTimetableChanged has copy, drop {
    court: ID,
    timetable: Timetable,
}

public struct CourtEconomicsChanged has copy, drop {
    court: ID,
    economics: Economics,
}

public struct CourtOperationChanged has copy, drop {
    court: ID,
    operation: Operation,
}

// === Method Aliases ===
use fun nivra::vec_map::unique_values as VecMap.unique_values;
use fun nivra::vec_map::do as VecMap.do;

// === Public Functions ===
public fun stake(
    court: &mut Court,
    registry: &Registry,
    assets: Coin<NVR>, 
    ctx: &mut TxContext,
) {
    court.validate_version();
    assert!(court.operation.status == status_active(), ENotOperational);

    let nivster_reputation = registry.nivster_reputation(ctx.sender());
    assert!(
        nivster_reputation >= court.economics.reputation_requirement, 
        ETooLowReputation
    );

    let deposit_amount = assets.value();
    assert!(deposit_amount > 0, EZeroDeposit);

    if (!court.stakes.contains(ctx.sender())) {
        court.stakes.push_back(ctx.sender(), Stake {
            amount: 0,
            locked_amount: 0,
            reward_amount: 0,
            worker_pool_pos: option::none(),
        });
    };

    let stake = court.stakes.borrow_mut(ctx.sender());

    assert!(
        stake.amount + deposit_amount >= court.economics.min_stake, 
        EDepositUnderMinStake
    );

    stake.amount = stake.amount + deposit_amount;

    // Automatically join worker pool or increase the existing stake.
    if (stake.worker_pool_pos.is_some()) {
        court.worker_pool.add_stake(
            *stake.worker_pool_pos.borrow(), 
            deposit_amount
        );
    } else if (!court.worker_pool.is_full()) {
        let pos = court.worker_pool.push_back(ctx.sender(), stake.amount);
        stake.worker_pool_pos = option::some(pos);
    };

    court.stake_pool.join(assets.into_balance());

    event::emit(BalanceDepositEvent {
        court: object::id(court),
        nivster: ctx.sender(),
        amount_nvr: deposit_amount,
    });
}

/// Withdraws available NVR stake and/or accumulated SUI rewards from the court.
public fun withdraw(
    court: &mut Court,
    amount_nvr: u64,
    amount_sui: u64,
    ctx: &mut TxContext,
): (Coin<NVR>, Coin<SUI>) {
    court.validate_version();
    let stake = court.stakes.borrow_mut(ctx.sender());
    let stake_before_withdraw = stake.amount;

    assert!(stake.amount >= amount_nvr, ENotEnoughNVR);
    assert!(stake.reward_amount >= amount_sui, ENotEnoughSUI);
    assert!(amount_nvr > 0 || amount_sui > 0, ENoWithdrawAmount);

    stake.amount = stake.amount - amount_nvr;
    stake.reward_amount = stake.reward_amount - amount_sui;

    // Automatically remove or deduct from the worker pool.
    if (stake.worker_pool_pos.is_some() && amount_nvr > 0) {
        let pos = *stake.worker_pool_pos.borrow();

        if (stake.amount >= court.economics.min_stake) {
            court.worker_pool.sub_stake(pos, amount_nvr);
        } else {
            court.remove_from_worker_pool(ctx.sender(), stake_before_withdraw);
        };
    };

    let nvr = court.stake_pool.split(amount_nvr).into_coin(ctx);
    let sui = court.reward_pool.split(amount_sui).into_coin(ctx);

    event::emit(BalanceWithdrawalEvent {
        court: object::id(court),
        nivster: ctx.sender(),
        amount_nvr,
        amount_sui,
    });
    
    (nvr, sui)
}

/// Enrolls the caller into the worker pool.
public fun join_worker_pool(
    court: &mut Court, 
    ctx: &mut TxContext
) {
    court.validate_version();
    assert!(court.operation.status == status_active(), ENotOperational);

    let stake = court.stakes.borrow_mut(ctx.sender());
    assert!(stake.amount >= court.economics.min_stake, ENotEnoughNVR);
    assert!(!stake.worker_pool_pos.is_some(), EAlreadyInWorkerPool);

    let pos = court.worker_pool.push_back(ctx.sender(), stake.amount);
    stake.worker_pool_pos = option::some(pos);

    event::emit(WorkerPoolEvent {
        court: object::id(court),
        nivster: ctx.sender(),
        entry: true,
    });
}

/// Removes the caller from the worker pool.
public fun leave_worker_pool(
    court: &mut Court,
    ctx: &mut TxContext
) {
    court.validate_version();

    let stake = court.stakes.borrow_mut(ctx.sender());
    assert!(stake.worker_pool_pos.is_some(), ENotInWorkerPool);
    let stake_in_pool = stake.amount;

    court.remove_from_worker_pool(ctx.sender(), stake_in_pool);

    event::emit(WorkerPoolEvent {
        court: object::id(court),
        nivster: ctx.sender(),
        entry: false,
    });
}

public fun open_dispute(
    court: &mut Court,
    fee: Coin<SUI>,
    contract: ID,
    description: String,
    options: vector<String>,
    parties: vector<address>,
    max_appeals: u8,
    clock: &Clock, 
    ctx: &mut TxContext
) {
    court.validate_version();
    assert!(court.operation.status == status_active(), ENotOperational);
    assert!(court.economics.dispute_fee == fee.value(), EInvalidFee);

    // Dispute rules.
    assert!(
        description.length() <= max_dispute_description_length(), 
        EDescriptionTooLong
    );
    assert!(max_appeals <= max_appeals_limit(), EInvalidAppealCount);
    assert!(parties.contains(&ctx.sender()), EInitiatorNotParty);
    assert!(options.length() >= min_option_count(), ETooLittleOptions);
    assert!(options.length() <= max_option_count(), ETooManyOptions);

    options.do!(|option| {
        assert!(option.length() > 0, EOptionEmpty);
        assert!(option.length() <= max_option_len() as u64, EOptionTooLong);
    });

    let options_mapping = vec_map::from_keys_values(
        options, 
        parties,
    );
    let parties = options_mapping.unique_values!();

    assert!(parties.length() >= min_party_size(), EInvalidPartySize);
    assert!(parties.length() <= max_party_size(), EInvalidPartySize);

    // Check if a dispute with the same configuration already exists.
    let serialized_config = serialize_dispute_config(
        contract, 
        options_mapping,
        max_appeals,
    );

    assert!(!court.cases.contains(serialized_config), EDisputeAlreadyExists);

    // Create & register a new dispute.
    let dispute = create_dispute(
        contract,
        object::id(court), 
        max_appeals, 
        options_mapping, 
        court.timetable.to_dispute_schedule_snapshot(clock), 
        court.economics.to_dispute_economics_snapshot(), 
        court.operation.to_dispute_operation_snapshot(),
        serialized_config,
        clock,
        ctx,
    );

    court.cases.add(serialized_config, object::id(&dispute));
    court.reward_pool.join(fee.into_balance());
    dispute.share_dispute();
}

public fun accept_dispute(
    court: &mut Court,
    dispute: &mut Dispute,
    fee: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    court.validate_version();
    assert!(dispute.is_response_period(clock), ENotResponsePeriod);
    assert!(dispute.court() == object::id(court), EInvalidCourt);
    assert!(dispute.is_party(ctx.sender()), ENotDisputeParty);
    assert!(dispute.last_payer() != ctx.sender(), EWrongParty);

    let appeal_count = dispute.appeals_used();
    let dispute_fee = dispute_fee(dispute.dispute_fee(), appeal_count);

    assert!(fee.value() == dispute_fee, EInvalidFee);

    dispute.register_payment(fee.value(), ctx.sender(),clock);
    court.reward_pool.join(fee.into_balance());

    dispute.start_draw_period(clock);
}

entry fun draw_nivsters(
    court: &mut Court,
    dispute: &mut Dispute,
    clock: &Clock,
    r: &Random,
    ctx: &mut TxContext,
) {
    court.validate_version();
    assert!(dispute.court() == object::id(court), EInvalidCourt);
    assert!(dispute.is_draw_period(clock), ENotDrawPeriod);

    let appeal_count = dispute.appeals_used();

    // The nivster count grows by 2^(i-1) * (N + 1) on appeal rounds, where 
    // i = appeal count and N = the initial nivster count.
    let nivster_count = if (appeal_count > 0) {
        std::u64::pow(2, appeal_count - 1) * (dispute.init_nivster_count() + 1)
    } else {
        dispute.init_nivster_count()
    };

    random_nivster_selection(
        court, 
        dispute, 
        nivster_count,
        r, 
        ctx
    );

    dispute.start_new_round(clock);
}

public fun open_appeal(
    court: &mut Court,
    dispute: &mut Dispute,
    fee: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    court.validate_version();
    assert!(dispute.court() == object::id(court), EInvalidCourt);
    assert!(dispute.is_appeal_period_tallied(clock), ENotAppealPeriodTallied);
    assert!(dispute.is_party(ctx.sender()), ENotDisputeParty);
    assert!(dispute.has_appeals_left(), ENoAppealsLeft);

    let appeal_count = dispute.appeals_used() + 1;

    let dispute_fee = dispute_fee(dispute.dispute_fee(), appeal_count);
    assert!(fee.value() == dispute_fee, EInvalidFee);

    dispute.register_payment(fee.value(), ctx.sender(), clock);
    court.reward_pool.join(fee.into_balance());

    dispute.use_appeal();
    dispute.start_response_period(clock);
}

entry fun handle_dispute_tie(
    court: &mut Court,
    dispute: &mut Dispute,
    clock: &Clock,
    r: &Random,
    ctx: &mut TxContext,
) {
    court.validate_version();
    assert!(dispute.court() == object::id(court), EInvalidCourt);
    assert!(dispute.is_appeal_period_tie(clock), EDisputeNotTie);

    random_nivster_selection(
        court, 
        dispute, 
        tie_nivster_count(),
        r, 
        ctx
    );

    dispute.start_new_round_tie(clock);
}

public fun cancel_dispute(
    court: &mut Court,
    dispute: &mut Dispute,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    court.validate_version();
    assert!(dispute.court() == object::id(court), EInvalidCourt);
    assert!(dispute.is_incomplete(clock), EDisputeNotCancellable);

    let dispute_id = object::id(dispute);

    // Remove the case from the case map, so a new case can be opened 
    // for the contract.
    court.cases.remove(dispute.config_hash());

    // Refund the parties.
    dispute.payments().do!(|party, payment_details| {
        let total_deposit_amount = payment_details.fold!(0, |sum, deposit| {
            sum + deposit.amount()
        });

        if (total_deposit_amount > 0) {
            transfer::public_transfer(
                court.reward_pool.split(total_deposit_amount).into_coin(ctx),
                *party
            );
            
            dispute.register_refund(total_deposit_amount, *party, clock);
        };
    });

    // Refund the nivsters.
    dispute.voters().for_each_ref!(|voter, voter_details| {
        court.unlock_stake(
            *voter, 
            voter_details.stake(), 
            dispute_id,
        );
    });

    dispute.cancel_dispute(clock);
}

public fun resolve_one_sided_dispute(
    court: &mut Court,
    dispute: &mut Dispute,
    registry: &mut Registry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    court.validate_version();
    assert!(dispute.court() == object::id(court), EInvalidCourt);
    assert!(dispute.party_failed_payment(clock), EDisputeNotOneSided);

    let winner_party = dispute.last_payer();

    // Refund the winning party and calculate sui rewards size.
    let mut winner_party_deposits = 0;
    let mut lost_deposits = 0;

    dispute.payments().do!(|party, payment_details| {
        let total_deposit_amount = payment_details.fold!(0, |sum, deposit| {
            sum + deposit.amount()
        });

        if (*party == winner_party) {
            winner_party_deposits = total_deposit_amount;
        } else {
            lost_deposits = lost_deposits + total_deposit_amount;
        };
    });

    transfer::public_transfer(
        court.reward_pool.split(winner_party_deposits).into_coin(ctx),
        winner_party
    );
            
    dispute.register_refund(winner_party_deposits, winner_party, clock);

    // Calculate nvr rewards size & register penalties.
    let winners = dispute.votes_for_party(winner_party);
    let total_votes = dispute.total_votes_casted();
    let mut penalties = 0;
    let mut winner_stakes = 0;
    let mut winner_nivsters: VecMapUnsafe<address, VoterDetails> = 
        vec_map_unsafe::empty();

    dispute.voters().for_each_ref!(|voter, voter_details| {
        let party_vote = voter_details.decrypted_vote_party(dispute);

        if (party_vote.is_none()) {
            let empty_vote_penalty = voter_details.stake() * 
                dispute.empty_vote_penalty() / 100;

            penalties = penalties + empty_vote_penalty;

            court.unlock_stake_with_penalty(
                registry, 
                *voter, 
                voter_details.stake(), 
                empty_vote_penalty, 
                object::id(dispute),
            );
        } else if (*party_vote.borrow() != winner_party) {
            let incoherent_vote_penalty = penalty(
                dispute.sanction_model(), 
                dispute.coefficient(), 
                voter_details.stake(), 
                total_votes, 
                winners
            );

            penalties = penalties + incoherent_vote_penalty;

            court.unlock_stake_with_penalty(
                registry, 
                *voter, 
                voter_details.stake(), 
                incoherent_vote_penalty, 
                object::id(dispute),
            );
        } else {
            winner_stakes = winner_stakes + voter_details.stake();
            winner_nivsters.insert_unsafe(*voter, *voter_details);
        };
    });

    // Distribute rewards.
    let treasury_nvr = 
        (penalties as u128) * (dispute.treasury_share_nvr() as u128) / 100;

    let treasury_sui = 
        (lost_deposits as u128) * (dispute.treasury_share() as u128) / 100;

    let nivster_share_nvr = (penalties as u128) - treasury_nvr;
    let nivster_share_sui = (lost_deposits as u128) - treasury_sui;
    
    let mut remaining_nvr = penalties;
    let mut remaining_sui = lost_deposits;

    winner_nivsters.for_each_ref!(|voter, voter_details| {
        // winner_stakes > 0, if winners exist.
        let nvr_reward = if (winner_stakes > 0) {
            nivster_share_nvr * (voter_details.stake() as u128) 
                / (winner_stakes as u128)
        } else { 0 };
            
        let sui_reward = if (winner_stakes > 0) {
            nivster_share_sui * (voter_details.stake() as u128) 
                / (winner_stakes as u128)
        } else { 0 };

        remaining_nvr = remaining_nvr - (nvr_reward as u64);
        remaining_sui = remaining_sui - (sui_reward as u64);

        court.unlock_stake_with_rewards(
            registry, 
            *voter, 
            voter_details.stake(), 
            nvr_reward as u64, 
            sui_reward as u64, 
            object::id(dispute),
        );
    });

    // Collect treasury share.
    if (remaining_nvr > 0) {
        transfer::public_transfer(
        court.stake_pool.split(remaining_nvr).into_coin(ctx),
        registry.treasury_address()
        );
    };

    if (remaining_sui > 0) {
        transfer::public_transfer(
            court.reward_pool.split(remaining_sui).into_coin(ctx),
            registry.treasury_address()
        );
    };
    
    dispute.resolve_dispute_one_sided(ctx);
}

public fun complete_dispute(
    court: &mut Court,
    dispute: &mut Dispute,
    registry: &mut Registry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    court.validate_version();
    assert!(dispute.court() == object::id(court), EInvalidCourt);
    assert!(dispute.is_completed(clock), EDisputeNotCompleted);

    let winner_party = *dispute.winner_party().borrow();

    // Refund the winning party and calculate sui rewards size.
    let mut winner_party_deposits = 0;
    let mut lost_deposits = 0;

    dispute.payments().do!(|party, payment_details| {
        let total_deposit_amount = payment_details.fold!(0, |sum, deposit| {
            sum + deposit.amount()
        });

        if (*party == winner_party) {
            winner_party_deposits = total_deposit_amount;
        } else {
            lost_deposits = lost_deposits + total_deposit_amount;
        };
    });

    transfer::public_transfer(
        court.reward_pool.split(winner_party_deposits).into_coin(ctx),
        winner_party
    );
            
    dispute.register_refund(winner_party_deposits, winner_party, clock);

    // Calculate nvr rewards size and register penalties.
    let winner_option = dispute.winner_option_idx();
    let winners = dispute.votes_for_option(*winner_option.borrow());
    let total_votes = dispute.total_votes_casted();
    let mut penalties = 0;
    let mut winner_stakes = 0;
    let mut winner_nivsters: VecMapUnsafe<address, VoterDetails> = 
        vec_map_unsafe::empty();

    dispute.voters().for_each_ref!(|voter, voter_details| {
        let vote = voter_details.decrypted_vote();

        if (vote.is_none()) {
            let empty_vote_penalty = voter_details.stake() * 
                dispute.empty_vote_penalty() / 100;
            
            penalties = penalties + empty_vote_penalty;

            court.unlock_stake_with_penalty(
                registry, 
                *voter, 
                voter_details.stake(), 
                empty_vote_penalty, 
                object::id(dispute),
            );
        } else if (*vote.borrow() as u64 != *winner_option.borrow()) {
            let discoherent_vote_penalty = penalty(
                dispute.sanction_model(), 
                dispute.coefficient(), 
                voter_details.stake(), 
                total_votes, 
                winners
            );

            penalties = penalties + discoherent_vote_penalty;

            court.unlock_stake_with_penalty(
                registry, 
                *voter, 
                voter_details.stake(), 
                discoherent_vote_penalty, 
                object::id(dispute),
            );
        } else {
            winner_stakes = winner_stakes + voter_details.stake();
            winner_nivsters.insert_unsafe(*voter, *voter_details);
        };
    });

    // Distribute rewards.
    let treasury_nvr = 
        (penalties as u128) * (dispute.treasury_share_nvr() as u128) / 100;

    let treasury_sui = 
        (lost_deposits as u128) * (dispute.treasury_share() as u128) / 100;

    let nivster_share_nvr = (penalties as u128) - treasury_nvr;
    let nivster_share_sui = (lost_deposits as u128) - treasury_sui;
    
    let mut remaining_nvr = penalties;
    let mut remaining_sui = lost_deposits;

    winner_nivsters.for_each_ref!(|voter, voter_details| {
        let nvr_reward = if (winner_stakes > 0) {
            nivster_share_nvr * (voter_details.stake() as u128) 
                / (winner_stakes as u128)
        } else { 0 };
            
        let sui_reward = if (winner_stakes > 0) {
            nivster_share_sui * (voter_details.stake() as u128) 
                / (winner_stakes as u128)
        } else { 0 };

        remaining_nvr = remaining_nvr - (nvr_reward as u64);
        remaining_sui = remaining_sui - (sui_reward as u64);

        court.unlock_stake_with_rewards(
            registry, 
            *voter, 
            voter_details.stake(), 
            nvr_reward as u64, 
            sui_reward as u64, 
            object::id(dispute),
        );
    });

    // Collect treasury share.
    if (remaining_nvr > 0) {
        transfer::public_transfer(
        court.stake_pool.split(remaining_nvr).into_coin(ctx),
        registry.treasury_address()
        );
    };

    if (remaining_sui > 0) {
        transfer::public_transfer(
            court.reward_pool.split(remaining_sui).into_coin(ctx),
            registry.treasury_address()
        );
    };

    dispute.complete_dispute(ctx);
}

public fun validate_version(court: &Court) {
    assert!(
        court.allowed_versions.contains(&current_version()), 
        EWrongVersion
    );
}

public fun create_metadata(
    name: String,
    category: String,
    description: String,
    ai_court: bool,
): Metadata {
    assert!(name.length() <= max_name_length(), ENameTooLong);
    assert!(category.length() <= max_category_length(), ECategoryTooLong);
    assert!(description.length() <= max_description_length(), EDescTooLong);

    Metadata {
        name,
        category,
        description,
        ai_court,
    }
}

public fun create_timetable(
    response_period_ms: u64,
    draw_period_ms: u64,
    evidence_period_ms: u64,
    voting_period_ms: u64,
    appeal_period_ms: u64,
): Timetable {
    Timetable {
        response_period_ms,
        draw_period_ms,
        evidence_period_ms,
        voting_period_ms,
        appeal_period_ms,
    }
}

public fun to_dispute_schedule_snapshot(
    timetable: &Timetable,
    clock: &Clock,
): nivra::dispute::Schedule {
    create_dispute_schedule(
        clock.timestamp_ms(), 
        timetable.response_period_ms, 
        timetable.draw_period_ms, 
        timetable.evidence_period_ms, 
        timetable.voting_period_ms, 
        timetable.appeal_period_ms,
    )
}

public fun create_economics(
    min_stake: u64,
    reputation_requirement: u64,
    init_nivster_count: u64,
    sanction_model: u64,
    coefficient: u64,
    dispute_fee: u64,
    treasury_share: u64,
    treasury_share_nvr: u64,
    empty_vote_penalty: u64,
): Economics {
    assert!(min_stake > 0, EZeroMinStake);
    assert!(init_nivster_count > 0, EZeroInitNivsters);
    assert!(
        init_nivster_count <= max_init_nivster_count(), 
        ETooHighInitNivsterCount
    );
    assert!(sanction_model < 3, EInvalidSanctionModel);
    assert!(reputation_requirement <= 100, EInvalidReputationRequirement);
    assert!(coefficient <= 100, EInvalidCoefficient);
    assert!(treasury_share <= 100, EInvalidTreasuryShare);
    assert!(treasury_share_nvr <= 100, EInvalidTreasuryShare);
    assert!(empty_vote_penalty <= 100, EInvalidEmptyVotePenalty);

    Economics {
        min_stake,
        reputation_requirement,
        init_nivster_count,
        sanction_model,
        coefficient,
        dispute_fee,
        treasury_share,
        treasury_share_nvr,
        empty_vote_penalty,
    }
}

public fun to_dispute_economics_snapshot(
    economics: &Economics
): nivra::dispute::Economics {
    create_dispute_economics(
        economics.init_nivster_count, 
        economics.sanction_model, 
        economics.coefficient, 
        economics.dispute_fee, 
        economics.treasury_share, 
        economics.treasury_share_nvr, 
        economics.empty_vote_penalty
    )
}

public fun create_operation(
    status: u8,
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
    threshold: u8,
): Operation {
    assert!(status <= status_halted(), EInvalidStatus);
    assert!(key_servers.length() > 0, EZeroKeyServers);
    assert!(key_servers.length() == public_keys.length(), EInvalidKeyConfig);
    assert!(threshold as u64 <= key_servers.length(), EInvalidThreshold);

    Operation {
        status,
        key_servers,
        public_keys,
        threshold,
    }
}

public fun to_dispute_operation_snapshot(
    operation: Operation,
): nivra::dispute::Operation {
    create_dispute_operation(
        operation.key_servers, 
        operation.public_keys, 
        operation.threshold
    )
}

// === Admin Functions ===
public fun create_court(
    registry: &mut Registry,
    metadata: Metadata,
    timetable: Timetable,
    economics: Economics,
    operation: Operation,
    ctx: &mut TxContext,
) {
    registry.validate_admin_privileges(ctx);

    let court = Court {
        id: object::new(ctx),
        allowed_versions: registry.allowed_versions(),
        cases: table::new(ctx),
        metadata,
        timetable,
        economics,
        operation,
        stakes: linked_table::new(ctx),
        worker_pool: worker_pool::empty(ctx),
        stake_pool: balance::zero<NVR>(),
        reward_pool: balance::zero<SUI>(),
    };
    let court_id = object::id(&court);

    registry.register_court(court_id);
    transfer::share_object(court);

    event::emit(CourtCreatedEvent {
        court: court_id,
        metadata,
        timetable,
        economics,
        operation,
    });
}

public fun change_metadata(
    court: &mut Court,
    registry: &Registry,
    metadata: Metadata,
    ctx: &mut TxContext,
) {
    court.validate_version();
    registry.validate_admin_privileges(ctx);

    court.metadata = metadata;

    event::emit(CourtMetadataChanged { 
        court: object::id(court), 
        metadata,
    });
}

public fun change_timetable(
    court: &mut Court,
    registry: &Registry,
    timetable: Timetable,
    ctx: &mut TxContext,
) {
    court.validate_version();
    registry.validate_admin_privileges(ctx);

    court.timetable = timetable;

    event::emit(CourtTimetableChanged { 
        court: object::id(court), 
        timetable,
    });
}

public fun change_economics(
    court: &mut Court,
    registry: &Registry,
    economics: Economics,
    ctx: &mut TxContext,
) {
    court.validate_version();
    registry.validate_admin_privileges(ctx);

    court.economics = economics;

    event::emit(CourtEconomicsChanged { 
        court: object::id(court), 
        economics,
    });
}

public fun change_operation(
    court: &mut Court,
    registry: &Registry,
    operation: Operation,
    ctx: &mut TxContext,
) {
    court.validate_version();
    registry.validate_admin_privileges(ctx);

    court.operation = operation;

    event::emit(CourtOperationChanged { 
        court: object::id(court), 
        operation, 
    });
}

public fun migrate(
    court: &mut Court,
    registry: &Registry,
    ctx: &mut TxContext,
) {
    registry.validate_admin_privileges(ctx);
    court.allowed_versions = registry.allowed_versions();
}

// === Private Functions ===
fun remove_from_worker_pool(
    court: &mut Court,
    nivster: address,
    stake_in_pool: u64,
) {
    let last_pos_idx = court.worker_pool.length() - 1;
    let idx = {
        let removed_staker = court.stakes.borrow_mut(nivster);
        let idx = *removed_staker.worker_pool_pos.borrow();
        removed_staker.worker_pool_pos = option::none();

        idx
    };

    // Update the position of the last staker in the worker pool
    if (last_pos_idx != idx) {
        let last_pos_addr = court.worker_pool.key(last_pos_idx);
        let last_staker = court.stakes.borrow_mut(last_pos_addr);
        last_staker.worker_pool_pos = option::some(idx);

        court.worker_pool.swap_remove(
            idx, 
            stake_in_pool, 
            last_staker.amount,
        );
    } else {
        court.worker_pool.swap_remove(
            idx, 
            0, 
            stake_in_pool,
        );
    };
}

fun serialize_dispute_config(
    contract_id: ID,
    options: VecMap<String, address>,
    max_appeals: u8,
): vector<u8> {
    // Configuration is serialized as:
    // [contract_id][max_appeals][options_len][(len, option, address)...]
    let mut serialized: vector<u8> = vector::empty();
    serialized.append(contract_id.to_bytes());
    serialized.push_back(max_appeals);
    // NOTE: Max options length is 4.
    serialized.push_back(options.length() as u8);

    options.do!(|option, party| {
        // NOTE: Max option length is 255.
        serialized.push_back(option.length() as u8);
        serialized.append(*option.as_bytes());
        serialized.append(party.to_bytes());
    });

    // Hash the serialized config.
    sui::hash::blake2b256(&serialized)
}

fun random_nivster_selection(
    court: &mut Court,
    dispute: &mut Dispute,
    nivster_count: u64,
    r: &Random,
    ctx: &mut TxContext,
) {
    assert!(court.worker_pool.length() >= nivster_count, ENotEnoughNivsters);
    assert!(
        dispute.voters().length() + nivster_count <= max_voter_count(),
        ETooManyVoters
    );

    let mut nivsters_selected: vector<address> = vector[];
    let mut generator = new_generator(r, ctx);
    let mut sum = court.worker_pool.prefix_sum(court.worker_pool.length() - 1);

    while (nivsters_selected.length() < nivster_count) {
        let selection_threshold = generator.generate_u64_in_range(1, sum);
        // Find the first nivster n whose cumulative stake sum is >= threshold.
        let nivster = court.worker_pool.search(selection_threshold);
        let stake_in_pool = court.stakes.borrow(nivster).amount;

        // Remove the n from the worker pool to prevent duplicate selections.
        court.remove_from_worker_pool(nivster, stake_in_pool);

        // Narrow the selection range by nivster's stake amount.
        let stake = court.stakes.borrow(nivster);
        sum = sum - stake.amount;

        nivsters_selected.push_back(nivster);
    };

    nivsters_selected.do!(|nivster| {
        let court_id = object::id(court);
        let stake = court.stakes.borrow_mut(nivster);
        let locked_amount = if (stake.amount < court.economics.min_stake) {
            stake.amount
        } else {
            court.economics.min_stake
        };

        stake.amount = stake.amount - locked_amount;
        stake.locked_amount = stake.locked_amount + locked_amount;

        event::emit(BalanceLockedEvent {
            court: court_id,
            nivster,
            locked_nvr: locked_amount,
            dispute_id: object::id(dispute),
        });

        dispute.add_voter(nivster, locked_amount);

        if (stake.amount >= court.economics.min_stake) {
            let idx = court.worker_pool.push_back(nivster, stake.amount);
            stake.worker_pool_pos = option::some(idx);
        } else {
            event::emit(WorkerPoolEvent {
                court: object::id(court),
                nivster,
                entry: false,
            });
        };
    });
}

fun dispute_fee(dispute_fee: u64, appeal_count: u8): u64 {
    let fee = std::u128::divide_and_round_up(
        dispute_fee as u128 * std::u128::pow(13, appeal_count), 
        std::u128::pow(5, appeal_count)
    );

    fee as u64
}

fun penalty(
    sanction_model: u64,
    coefficient: u64,
    staked_amount: u64,
    total_votes: u64,
    winner_votes: u64,
): u64 {
    if (sanction_model == FIXED_PERCENTAGE_MODEL) {
        return staked_amount * coefficient / 100
    };

    // if total_votes == winner_votes, the penalty should never occurs for any 
    // nivster.
    let minority_votes = total_votes - winner_votes;

    if (sanction_model == MINORITY_SCALED_MODEL && minority_votes > 0) {
        return staked_amount * coefficient / (minority_votes * 100)
    };

    // if total_votes == 0, the penalty should never occur for any nivster.
    if (sanction_model == QUADRATIC_MODEL && total_votes > 0) {
        return (
            (staked_amount as u128) * (coefficient as u128) 
            * std::u128::pow(winner_votes as u128, 2) 
            / (100 * std::u128::pow(total_votes as u128, 2))
        ) as u64
    };

    0
}

fun unlock_stake(
    court: &mut Court,
    key: address, 
    amount: u64,
    dispute_id: ID,
) {
    let stake = court.stakes.borrow_mut(key);
            
    stake.amount = stake.amount + amount;
    stake.locked_amount = stake.locked_amount - amount;

    if (stake.worker_pool_pos.is_some()) {
        court.worker_pool.add_stake(
            *stake.worker_pool_pos.borrow(), 
            amount,
        );
    };

    event::emit(BalanceUnlockEvent {
        court: object::id(court),
        nivster: key,
        unlocked_nvr: amount,
        dispute_id,
    });
}

fun unlock_stake_with_penalty(
    court: &mut Court,
    registry: &mut Registry,
    nivster: address,
    amount: u64,
    penalty: u64,
    dispute_id: ID,
) {
    let stake = court.stakes.borrow_mut(nivster);

    stake.amount = stake.amount + amount - penalty;
    stake.locked_amount = stake.locked_amount - amount;

    if (stake.worker_pool_pos.is_some()) {
        court.worker_pool.add_stake(
            *stake.worker_pool_pos.borrow(), 
            amount - penalty,
        );
    };

    registry.register_case_lost(nivster, penalty);

    event::emit(BalancePenaltyEvent {
        court: object::id(court),
        nivster: nivster,
        amount_nvr: penalty,
        unlocked_nvr: amount,
        dispute_id,
    });
}

fun unlock_stake_with_rewards(
    court: &mut Court, 
    registry: &mut Registry,
    nivster: address,
    amount: u64,
    reward_nvr: u64,
    reward_sui: u64,
    dispute_id: ID,
) {
    let stake = court.stakes.borrow_mut(nivster);

    stake.amount = stake.amount + amount + reward_nvr;
    stake.locked_amount = stake.locked_amount - amount;
    stake.reward_amount = stake.reward_amount + reward_sui;

    if (stake.worker_pool_pos.is_some()) {
        court.worker_pool.add_stake(
            *stake.worker_pool_pos.borrow(), 
            amount + reward_nvr,
        );
    };

    registry.register_case_won(nivster, reward_nvr, reward_sui);

    event::emit(BalanceRewardEvent {
        court: object::id(court),
        nivster: nivster,
        amount_nvr: reward_nvr,
        amount_sui: reward_sui,
        unlocked_nvr: amount,
        dispute_id,
    });
}

// === Test Functions ===
#[test_only]
public fun worker_pool_length_for_testing(court: &Court): u64 {
    court.worker_pool.length()
}

#[test_only]
public fun worker_pool_key_for_testing(court: &Court, idx: u64): address {
    court.worker_pool.key(idx)
}

#[test_only]
public fun worker_pool_bit_value_for_testing(court: &Court, idx: u64): u64 {
    worker_pool::bit_value_for_testing(&court.worker_pool, idx)
}

#[test_only]
public fun worker_pool_prefix_sum_for_testing(court: &Court, idx: u64): u64 {
    court.worker_pool.prefix_sum(idx)
}