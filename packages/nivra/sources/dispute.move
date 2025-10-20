module nivra::dispute;

use std::ascii::String;
use sui::linked_table::{Self, LinkedTable};
use sui::clock::Clock;
use seal::bf_hmac_encryption::{
    EncryptedObject,
};

public struct PartyCap has key, store {
    id: UID,
    dispute_id: ID,
    party: address,
}

public struct VoterCap has key, store {
    id: UID,
    dispute_id: ID,
    voter: address,
}

public struct VoterDetails has copy, drop, store {
    stake: u64,
    vote: Option<EncryptedObject>,
    multiplier: u64,
    cap_issued: bool,
}

public struct TimeTable has copy, drop, store {
    round_init_ms: u64,
    evidence_period_ms: u64,
    voting_period_ms: u64,
    appeal_period_ms: u64,
}

public struct Dispute has key {
    id: UID,
    contract: ID,
    description: String,
    round: u16,
    timetable: TimeTable,
    max_appeals: u8,
    parties: vector<address>,
    voters: LinkedTable<address, VoterDetails>,
    options: vector<String>,
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
}

public(package) fun create_voter_details(stake: u64): VoterDetails {
    VoterDetails {
        stake,
        vote: std::option::none(),
        multiplier: 1,
        cap_issued: false,
    }
}

public(package) fun increase_multiplier(self: &mut VoterDetails) {
    self.multiplier = self.multiplier + 1;
}

public(package) fun increase_stake(self: &mut VoterDetails, stake: u64) {
    self.stake = self.stake + stake;
}

public(package) fun create_dispute(
    contract: ID,
    description: String,
    evidence_period_ms: u64,
    voting_period_ms: u64,
    appeal_period_ms: u64,
    max_appeals: u8,
    parties: vector<address>,
    voters: LinkedTable<address, VoterDetails>,
    options: vector<String>,
    key_servers: vector<address>,
    public_keys: vector<vector<u8>>,
    clock: &Clock,
    ctx: &mut TxContext,
): Dispute {
    Dispute {
        id: object::new(ctx),
        contract,
        description,
        round: 1,
        timetable: TimeTable {
            round_init_ms: clock.timestamp_ms(),
            evidence_period_ms,
            voting_period_ms,
            appeal_period_ms,
        },
        max_appeals,
        parties,
        voters,
        options,
        key_servers,
        public_keys,
    }
}

public(package) fun distribute_voter_caps(dispute: &mut Dispute, ctx: &mut TxContext) {
    let mut i = linked_table::front(&dispute.voters);

    while(i.is_some()) {
        let k = *i.borrow();
        let v = dispute.voters.borrow_mut(k);

        if (!v.cap_issued) {
            v.cap_issued = true;
            transfer::public_transfer(VoterCap {
                id: object::new(ctx),
                dispute_id: object::id(dispute),
                voter: k,
            }, k);
        };

        i = dispute.voters.next(k);
    };
}

public(package) fun share_dispute(dispute: Dispute, ctx: &mut TxContext) {
    dispute.parties.do_ref!(|party| {
        transfer::public_transfer(PartyCap {
            id: object::new(ctx),
            dispute_id: object::id(&dispute),
            party: *party,
        }, *party)
    });

    let mut dispute = dispute;
    distribute_voter_caps(&mut dispute, ctx);

    transfer::share_object(dispute);
}