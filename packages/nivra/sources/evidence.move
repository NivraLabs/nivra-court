// © 2025 Nivra Labs Ltd.

module nivra::evidence;

// === Imports ===

use std::string::String;
use sui::clock::Clock;
use sui::event;
use nivra::dispute::{
    Dispute,
    PartyCap,
    VoterCap,
};

// === Errors ===

const EInvalidPartyCap: u64 = 1;
const EInvalidEvidence: u64 = 2;
const ENoCaseAccess: u64 = 3;

// === Structs ===

public struct Evidence has key, store {
    id: UID,
    party_cap_id: ID,
    dispute_id: ID,
    description: String,
    blob_id: Option<String>,      // Walrus blob ID
    file_name: Option<String>,
    file_type: Option<String>,
    file_subtype: Option<String>,
    encrypted: bool,
}

// === Events ===
public struct EvidenceCreationEvent has copy, drop {
    evidence_id: ID,
    dispute_id: ID,
    party: address,
    description: String,
    blob_id: Option<String>,
    file_name: Option<String>,
    file_type: Option<String>,
    file_subtype: Option<String>,
    encrypted: bool,
}

public struct EvidenceModificationEvent has copy, drop {
    evidence_id: ID,
    description: String,
    blob_id: Option<String>,
    file_name: Option<String>,
    file_type: Option<String>,
    file_subtype: Option<String>,
}

public struct EvidenceDestroyedEvent has copy, drop {
    evidence_id: ID,
}

// === Public Functions ===

entry fun seal_approve(
    id: vector<u8>,
    evidence: &Evidence,
    voter_cap: &VoterCap,
) {
    assert!(voter_cap.dispute_id_voter() == evidence.dispute_id, ENoCaseAccess);
    assert!(id == object::id(evidence).to_bytes(), EInvalidEvidence);
}

public fun create_evidence(
    dispute: &mut Dispute,
    description: String,
    blob_id: Option<String>,
    file_name: Option<String>,
    file_type: Option<String>,
    file_subtype: Option<String>,
    encrypted: bool,
    cap: &PartyCap, 
    clock: &Clock,
    ctx: &mut TxContext
) {
    let dispute_id = object::id(dispute);

    let evidence = Evidence {
        id: object::new(ctx),
        party_cap_id: object::id(cap),
        dispute_id,
        description,
        blob_id,
        file_name,
        file_type,
        file_subtype,
        encrypted,
    };

    let evidence_id = object::id(&evidence);

    dispute.add_evidence(evidence_id, cap, clock);
    transfer::share_object(evidence);

    event::emit(EvidenceCreationEvent {
        dispute_id,
        evidence_id,
        party: cap.party(),
        description,
        blob_id,
        file_name,
        file_type,
        file_subtype,
        encrypted,
    });
}

public fun modify_evidence(
    evidence: &mut Evidence,
    description: String,
    blob_id: Option<String>,
    file_name: Option<String>,
    file_type: Option<String>,
    file_subtype: Option<String>,
    cap: &PartyCap, 
) {
    assert!(object::id(cap) == evidence.party_cap_id, EInvalidPartyCap);

    evidence.description = description;
    evidence.blob_id = blob_id;
    evidence.file_name = file_name;
    evidence.file_type = file_type;
    evidence.file_subtype = file_subtype;

    event::emit(EvidenceModificationEvent {
        evidence_id: object::id(evidence),
        description,
        blob_id,
        file_name,
        file_type,
        file_subtype,
    });
}

public fun destroy_evidence(
    dispute: &mut Dispute,
    cap: &PartyCap,
    evidence: Evidence,
    clock: &Clock,
) {
    assert!(object::id(cap) == evidence.party_cap_id, EInvalidPartyCap);

    let evidence_id = object::id(&evidence);

    dispute.remove_evidence(evidence_id, cap, clock);

    let Evidence {
        id,
        party_cap_id: _,
        dispute_id: _,
        blob_id: _,
        description: _,
        file_name: _,
        file_type: _,
        file_subtype: _,
        encrypted: _,
    } = evidence;

    id.delete();

    event::emit(EvidenceDestroyedEvent { 
        evidence_id,
    });
}