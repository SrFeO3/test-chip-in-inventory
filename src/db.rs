use etcd_client::Client;

pub const REALM_PREFIX: &str = "/realms/";

#[derive(Clone)]
pub struct AppState {
    pub etcd_client: Client,
}