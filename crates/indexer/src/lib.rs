use std::str::FromStr;

use move_core_types::account_address::AccountAddress;
use url::Url;

pub(crate) mod models;
pub(crate) mod notifications;
pub mod traits;
pub mod handlers;

pub const MAINNET_REMOTE_STORE_URL: &str = "https://checkpoints.mainnet.sui.io";
pub const TESTNET_REMOTE_STORE_URL: &str = "https://checkpoints.testnet.sui.io";

const MAINNET_PACKAGES: &[&str] = &[

];

const TESTNET_PACKAGES: &[&str] = &[
    "0x3df5ba5787ae8195bdf03ec909398a0bd346c5f2bcbd7477c0416d75ef79f83d",
];

pub const NIVRA_MODULES: &[&str] = &[
    "registry",
    "court",
    "dispute",
    "evidence",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ModuleType {
    Nivra,
    Unknown,
}

pub fn is_nivra_module(module: &str) -> bool {
    NIVRA_MODULES.contains(&module)
}

pub fn get_module_type(module: &str) -> ModuleType {
    if is_nivra_module(module) {
        ModuleType::Nivra
    } else {
        ModuleType::Unknown
    }
}

#[derive(Debug, Clone, Copy, clap::ValueEnum)]
pub enum NivraEnv {
    Mainnet,
    Testnet,
}

impl NivraEnv {
    pub fn remote_store_url(&self) -> Url {
        let url = match self {
            NivraEnv::Mainnet => MAINNET_REMOTE_STORE_URL,
            NivraEnv::Testnet => TESTNET_REMOTE_STORE_URL,
        };
        Url::parse(url).unwrap()
    }

    pub fn get_nivra_package_addresses(&self) -> &'static [&'static str] {
        match self {
            NivraEnv::Mainnet => MAINNET_PACKAGES,
            NivraEnv::Testnet => TESTNET_PACKAGES,
        }
    }

    pub fn package_addresses(&self) -> Vec<AccountAddress> {
        self.get_nivra_package_addresses()
            .iter()
            .map(|pkg| AccountAddress::from_str(pkg).unwrap())
            .collect()
    }
}