module nivra::evidence;

use std::ascii::String;

public struct Evidence has key, store {
    id: UID,
    description: String,
    blob_id: Option<String>,
    file_type: Option<String>,
    file_subtype: Option<String>,
}

public(package) fun create_evidence(
    description: String,
    blob_id: Option<String>,
    file_type: Option<String>,
    file_subtype: Option<String>,
    ctx: &mut TxContext
): Evidence {
    Evidence {
        id: object::new(ctx),
        description,
        blob_id,
        file_type,
        file_subtype,
    }
}

public(package) fun modify_evidence(
    evidence: &mut Evidence,
    description: String,
    blob_id: Option<String>,
    file_type: Option<String>,
    file_subtype: Option<String>,
) {
    evidence.description = description;
    evidence.blob_id = blob_id;
    evidence.file_type = file_type;
    evidence.file_subtype = file_subtype;
}

public(package) fun destruct_evidence(
    evidence: Evidence
) {
    let Evidence {
        id,
        blob_id: _,
        description: _,
        file_type: _,
        file_subtype: _,
    } = evidence;

    id.delete();
}