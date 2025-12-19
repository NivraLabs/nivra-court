// © 2025 Nivra Labs Ltd.

module nivra::constants;

// === Constants ===
const CURRENT_VERSION: u64 = 1;

// === View Functions ===
/// Returns the current package version.
public fun current_version(): u64 {
    CURRENT_VERSION
}