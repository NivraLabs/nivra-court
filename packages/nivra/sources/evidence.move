// © 2025 Nivra Labs Ltd.

module nivra::evidence;

// === Imports ===

use std::string::String;
use sui::clock::Clock;
use nivra::dispute::{
    Dispute,
    PartyCap
};

// === Errors ===

const EInvalidPartyCap: u64 = 1;

// === Structs ===

public struct Evidence has key, store {
    id: UID,
    party_cap_id: ID,
    description: String,
    blob_id: Option<String>,      // Walrus blob ID
    file_name: Option<String>,
    file_type: Option<String>,
    file_subtype: Option<String>,
    encrypted: bool,
}

// === Public Functions ===

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
    let evidence = Evidence {
        id: object::new(ctx),
        party_cap_id: object::id(cap),
        description,
        blob_id,
        file_name,
        file_type,
        file_subtype,
        encrypted,
    };

    dispute.add_evidence(object::id(&evidence), cap, clock);
    transfer::share_object(evidence);
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
}

public fun destroy_evidence(
    dispute: &mut Dispute,
    cap: &PartyCap,
    evidence: Evidence,
    clock: &Clock,
) {
    assert!(object::id(cap) == evidence.party_cap_id, EInvalidPartyCap);

    dispute.remove_evidence(object::id(&evidence), cap, clock);

    let Evidence {
        id,
        party_cap_id: _,
        blob_id: _,
        description: _,
        file_name: _,
        file_type: _,
        file_subtype: _,
        encrypted: _,
    } = evidence;

    id.delete();
}