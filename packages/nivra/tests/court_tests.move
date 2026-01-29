#[test_only]
module nivra::court_tests;

use nivra::court::nivsters_take;
use std::string::String;
use nivra::court::serialize_dispute_config;

/// This test validates that the same dispute configs with different ordering
/// have the same serialization value. 
#[test]
fun test_serialize_dispute_config() {
    let alice = @0x1;
    let bob = @0x2;
    let mut scenario = sui::test_scenario::begin(alice);

    let contract_id = 
    object::new(sui::test_scenario::ctx(&mut scenario));
    let mut parties: vector<address> = vector::empty();
    let mut parties_reversed: vector<address> = vector::empty();
    let mut options: vector<String> = vector::empty();
    let mut options_reordered: vector<String> = vector::empty();

    // Populate parties
    parties.push_back(alice);
    parties.push_back(bob);
    parties_reversed.push_back(bob);
    parties_reversed.push_back(alice);

    // Populate options
    let option_1: String = "yes";
    let option_2: String = "yse";
    let option_3: String = "test";

    options.push_back(option_1);
    options.push_back(option_2);
    options.push_back(option_3);

    options_reordered.push_back(option_2);
    options_reordered.push_back(option_1);
    options_reordered.push_back(option_3);

    // Serialize configs
    let serialized_1 = serialize_dispute_config(
        *contract_id.as_inner(), 
        parties, 
        options, 
        3
    );

    let serialized_2 = serialize_dispute_config(
        *contract_id.as_inner(), 
        parties_reversed, 
        options_reordered, 
        3
    );

    assert!(serialized_1 == serialized_2);

    contract_id.delete();

    sui::test_scenario::end(scenario);
}

#[test]
fun test_nivsters_take() {
    let dispute_fee = 10_000_000_000;
    let treasury_share = 5; // in percentages scaled by 100
    let appeals = 0;
    let init_nivster_count = 10;

    // The expected cut is F(n) * (1 - a), where F(n) = dispute_fee and
    // a = treasury_share [0,1]
    let cut = nivsters_take(
        dispute_fee, 
        treasury_share, 
        appeals, 
        init_nivster_count
    );

    assert!(cut == 9_500_000_000);

    // The expected cut is F(n) * (1 - a) * (2^i + (2^i - 1) / N) + round(0) cut
    //, where i = appeals and N = init_nivster_count
    let appeals = 1;
    let cut = nivsters_take(
        dispute_fee, 
        treasury_share, 
        appeals, 
        init_nivster_count
    );

    assert!(cut == 29_450_000_000);

    let appeals = 2;
    let cut = nivsters_take(
        dispute_fee, 
        treasury_share, 
        appeals, 
        init_nivster_count
    );

    assert!(cut == 70_300_000_000);

    let dispute_fee = 9_999_999_997;
    let treasury_share = 25;
    let appeals = 0;
    let init_nivster_count = 3;

    let cut = nivsters_take(
        dispute_fee, 
        treasury_share, 
        appeals, 
        init_nivster_count
    );

    assert!(cut == 7_499_999_998);

    let appeals = 1;
    let cut = nivsters_take(
        dispute_fee, 
        treasury_share, 
        appeals, 
        init_nivster_count
    );

    assert!(cut == 24_999_999_993);
}