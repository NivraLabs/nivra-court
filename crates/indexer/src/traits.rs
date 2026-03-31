use serde::Serialize;
use sui_sdk_types::{Address, Identifier, StructTag, TypeTag};
use move_core_types::{account_address::AccountAddress, language_storage::StructTag as CoreStructTag};

use crate::{ModuleType, NivraEnv, get_module_type};


pub trait MoveStruct: Serialize {
    const MODULE: &'static str;
    const NAME: &'static str;
    const TYPE_PARAMS: &'static [&'static str] = &[];

    fn acceptable_package_addresses(env: NivraEnv) -> Result<Vec<Address>, String> {
        get_package_addresses_for_module(Self::MODULE, env)
    }

    fn matches_event_type(
        event_type: &CoreStructTag,
        env: NivraEnv,
    ) -> bool {
        let all_struct_types = Self::get_all_struct_types(env);

        all_struct_types.iter().any(|struct_type| {
            event_type.address == AccountAddress::new(*struct_type.address().inner())
                && event_type.module.as_str() == struct_type.module().as_str()
                && event_type.name.as_str() == struct_type.name().as_str()
        })
    }

    fn get_all_struct_types(env: NivraEnv) -> Vec<StructTag> {
        let acceptable_addresses = match Self::acceptable_package_addresses(env) {
            Ok(addresses) => addresses,
            Err(_) => return Vec::new(),
        };

        acceptable_addresses
            .into_iter()
            .map(|address| StructTag::new(
                address,
                Identifier::from_static(Self::MODULE),
                Identifier::from_static(Self::NAME),
                Self::TYPE_PARAMS
                    .iter()
                    .map(|param| TypeTag::from(StructTag::new(
                        address, 
                        Identifier::from_static(Self::MODULE), 
                        Identifier::from_static(param), 
                        vec![],
                    )))
                    .collect()
            ))
            .collect()
    }
}

pub fn get_package_addresses_for_module(
    module: &str,
    env: crate::NivraEnv,
) -> Result<Vec<Address>, String> {
    match get_module_type(module) {
        ModuleType::Nivra => {
            let addresses = env
                .get_nivra_package_addresses()
                .into_iter()
                .map(|addr| Address::from_static(addr))
                .collect();

            Ok(addresses)
        },
        ModuleType::Unknown => {
            Err(format!("Unknown module: {}", module))
        },
    }
}