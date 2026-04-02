// © 2026 Nivra Labs Ltd.

module nivra::evidence;

// === Imports ===
use std::string::String;
use sui::clock::Clock;
use nivra::dispute::Dispute;
use sui::event;
use nivra::constants::max_evidence_description_length;
use nivra::constants::max_src;
use nivra::constants::max_file_name;
use nivra::constants::max_file_type;
use nivra::constants::max_file_subtype;

// === Errors ===
const EInvalidEvidence: u64 = 1;
const ENoCaseAccess: u64 = 2;
const ENotEncrypted: u64 = 3;
const ENotEvidencePeriod: u64 = 4;
const ENotDisputeParty: u64 = 5;
const ENotOwner: u64 = 6;
const EWrongDispute: u64 = 7;

// === Structs ===
public struct Evidence has key, store {
    id: UID,
    dispute_id: ID,
    owner: address,
    description: String,
    src: Option<String>,
    file_name: Option<String>,
    file_type: Option<String>,
    file_subtype: Option<String>,
    encrypted: bool,
}

// === Events ===
public struct EvidenceCreatedEvent has copy, drop {
    dispute: ID,
    evidence: ID,
    party: address,
    description: String,
    src: Option<String>,
    file_name: Option<String>,
    file_type: Option<String>,
    file_subtype: Option<String>,
    encrypted: bool,
}

public struct EvidenceModifiedEvent has copy, drop {
    evidence: ID,
    description: String,
    src: Option<String>,
    file_name: Option<String>,
    file_type: Option<String>,
    file_subtype: Option<String>,
    encrypted: bool,
}

public struct EvidenceRemovedEvent has copy, drop {
    evidence: ID,
}

// === Public Functions ===
entry fun seal_approve(
    id: vector<u8>,
    evidence: &Evidence,
    dispute: &Dispute,
    ctx: &TxContext,
) {
    assert!(id == object::id(evidence).to_bytes(), EInvalidEvidence);
    assert!(evidence.encrypted, ENotEncrypted);
    assert!(evidence.dispute_id == object::id(dispute), EWrongDispute);
    assert!(
        dispute.is_party(ctx.sender()) || dispute.is_voter(ctx.sender()), 
        ENoCaseAccess
    );
}

public fun create_evidence(
    dispute: &mut Dispute,
    description: String,
    src: Option<String>,
    file_name: Option<String>,
    file_type: Option<String>,
    file_subtype: Option<String>,
    encrypted: bool,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // File metadata must be provided if a source is defined.
    // If not, metadata must be set to null.
    if (src.is_some()) {
        assert!((*src.borrow()).length() <= max_src(), EInvalidEvidence);
        assert!(
            file_name.is_some() && 
            (*file_name.borrow()).length() <= max_file_name(), 
            EInvalidEvidence
        );
        assert!(
            file_type.is_some() && 
            (*file_type.borrow()).length() <= max_file_type(), 
            EInvalidEvidence
        );
        assert!(
            file_subtype.is_some() && 
            (*file_subtype.borrow()).length() <= max_file_subtype(), 
            EInvalidEvidence
        );
    } else {
        assert!(file_name.is_none(), EInvalidEvidence);
        assert!(file_type.is_none(), EInvalidEvidence);
        assert!(file_subtype.is_none(), EInvalidEvidence);
        assert!(!encrypted, EInvalidEvidence);
    };

    assert!(
        description.length() <= max_evidence_description_length(), 
        EInvalidEvidence
    );

    // Check if user is allowed to submit evidence.
    assert!(dispute.is_party(ctx.sender()), ENotDisputeParty);
    assert!(dispute.is_evidence_period(clock), ENotEvidencePeriod);

    let evidence = Evidence {
        id: object::new(ctx),
        dispute_id: object::id(dispute),
        owner: ctx.sender(),
        description,
        src,
        file_name,
        file_type,
        file_subtype,
        encrypted,
    };

    let evidence_id = object::id(&evidence);

    dispute.add_evidence(ctx.sender(), evidence_id);
    transfer::share_object(evidence);

    event::emit(EvidenceCreatedEvent {
        dispute: object::id(dispute),
        evidence: evidence_id,
        party: ctx.sender(),
        description,
        src,
        file_name,
        file_type,
        file_subtype,
        encrypted,
    });
}

public fun modify_evidence(
    evidence: &mut Evidence,
    dispute: &Dispute,
    description: String,
    src: Option<String>,
    file_name: Option<String>,
    file_type: Option<String>,
    file_subtype: Option<String>,
    encrypted: bool,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // File metadata must be provided if a source is defined.
    // If not, metadata must be set to null.
    if (src.is_some()) {
        assert!((*src.borrow()).length() <= max_src(), EInvalidEvidence);
        assert!(
            file_name.is_some() && 
            (*file_name.borrow()).length() <= max_file_name(), 
            EInvalidEvidence
        );
        assert!(
            file_type.is_some() && 
            (*file_type.borrow()).length() <= max_file_type(), 
            EInvalidEvidence
        );
        assert!(
            file_subtype.is_some() && 
            (*file_subtype.borrow()).length() <= max_file_subtype(), 
            EInvalidEvidence
        );
    } else {
        assert!(file_name.is_none(), EInvalidEvidence);
        assert!(file_type.is_none(), EInvalidEvidence);
        assert!(file_subtype.is_none(), EInvalidEvidence);
        assert!(!encrypted, EInvalidEvidence);
    };

    assert!(
        description.length() <= max_evidence_description_length(), 
        EInvalidEvidence
    );

    // Check if user is allowed to modify the evidence.
    assert!(evidence.owner == ctx.sender(), ENotOwner);
    assert!(evidence.dispute_id == object::id(dispute), EWrongDispute);
    assert!(dispute.is_evidence_period(clock), ENotEvidencePeriod);

    evidence.description = description;
    evidence.src = src;
    evidence.file_name = file_name;
    evidence.file_type = file_type;
    evidence.file_subtype = file_subtype;
    evidence.encrypted = encrypted;

    event::emit(EvidenceModifiedEvent {
        evidence: object::id(evidence),
        description,
        src,
        file_name,
        file_type,
        file_subtype,
        encrypted,
    });
}

public fun remove_evidence(
    evidence: Evidence,
    dispute: &mut Dispute,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // Check if user is allowed to remove the evidence.
    assert!(evidence.owner == ctx.sender(), ENotOwner);
    assert!(evidence.dispute_id == object::id(dispute), EWrongDispute);
    assert!(dispute.is_evidence_period(clock), ENotEvidencePeriod);

    let evidence_id = object::id(&evidence);
    dispute.remove_evidence(ctx.sender(), evidence_id);

    let Evidence {
        id,
        dispute_id: _,
        owner: _,
        description: _,
        src: _,
        file_name: _,
        file_type: _,
        file_subtype: _,
        encrypted: _,
    } = evidence;

    id.delete();

    event::emit(EvidenceRemovedEvent {
        evidence: evidence_id,
    });
}