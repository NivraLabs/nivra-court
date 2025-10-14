module nivra::court;

use std::ascii::String;
use sui::url::Url;

public struct Metadata has copy, drop, store {
    category: String,
    name: String,
    icon: Option<Url>,
    description: String,
    skills: vector<String>,
    min_stake: u64, // (NVR)
    reward: u64, // (Sui)
}