use crate::db::AppState;
use crate::error::ApiError;
use crate::utils::get_from_etcd;
use axum::{
    extract::{Path, State},
    routing::get,
    Json, Router,
};
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub struct VirtualHost {
    pub name: String,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub realm: Option<String>,
    pub subdomain: String,
    pub routing_chain: String,
    #[serde(default)]
    pub certificate: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub key: Option<String>,
    #[serde(default)]
    pub disabled: bool,
}

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(list_virtual_hosts).post(add_virtual_host).put(update_virtual_host))
        .route(
            "/{virtual_host_name}",
            get(get_virtual_host).delete(delete_virtual_host),
        )
}

fn virtual_host_key(realm: &str, name: &str) -> String {
    format!("/realms/{}/virtual-hosts/{}", realm, name)
}

fn virtual_host_prefix(realm: &str) -> String {
    format!("/realms/{}/virtual-hosts/", realm)
}

async fn list_virtual_hosts(
    State(state): State<AppState>,
    Path(realm): Path<String>,
) -> Result<Json<Vec<VirtualHost>>, ApiError> {
    let mut client = state.etcd_client.clone();
    let prefix = virtual_host_prefix(&realm);
    let resp = client.get(prefix, Some(etcd_client::GetOptions::new().with_prefix())).await?;
    let hosts = resp
        .kvs()
        .iter()
        .filter_map(|kv| serde_json::from_slice(kv.value()).ok())
        .collect();
    Ok(Json(hosts))
}

async fn add_virtual_host(
    State(state): State<AppState>,
    Path(realm): Path<String>,
    Json(mut host): Json<VirtualHost>,
) -> Result<Json<VirtualHost>, ApiError> {
    let mut client = state.etcd_client.clone();
    let key = virtual_host_key(&realm, &host.name);

    if get_from_etcd(&state, &key).await?.kvs().first().is_some() {
        return Err(ApiError::Conflict(format!(
            "VirtualHost '{}' already exists in realm '{}'.",
            host.name, realm
        )));
    }
    
    host.certificate = Vec::new(); // Ensure certificate field is present, even if empty
    host.realm = Some(realm);
    let value = serde_json::to_vec(&host)?;
    client.put(key, value, None).await?;
    Ok(Json(host))
}

async fn update_virtual_host(
    State(state): State<AppState>,
    Path(realm): Path<String>,
    Json(mut host): Json<VirtualHost>,
) -> Result<Json<VirtualHost>, ApiError> {
    let mut client = state.etcd_client.clone();
    let key = virtual_host_key(&realm, &host.name);
    host.realm = Some(realm);
    let value = serde_json::to_vec(&host)?;
    client.put(key, value, None).await?;
    Ok(Json(host))
}

async fn get_virtual_host(
    State(state): State<AppState>,
    Path((realm, name)): Path<(String, String)>,
) -> Result<Json<VirtualHost>, ApiError> {
    let key = virtual_host_key(&realm, &name);
    if let Some(kv) = get_from_etcd(&state, &key).await?.kvs().first() {
        let host = serde_json::from_slice(kv.value())?;
        Ok(Json(host))
    } else {
        Err(ApiError::NotFound(format!(
            "VirtualHost '{}' not found in realm '{}'", name, realm
        )))
    }
}

async fn delete_virtual_host(
    State(state): State<AppState>,
    Path((realm, name)): Path<(String, String)>,
) -> Result<Json<VirtualHost>, ApiError> {
    let mut client = state.etcd_client.clone();
    let key = virtual_host_key(&realm, &name);
    let opts = etcd_client::DeleteOptions::new().with_prev_key();
    let resp = client.delete(key, Some(opts)).await?;

    if let Some(kv) = resp.prev_kvs().first() {
        let host = serde_json::from_slice(kv.value())?;
        Ok(Json(host))
    } else {
        Err(ApiError::NotFound(format!(
            "VirtualHost '{}' not found in realm '{}'", name, realm
        )))
    }
}