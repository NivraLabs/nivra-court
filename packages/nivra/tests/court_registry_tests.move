#[test_only]
module nivra::court_registry_tests;

use nivra::court_registry::init_for_testing;
use sui::test_scenario;
use nivra::court_registry::NivraAdminCap;
use nivra::court_registry::CourtRegistry;
use nivra::constants::current_version;
use nivra::court_registry::get_root_privileges_for_testing;
use nivra::court_registry::create_metadata;

#[test]
fun test_init() {
    let alice = @0xA;
    let mut scenario = test_scenario::begin(alice);
    {
        init_for_testing(scenario.ctx());
    };
    scenario.next_tx(alice);
    {
        let admin_cap = scenario.take_from_sender<NivraAdminCap>();
        let court_registry = scenario.take_shared<CourtRegistry>();

        let cur_ver = current_version();
        let cap_id = object::id(&admin_cap);
        let root = 1;

        assert!(court_registry.allowed_versions().contains(&cur_ver));
        assert!(court_registry.admin_whitelist().contains(&cap_id));
        assert!(court_registry.admin_whitelist().get(&cap_id) == root);
        assert!(court_registry.treasury_address() == alice);

        admin_cap.destroy_admin_cap_for_testing();
        court_registry.destroy_court_registry_for_testing();
    };
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = 3, location = nivra::court_registry)]
fun test_validate_admin_privileges() {
    let alice = @0xA;

    let mut scenario = test_scenario::begin(alice);
    let (mut cr, rac) = {
        let (mut court_registry, root_admin_cap) = 
            get_root_privileges_for_testing(scenario.ctx());
            
        court_registry.mint_admin_cap(
            &root_admin_cap, 
            alice, 
            scenario.ctx()
        );

        (court_registry, root_admin_cap)
    };
    scenario.next_tx(alice);
    let ac = {
        let admin_cap = scenario.take_from_sender<NivraAdminCap>();
        let root = cr.validate_admin_privileges(&rac);
        let admin = cr.validate_admin_privileges(&admin_cap);

        assert!(root == 1 && admin == 2);

        cr.blacklist_admin_cap(&rac, object::id(&admin_cap));
        cr.validate_admin_privileges(&admin_cap);

        admin_cap
    };

    rac.destroy_admin_cap_for_testing();
    ac.destroy_admin_cap_for_testing();
    cr.destroy_court_registry_for_testing();

    test_scenario::end(scenario);
}

#[test]
fun test_mint_admin_cap() {
    let alice = @0xA;

    let mut scenario = test_scenario::begin(alice);
    let (cr, rac) = {
        let (mut court_registry, root_admin_cap) = 
            get_root_privileges_for_testing(scenario.ctx());
            
        court_registry.mint_admin_cap(
            &root_admin_cap, 
            alice, 
            scenario.ctx()
        );

        (court_registry, root_admin_cap)
    };
    scenario.next_tx(alice);
    let ac = {
        let admin_cap = scenario.take_from_sender<NivraAdminCap>();

        assert!(cr.admin_whitelist().contains(&object::id(&admin_cap)));
        assert!(cr.admin_whitelist().get(&object::id(&admin_cap)) == 2);

        admin_cap
    };

    rac.destroy_admin_cap_for_testing();
    ac.destroy_admin_cap_for_testing();
    cr.destroy_court_registry_for_testing();

    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = 7, location = nivra::court_registry)]
fun test_mint_admin_cap_max() {
    let alice = @0xA;

    let mut scenario = test_scenario::begin(alice);
    let (cr, rac) = {
        let (mut court_registry, root_admin_cap) = 
            get_root_privileges_for_testing(scenario.ctx());

        let mut i = 0u64;

        while (i <= 100u64) {
            court_registry.mint_admin_cap(
                &root_admin_cap, 
                alice, 
                scenario.ctx()
            );

            i = i + 1;
        };

        (court_registry, root_admin_cap)
    };

    rac.destroy_admin_cap_for_testing();
    cr.destroy_court_registry_for_testing();

    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = 6, location = nivra::court_registry)]
fun test_blacklist_admin_cap() {
    let alice = @0xA;

    let mut scenario = test_scenario::begin(alice);
    let (mut cr, rac) = {
        let (mut court_registry, root_admin_cap) = 
            get_root_privileges_for_testing(scenario.ctx());
            
        court_registry.mint_admin_cap(
            &root_admin_cap, 
            alice, 
            scenario.ctx()
        );

        (court_registry, root_admin_cap)
    };
    scenario.next_tx(alice);
    let ac = {
        let admin_cap = scenario.take_from_sender<NivraAdminCap>();

        // Blacklist the created admin cap
        cr.blacklist_admin_cap(&rac, object::id(&admin_cap));
        
        assert!(!cr.admin_whitelist().contains(&object::id(&admin_cap)));

        // Attempt to blacklist the root admin cap
        cr.blacklist_admin_cap(&rac, object::id(&rac));

        admin_cap
    };

    rac.destroy_admin_cap_for_testing();
    ac.destroy_admin_cap_for_testing();
    cr.destroy_court_registry_for_testing();

    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = 6, location = nivra::court_registry)]
fun test_purge_admin_caps() {
    let alice = @0xA;
    let bob = @0xB;
    let charlie = @0xC;

    let mut scenario = test_scenario::begin(alice);
    {
        let (mut court_registry, root_admin_cap) = 
            get_root_privileges_for_testing(scenario.ctx());

        court_registry.mint_admin_cap(
            &root_admin_cap, 
            bob, 
            scenario.ctx()
        );

        court_registry.mint_admin_cap(
            &root_admin_cap, 
            charlie, 
            scenario.ctx()
        );

        assert!(court_registry.admin_whitelist().length() == 3);

        court_registry.purge_admin_caps(&root_admin_cap, 2);

        assert!(court_registry.admin_whitelist().length() == 3);

        court_registry.purge_admin_caps(&root_admin_cap, 1);

        assert!(court_registry.admin_whitelist().length() == 1);
        assert!(court_registry.admin_whitelist().contains(&object::id(&root_admin_cap)));

        // Attempt to purge admin cap
        court_registry.purge_admin_caps(&root_admin_cap, 0);

        root_admin_cap.destroy_admin_cap_for_testing();
        court_registry.destroy_court_registry_for_testing();
    };
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = 6, location = nivra::court_registry)]
fun test_set_tresury_address() {
    let alice = @0xA;
    let bob = @0xB;

    let mut scenario = test_scenario::begin(alice);
    let (mut cr, rac) = {
        let (mut court_registry, root_admin_cap) = 
            get_root_privileges_for_testing(scenario.ctx());

        // Set treasury address with the root cap
        court_registry.set_treasury_address(&root_admin_cap, bob);

        assert!(court_registry.treasury_address() == bob);

        court_registry.mint_admin_cap(
            &root_admin_cap, 
            bob, 
            scenario.ctx()
        );

        (court_registry, root_admin_cap)
    };
    scenario.next_tx(bob); 
    let ac = {
        let admin_cap = scenario.take_from_sender<NivraAdminCap>();

        // Attempt to set treasury address with non-root cap
        cr.set_treasury_address(&admin_cap, alice);

        admin_cap
    };
    ac.destroy_admin_cap_for_testing();
    rac.destroy_admin_cap_for_testing();
    cr.destroy_court_registry_for_testing();
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = 2, location = nivra::court_registry)]
fun test_enable_version() {
    let alice = @0xA;

    let mut scenario = test_scenario::begin(alice);
    {
        let (mut court_registry, root_admin_cap) = 
            get_root_privileges_for_testing(scenario.ctx());
        
        let cur_ver = current_version();
        
        court_registry.enable_version(&root_admin_cap, cur_ver + 1);

        // attempt to enable the same version
        court_registry.enable_version(&root_admin_cap, cur_ver + 1);

        court_registry.destroy_court_registry_for_testing();
        root_admin_cap.destroy_admin_cap_for_testing();
    };
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = 4, location = nivra::court_registry)]
fun test_disable_version() {
    let alice = @0xA;

    let mut scenario = test_scenario::begin(alice);
    {
        let (mut court_registry, root_admin_cap) = 
            get_root_privileges_for_testing(scenario.ctx());
        
        let cur_ver = current_version();
        
        court_registry.enable_version(&root_admin_cap, cur_ver + 1);
        court_registry.disable_version(&root_admin_cap, cur_ver + 1);

        // Attempt to disable the current version
        court_registry.disable_version(&root_admin_cap, cur_ver);

        court_registry.destroy_court_registry_for_testing();
        root_admin_cap.destroy_admin_cap_for_testing();
    };
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = 5, location = nivra::court_registry)]
fun test_disable_unexisting_version() {
    let alice = @0xA;

    let mut scenario = test_scenario::begin(alice);
    {
        let (mut court_registry, root_admin_cap) = 
            get_root_privileges_for_testing(scenario.ctx());

        court_registry.disable_version(&root_admin_cap, 0);

        court_registry.destroy_court_registry_for_testing();
        root_admin_cap.destroy_admin_cap_for_testing();
    };
    test_scenario::end(scenario);
}

#[test]
fun test_registeration_and_metadata() {
    let alice = @0xA;

    let mut scenario = test_scenario::begin(alice);
    {
        let (mut court_registry, root_admin_cap) = 
            get_root_privileges_for_testing(scenario.ctx());
        
        let court_placeholder = object::new(scenario.ctx());
        let court_metadata = create_metadata(
            b"test".to_string(), 
            b"test".to_string(), 
            b"test".to_string(), 
            b"test".to_string()
        );
        
        court_registry.register_court(
            *court_placeholder.as_inner(), 
            court_metadata
        );

        court_registry.change_court_metadata(
            &root_admin_cap, 
            *court_placeholder.as_inner(), 
            b"test2".to_string(), 
            b"test2".to_string(),
            b"test2".to_string(), 
            b"test2".to_string(),
        );

        let md = court_registry.courts().borrow(*court_placeholder.as_inner());

        assert!(md.category() == b"test2".to_string());
        assert!(md.name() == b"test2".to_string());
        assert!(md.description() == b"test2".to_string());
        assert!(md.skills() == b"test2".to_string());

        court_registry.unregister_court(*court_placeholder.as_inner());

        assert!(court_registry.courts().length() == 0);

        court_registry.destroy_court_registry_for_testing();
        root_admin_cap.destroy_admin_cap_for_testing();
        court_placeholder.delete();
    };
    test_scenario::end(scenario);
}