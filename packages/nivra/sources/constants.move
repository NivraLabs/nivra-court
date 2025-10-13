module nivra::constants;

const CURRENT_VERSION: u64 = 1;

public fun current_version(): u64 {
    CURRENT_VERSION
}