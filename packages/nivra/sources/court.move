// © 2025 Nivra Labs Ltd.

module nivra::court;

// === Imports ===
use std::string::String;
use sui::{
    versioned::{Self, Versioned},
    balance::{Self, Balance},
    coin::{Self, Coin},
    linked_table::{Self, LinkedTable},
    table::{Self, Table},
    random::{Random, new_generator},
    clock::Clock,
    sui::SUI,
    linked_table::borrow_mut,
    event,
    vec_map::{Self, VecMap},
};
use token::nvr::NVR;
use nivra::court_registry::CourtRegistry;
use nivra::court_registry::NivraAdminCap;
use nivra::constants::current_version;
use nivra::court_registry::create_metadata;
use nivra::dispute::VoterDetails;
use nivra::dispute::create_voter_details;
use nivra::dispute::create_dispute;
use nivra::dispute::Dispute;
use nivra::dispute::PartyCap;
use nivra::constants::dispute_status_active;
use nivra::constants::dispute_status_response;
use nivra::result::create_result;
use nivra::constants::dispute_status_canceled;
use std::u64::pow;
use std::u64::divide_and_round_up;

// === Constants ===
const DRAW_STATUS_NOT_ENOUGH_NIVSTERS: u64 = 0;
const DRAW_STATUS_SUCCESS: u64 = 1;
// Default dispute rules
const INIT_NIVSTER_COUNT: u64 = 1; // TODO: increase nivster count after testing
const TIE_NIVSTER_COUNT: u64 = 1;
const MIN_OPTIONS: u64 = 2;
const MAX_OPTIONS: u64 = 10;
const PARTY_COUNT: u64 = 2;
const MAX_APPEALS: u8 = 3;
// Dispute creation error event codes
const NOT_ENOUGH_NIVSTERS_INIT: u64 = 1;
const EXISTING_DISPUTE: u64 = 2;
// Dispute error event codes
const NOT_ENOUGH_NIVSTERS_TIE: u64 = 1;

// === Errors ===
const EWrongVersion: u64 = 1;
const ENotUpgrade: u64 = 2;
const ENotEnoughNVR: u64 = 3;
const ENotOperational: u64 = 4;
const EInvalidFee: u64 = 5;
const ENotResponsePeriod: u64 = 7;
const ENoDisputeAccess: u64 = 8;
const EDisputeNotTie: u64 = 9;
const ENoAppealsLeft: u64 = 10;
const EInvalidOptionsAmount: u64 = 12;
const EBalanceMismatchInternal: u64 = 18;
const ENivsterMismatchInternal: u64 = 19;
const EWrongParty: u64 = 20;
const EInvalidPartyCount: u64 = 21;
const EInitiatorNotParty: u64 = 22;
const EInvalidAppealCount: u64 = 23;
const EInvalidLockAmountInternal: u64 = 24;
const ENotAppealPeriodTallied: u64 = 25;
const EDisputeNotCompleted: u64 = 26;
const ENotEnoughSUI: u64 = 27;

// === Structs ===
public enum Status has copy, drop, store {
    Running,
    Halted,
}

public struct Stake has copy, drop, store {
    amount: u64,        // NVR
    locked_amount: u64, // NVR
    reward_amount: u64, // SUI
}

public struct DisputeDetails has store {
    dispute_id: ID,
    depositors: VecMap<address, u64>, // Amount per address
    pool: Balance<SUI>,
}

public struct Court has key {
    id: UID,
    inner: Versioned,
}

public struct CourtInner has store {
    ai_court: bool,
    status: Status,
    cases: Table<ID, DisputeDetails>,
    stake_pool: Balance<NVR>,
    reward_pool: Balance<SUI>,
    stakes: LinkedTable<address, Stake>,
    dispute_fee: u64,
    min_stake: u64,
    default_response_period_ms: u64,
    default_evidence_period_ms: u64,
    default_voting_period_ms: u64,
    default_appeal_period_ms: u64,
}

// === Events ===

public struct StakeEvent has copy, drop {
    sender: address,
    amount: u64,
}

public struct WithdrawEvent has copy, drop {
    sender: address,
    amount_nvr: u64,
    amount_sui: u64,
}

public struct DisputeCreationErrorEvent has copy, drop {
    sender: address,
    contract: ID,
    error_code: u64,
}

public struct DisputeErrorEvent has copy, drop {
    sender: address,
    dispute_id: ID,
    error_code: u64,
}

// === Public Functions ===

public fun stake(self: &mut Court, assets: Coin<NVR>, ctx: &mut TxContext) {
    let self = self.load_inner_mut();
    let amount = assets.value();
    assert!(amount >= self.min_stake, ENotEnoughNVR);
    assert!(self.status == Status::Running, ENotOperational);

    coin::put(&mut self.stake_pool, assets);
    let sender = ctx.sender();

    if (self.stakes.contains(sender)) {
        let stake = self.stakes.borrow_mut(sender);
        stake.amount = stake.amount + amount;
    } else {
        self.stakes.push_back(sender, Stake {
            amount,
            locked_amount: 0,
            reward_amount: 0,
        });
    };

    event::emit(StakeEvent { 
        sender, 
        amount, 
    });
}

public fun withdraw(
    self: &mut Court, 
    amount_nvr: u64,
    amount_sui: u64,
    ctx: &mut TxContext,
): (Coin<NVR>, Coin<SUI>) {
    let self = self.load_inner_mut();
    let sender = ctx.sender();
    let stake = self.stakes.borrow_mut(sender);

    // Check balances.
    assert!(stake.amount >= amount_nvr, ENotEnoughNVR);
    assert!(stake.reward_amount >= amount_sui, ENotEnoughSUI);

    // Deduct amounts.
    stake.amount = stake.amount - amount_nvr;
    stake.reward_amount = stake.reward_amount - amount_sui;

    let nvr = self.stake_pool.split(amount_nvr).into_coin(ctx);
    let sui = self.reward_pool.split(amount_sui).into_coin(ctx);

    // Remove empty balances from the list.
    if (stake.amount == 0 && stake.locked_amount == 0 && stake.reward_amount == 0) {
        self.stakes.remove(sender);
    };

    event::emit(WithdrawEvent { 
        sender, 
        amount_nvr,
        amount_sui,
    });
    
    (nvr, sui)
}

public fun distribute_rewards(
    court: &mut Court,
    dispute: &mut Dispute,
    registry: &CourtRegistry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(dispute.is_completed(clock), EDisputeNotCompleted);

    //TODO
}

public fun cancel_dispute(
    court: &mut Court,
    court_registry: &CourtRegistry,
    dispute: &mut Dispute,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let self = court.load_inner_mut();

    // The other party did not accept the dispute/appeal in time. Party with more deposits wins by default.
    if (!dispute.is_response_period(clock) && dispute.status() == dispute_status_response()) {
        let mut case = self.cases.remove(dispute.contract());

        // Get the winner address & winner's deposit amount
        let (mut winner_address, mut highest_deposit) = case.depositors.get_entry_by_idx(0);

        if (case.depositors.length() == 2) {
            let (other_party, deposit) = case.depositors.get_entry_by_idx(1);

            if (*deposit > *highest_deposit) {
                winner_address = other_party;
                highest_deposit = deposit;
            };
        };

        // Get the index of the winner address.
        let winner_party = dispute.parties()
        .find_index!(|addr| addr == winner_address)
        .map!(|val| val as u8 )
        .extract();

        // Refund the winner
        transfer::public_transfer(case.pool.split(*highest_deposit).into_coin(ctx), *winner_address);

        // Distribute rewards & refund stakes
        let voters = dispute.voters();
        let remaining_amount = case.pool.value();
        let nivra_cut = std::uq64_64::from_int(remaining_amount)
        .div(std::uq64_64::from_int(20))
        .to_int(); // 5%
        let nivster_cut = std::uq64_64::from_int(remaining_amount - nivra_cut)
        .div(std::uq64_64::from_int(voters.length()))
        .to_int();

        transfer::public_transfer(case.pool.split(nivra_cut).into_coin(ctx), court_registry.treasury_address());
        self.reward_pool.join(case.pool.withdraw_all());

        let mut i = linked_table::front(voters);

        while(i.is_some()) {
            let k = *i.borrow();
            let v = voters.borrow(k);
            let stake = self.stakes.borrow_mut(k);

            // Failsafe. Should never throw.
            assert!(stake.locked_amount >= v.stake(), EInvalidLockAmountInternal);

            stake.locked_amount = stake.locked_amount - v.stake();
            stake.amount = stake.amount + v.stake();
            stake.reward_amount = stake.reward_amount + nivster_cut;
            i = voters.next(k);
        };

        // Distribute result to both parties.
        dispute.parties().do!(|party| transfer::public_transfer(
            create_result(
                object::id(dispute), 
                dispute.contract(), 
                dispute.options(), 
                option::none(), 
                dispute.parties(), 
                winner_party,
                dispute.max_appeals(),
                ctx
            ), party)
        );

        // Destroy the case
        let DisputeDetails { 
            dispute_id: _,
            depositors: _,
            pool, 
        } = case;

        pool.destroy_zero();

        // Change status to cancelled
        dispute.set_status(dispute_status_canceled());
    };

    // Dispute is incomplete (not tallied or unresolved tie) and fully refunded.
    if (dispute.is_incomplete(clock)) {
        let mut case = self.cases.remove(dispute.contract());

        // Refund parties
        let (address_1, deposit_1) = case.depositors.get_entry_by_idx(0);
        let (address_2, _) = case.depositors.get_entry_by_idx(1);

        transfer::public_transfer(case.pool.split(*deposit_1).into_coin(ctx), *address_1);
        transfer::public_transfer(case.pool.withdraw_all().into_coin(ctx), *address_2);

        // Unlock stakes
        let voters = dispute.voters();
        let mut i = linked_table::front(voters);

        while(i.is_some()) {
            let k = *i.borrow();
            let v = voters.borrow(k);
            let stake = self.stakes.borrow_mut(k);

            // Failsafe. Should never throw.
            assert!(stake.locked_amount >= v.stake(), EInvalidLockAmountInternal);

            stake.locked_amount = stake.locked_amount - v.stake();
            stake.amount = stake.amount + v.stake();
            i = voters.next(k);
        };

        // Destroy the case
        let DisputeDetails { 
            dispute_id: _,
            depositors: _,
            pool, 
        } = case;

        pool.destroy_zero();

        // Change status to cancelled
        dispute.set_status(dispute_status_canceled());
    };
}

public fun accept_dispute(
    court: &mut Court,
    dispute: &mut Dispute,
    fee: Coin<SUI>,
    cap: &PartyCap,
    clock: &Clock,
) {
    assert!(dispute.is_response_period(clock), ENotResponsePeriod);
    assert!(object::id(dispute) == cap.dispute_id_party(), ENoDisputeAccess);

    let self = court.load_inner_mut();
    let appeal_count = dispute.appeals_used();

    // Fee = 13^i * Fn / 5^i, where Fn = base dispute fee & i = appeal count.
    let outstanding_fee = divide_and_round_up(self.dispute_fee * pow(13, appeal_count), pow(5, appeal_count));
    assert!(fee.value() == outstanding_fee, EInvalidFee);

    let dispute_details = self.cases.borrow_mut(dispute.contract());
    let mut depositors = dispute_details.depositors;

    if (depositors.length() == 2) {
        // Dispute appeal scenario.
        let payer_balance = depositors.get_mut(&cap.party());
        *payer_balance = *payer_balance + fee.value();
    } else {
        // Dispute opening scenario. The other party has not made deposits yet.
        depositors.insert(cap.party(), fee.value());
    };

    // Make sure that the fee is paid by the opposing party.
    let (_, balance) = depositors.get_entry_by_idx(0);
    let (_, balance_other) = depositors.get_entry_by_idx(1);
    assert!(balance == balance_other, EWrongParty);

    dispute_details.pool.join(fee.into_balance());

    // Dispute status is set to active after the other party accepts the case.
    dispute.set_status(dispute_status_active());
}

entry fun open_dispute(
    court: &mut Court,
    fee: Coin<SUI>,
    contract: ID,
    description: String,
    parties: vector<address>,
    options: vector<String>,
    max_appeals: u8,
    response_period_ms: Option<u64>,
    evidence_period_ms: Option<u64>,
    voting_period_ms: Option<u64>,
    appeal_period_ms: Option<u64>,
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
    threshold: u8,
    r: &Random,
    clock: &Clock, 
    ctx: &mut TxContext
) {
    let court_id = object::id(court);
    let self = court.load_inner_mut();

    assert!(self.status == Status::Running, ENotOperational);
    assert!(fee.value() == self.dispute_fee, EInvalidFee);
    assert!(options.length() >= MIN_OPTIONS && options.length() <= MAX_OPTIONS, EInvalidOptionsAmount);
    assert!(parties.length() == PARTY_COUNT, EInvalidPartyCount);
    assert!(parties.contains(&ctx.sender()), EInitiatorNotParty);
    assert!(max_appeals <= MAX_APPEALS, EInvalidAppealCount);

    // Allow only 1 dispute to exist at a time per contract instance.
    if(self.cases.contains(contract)) {
        event::emit(DisputeCreationErrorEvent {
            sender: ctx.sender(),
            contract,
            error_code: EXISTING_DISPUTE,
        });

        transfer::public_transfer(fee, ctx.sender());
        return
    };

    // Unwrap dispute timetable or use court defaults if not specified.
    let response_period = response_period_ms.destroy_or!(self.default_response_period_ms);
    let evidence_period = evidence_period_ms.destroy_or!(self.default_evidence_period_ms);
    let voting_period = voting_period_ms.destroy_or!(self.default_voting_period_ms);
    let appeal_period = appeal_period_ms.destroy_or!(self.default_appeal_period_ms);

    // Draw initial nivsters to the case.
    let mut nivsters = linked_table::new(ctx);
    let draw_status = draw_nivsters(self, &mut nivsters, INIT_NIVSTER_COUNT, r, ctx);

    // Not enough nivsters to start a dispute
    if (draw_status == DRAW_STATUS_NOT_ENOUGH_NIVSTERS) {
        event::emit(DisputeCreationErrorEvent {
            sender: ctx.sender(),
            contract,
            error_code: NOT_ENOUGH_NIVSTERS_INIT,
        });

        nivsters.destroy_empty();
        transfer::public_transfer(fee, ctx.sender());
        return
    };

    let dispute_id = create_dispute(
        ctx.sender(),
        contract,
        court_id,
        description,
        response_period,
        evidence_period, 
        voting_period, 
        appeal_period, 
        max_appeals, 
        parties, 
        nivsters, 
        options, 
        key_servers, 
        public_keys, 
        threshold,
        clock, 
        ctx
    );

    // Fill in dispute details and place into case map.
    let mut dispute_details = DisputeDetails {
        dispute_id,
        depositors: vec_map::empty(),
        pool: balance::zero(),
    };

    dispute_details.depositors.insert(ctx.sender(), fee.value());
    coin::put(&mut dispute_details.pool, fee);

    self.cases.add(contract, dispute_details);
}

entry fun handle_dispute_tie(
    court: &mut Court,
    dispute: &mut Dispute,
    clock: &Clock,
    r: &Random,
    ctx: &mut TxContext,
) {
    assert!(dispute.is_appeal_period_tie(clock), EDisputeNotTie);

    let court = court.load_inner_mut();
    let draw_status = court.draw_nivsters(dispute.voters_mut(), TIE_NIVSTER_COUNT, r, ctx);

    if (draw_status == DRAW_STATUS_NOT_ENOUGH_NIVSTERS) {
        event::emit(DisputeErrorEvent {
            sender: ctx.sender(),
            dispute_id: object::id(dispute),
            error_code: NOT_ENOUGH_NIVSTERS_TIE,
        });

        return
    };

    dispute.start_new_round_tie(clock, ctx);
}

entry fun open_appeal(
    court: &mut Court,
    dispute: &mut Dispute,
    fee: Coin<SUI>,
    cap: &PartyCap,
    clock: &Clock,
    r: &Random,
    ctx: &mut TxContext,
) {
    assert!(object::id(dispute) == cap.dispute_id_party(), ENoDisputeAccess);
    assert!(dispute.is_appeal_period_tallied(clock), ENotAppealPeriodTallied);
    assert!(dispute.has_appeals_left(), ENoAppealsLeft);

    let self = court.load_inner_mut();
    let appeal_count = dispute.appeals_used() + 1;

    // Fee = 13^i * Fn / 5^i, where Fn = base dispute fee & i = appeal count.
    let appeal_fee = divide_and_round_up(self.dispute_fee * pow(13, appeal_count), pow(5, appeal_count));
    assert!(fee.value() == appeal_fee, EInvalidFee);

    // Nivster amount n shall increase to 2n + 1 on every appeal.
    let nivster_count = dispute.voters().length() + 1;
    let draw_status = self.draw_nivsters(dispute.voters_mut(), nivster_count, r, ctx);

    // Not enough nivsters for the appeal.
    if (draw_status == DRAW_STATUS_NOT_ENOUGH_NIVSTERS) {
        event::emit(DisputeErrorEvent {
            sender: ctx.sender(),
            dispute_id: object::id(dispute),
            error_code: NOT_ENOUGH_NIVSTERS_INIT,
        });

        transfer::public_transfer(fee, ctx.sender());
        return
    };

    // Deposit coins
    let case = self.cases.borrow_mut(dispute.contract());
    let deposit = case.depositors.get_mut(&cap.party());
    *deposit = *deposit + fee.value();
    case.pool.join(fee.into_balance());

    // Start a new appeal round
    dispute.start_new_round_appeal(clock, ctx);
}

// === Admin Functions ===

public fun create_court(
    court_registry: &mut CourtRegistry,
    _cap: &NivraAdminCap,
    ai_court: bool,
    category: String,
    name: String,
    description: String,
    skills: String,
    min_stake: u64,
    dispute_fee: u64,
    default_response_period_ms: u64,
    default_evidence_period_ms: u64,
    default_voting_period_ms: u64,
    default_appeal_period_ms: u64,
    ctx: &mut TxContext,
): ID {
    let court_inner = CourtInner {
        ai_court,
        status: Status::Running,
        cases: table::new(ctx),
        stake_pool: balance::zero<NVR>(),
        reward_pool: balance::zero<SUI>(),
        stakes: linked_table::new(ctx),
        dispute_fee, 
        min_stake,
        default_response_period_ms,
        default_evidence_period_ms,
        default_voting_period_ms,
        default_appeal_period_ms,
    };

    let court = Court { 
        id: object::new(ctx), 
        inner: versioned::create(
            current_version(), 
            court_inner, 
            ctx
        ),
    };

    let court_id = object::id(&court);
    let metadata = create_metadata(
        category, 
        name, 
        description, 
        skills, 
        min_stake, 
    );

    court_registry.register_court(court_id, metadata);
    transfer::share_object(court);

    court_id
}

public fun halt_operation(self: &mut Court, _cap: &NivraAdminCap) {
    let self = self.load_inner_mut();
    self.status = Status::Halted;
}

entry fun migrate(self: &mut Court, _cap: &NivraAdminCap) {
    assert!(self.inner.version() < current_version(), ENotUpgrade);
    let (inner, cap) = self.inner.remove_value_for_upgrade<CourtInner>();
    self.inner.upgrade(current_version(), inner, cap);
}

// === Package Functions ===

public(package) fun draw_nivsters(
    self: &mut CourtInner, 
    nivsters: &mut LinkedTable<address, VoterDetails>, 
    nivster_count: u64,
    r: &Random,
    ctx: &mut TxContext,
): u64 {
    let nivster_start_count: u64 = nivsters.length();

    let mut potential_nivsters: u64 = 0;
    let mut staked_amount: u64 = 0;
    let mut i = linked_table::front(&self.stakes);

    // Calculate potential nivster count & their total staked amount
    while (i.is_some()) {
        let k = *i.borrow();
        let v = self.stakes.borrow(k);

        // Nivsters with less than min_stake or those already selected are disqualified.
        if (v.amount >= self.min_stake && !nivsters.contains(k)) {
            potential_nivsters = potential_nivsters + 1;
            staked_amount = staked_amount + v.amount;
        };

        i = self.stakes.next(k);
    };

    // Return not enough nivsters if draw is not possible.
    if (potential_nivsters < nivster_count) {
        return DRAW_STATUS_NOT_ENOUGH_NIVSTERS
    };

    let mut nivsters_selected = 0;
    let mut generator = new_generator(r, ctx);

    // Draw nivsters to nivsters list until nivster count is satisified.
    loop {
        if (nivsters_selected >= nivster_count) {
            break
        };

        let mut cum_stake_sum = 0;
        let mut nivster_found = false;
        let next_nivster = generator.generate_u64_in_range(0, staked_amount);
        i = linked_table::front(&self.stakes);

        // Next nivster is the one whose cumulative stake sum >= random[0, staked_amount].
        // -> Nivsters with larger stakes have better hit rate.
        // Full list is always looped per draw to make every draw consume the same amount of resources.
        while (i.is_some()) {
            let k = *i.borrow();
            let v = self.stakes.borrow_mut(k);

            // Skip nivsters with less than min_stake or those already selected.
            if (v.amount < self.min_stake || nivsters.contains(k)) {
                i = self.stakes.next(k);
                continue
            };

            cum_stake_sum = cum_stake_sum + v.amount;

            // Create voter details for the selected nivster.
            if (cum_stake_sum >= next_nivster && !nivster_found) {
                // Failsafe. Should never throw.
                assert!(v.amount >= self.min_stake, EBalanceMismatchInternal);
                nivsters.push_back(k, create_voter_details(self.min_stake));

                // Deduct nivster's staked amount from total staked amount for the next draw.
                staked_amount = staked_amount - v.amount;
                // Lock the min stake amount from the total balance.
                v.amount = v.amount - self.min_stake;
                v.locked_amount = self.min_stake;
                // Mark nivster to be found for the round.
                nivster_found = true;
            };

            i = self.stakes.next(k);
        };

        nivsters_selected = nivsters_selected + 1;
    };
    // Failsafe. Should never throw.
    assert!(nivsters.length() == nivster_start_count + nivster_count, ENivsterMismatchInternal);
    // Return success.
    DRAW_STATUS_SUCCESS
}

public(package) fun load_inner_mut(self: &mut Court): &mut CourtInner {
    assert!(self.inner.version() == current_version(), EWrongVersion);
    self.inner.load_value_mut()
}

public(package) fun load_inner(self: &Court): &CourtInner {
    assert!(self.inner.version() == current_version(), EWrongVersion);
    self.inner.load_value()
}