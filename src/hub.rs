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
pub struct Hub {
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub realm: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub urn: Option<String>,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub fqdn: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub server_port: Option<i32>,
    pub server_cert: String,
    pub server_cert_key: String,
}

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(list_hubs).post(add_hub).put(update_hub))
        .route("/{hub_name}", get(get_hub).delete(delete_hub))
}

fn hub_key(realm: &str, name: &str) -> String {
    format!("/realms/{}/hubs/{}", realm, name)
}

fn hub_prefix(realm: &str) -> String {
    format!("/realms/{}/hubs/", realm)
}

async fn list_hubs(
    State(state): State<AppState>,
    Path(realm): Path<String>,
) -> Result<Json<Vec<Hub>>, ApiError> {
    let mut client = state.etcd_client.clone();
    let prefix = hub_prefix(&realm);
    let resp = client.get(prefix, Some(etcd_client::GetOptions::new().with_prefix())).await?;
    let hubs = resp
        .kvs()
        .iter()
        .filter_map(|kv| serde_json::from_slice(kv.value()).ok())
        .collect();
    Ok(Json(hubs))
}

async fn add_hub(
    State(state): State<AppState>,
    Path(realm): Path<String>,
    Json(mut hub): Json<Hub>,
) -> Result<Json<Hub>, ApiError> {
    let mut client = state.etcd_client.clone();
    let key = hub_key(&realm, &hub.name);

    if get_from_etcd(&state, &key).await?.kvs().first().is_some() {
        return Err(ApiError::Conflict(format!("Hub '{}' already exists in realm '{}'.", hub.name, realm)));
    }
    
    hub.realm = Some(realm.clone());
    hub.urn = Some(format!("urn:chip-in:hub:{}:{}", realm, hub.name));
    let value = serde_json::to_vec(&hub)?;
    client.put(key, value, None).await?;
    Ok(Json(hub))
}

async fn update_hub(
    State(state): State<AppState>,
    Path(realm): Path<String>,
    Json(mut hub): Json<Hub>,
) -> Result<Json<Hub>, ApiError> {
    let mut client = state.etcd_client.clone();
    let key = hub_key(&realm, &hub.name);
    hub.realm = Some(realm.clone());
    hub.urn = Some(format!("urn:chip-in:hub:{}:{}", realm, hub.name));
    let value = serde_json::to_vec(&hub)?;
    client.put(key, value, None).await?;
    Ok(Json(hub))
}

async fn get_hub(State(state): State<AppState>, Path((realm, name)): Path<(String, String)>) -> Result<Json<Hub>, ApiError> {
    let key = hub_key(&realm, &name);
    if let Some(kv) = get_from_etcd(&state, &key).await?.kvs().first() {
        let hub = serde_json::from_slice(kv.value())?;
        Ok(Json(hub))
    } else {
        Err(ApiError::NotFound(format!("Hub '{}' not found in realm '{}'", name, realm)))
    }
}

async fn delete_hub(State(state): State<AppState>, Path((realm, name)): Path<(String, String)>) -> Result<Json<Hub>, ApiError> {
    let mut client = state.etcd_client.clone();
    let key = hub_key(&realm, &name);
    let opts = etcd_client::DeleteOptions::new().with_prev_key();
    let resp = client.delete(key, Some(opts)).await?;
    if let Some(kv) = resp.prev_kvs().first() {
        let hub = serde_json::from_slice(kv.value())?;
        Ok(Json(hub))
    } else {
        Err(ApiError::NotFound(format!("Hub '{}' not found in realm '{}'", name, realm)))
    }
}