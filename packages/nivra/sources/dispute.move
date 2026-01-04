// © 2025 Nivra Labs Ltd.

module nivra::dispute;

// === Imports ===
use std::string::String;
use sui::{
    linked_table::{Self, LinkedTable},
    clock::Clock,
    vec_map::{Self, VecMap},
    bls12381::g1_from_bytes
};
use seal::bf_hmac_encryption::{
    EncryptedObject,
    parse_encrypted_object,
    VerifiedDerivedKey,
    verify_derived_keys,
    new_public_key,
    PublicKey,
    decrypt
};

// === Errors ===

const EEvidenceFull: u64 = 1;
const ENotPartyMember: u64 = 2;
const ENoEvidenceFound: u64 = 3;
const ENotEvidencePeriod: u64 = 4;
const EInvalidVote: u64 = 5;
const ENotVotingPeriod: u64 = 6;
const ENotVoter: u64 = 7;
const EVotingPeriodNotEnded: u64 = 8;
const ENotEnoughKeys: u64 = 9;
const EAlreadyFinalized: u64 = 10;
const EInvalidDispute: u64 = 11;

// === Structs ===

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
    decrypted_vote: Option<u8>,
    cap_issued: bool,
}

// === Package Functions ===

public(package) fun create_voter_details(stake: u64): VoterDetails {
    VoterDetails {
        stake,
        vote: std::option::none(),
        decrypted_vote: std::option::none(),
        cap_issued: false,
    }
}