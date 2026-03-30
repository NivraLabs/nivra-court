use url::Url;


pub const MAINNET_REMOTE_STORE_URL: &str = "https://checkpoints.mainnet.sui.io";
pub const TESTNET_REMOTE_STORE_URL: &str = "https://checkpoints.testnet.sui.io";

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
}