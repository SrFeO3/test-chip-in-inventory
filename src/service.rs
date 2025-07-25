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
pub struct Service {
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hub: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub urn: Option<String>,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub realm: String,
    pub hub_name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub availability_management: Option<AvailabilityManagement>,
    pub providers: Vec<String>,
    pub consumers: Vec<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub struct AvailabilityManagement {
    pub cluster_manager_urn: String,
    pub service_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub start_at: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stop_at: Option<String>,
    #[serde(default)]
    pub ondemand_start: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub idel_timeout: Option<i32>,
}

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(list_services).post(add_service).put(update_service))
        .route("/{service_name}", get(get_service).delete(delete_service))
}

fn service_key(realm: &str, hub: &str, name: &str) -> String {
    format!("/realms/{}/hubs/{}/services/{}", realm, hub, name)
}

fn service_prefix(realm: &str, hub: &str) -> String {
    format!("/realms/{}/hubs/{}/services/", realm, hub)
}

async fn list_services(
    State(state): State<AppState>,
    Path((realm, hub_name)): Path<(String, String)>,
) -> Result<Json<Vec<Service>>, ApiError> {
    let mut client = state.etcd_client.clone();
    let prefix = service_prefix(&realm, &hub_name);
    let resp = client.get(prefix, Some(etcd_client::GetOptions::new().with_prefix())).await?;
    let services = resp
        .kvs()
        .iter()
        .filter_map(|kv| serde_json::from_slice(kv.value()).ok())
        .collect();
    Ok(Json(services))
}

async fn add_service(
    State(state): State<AppState>,
    Path((realm, hub_name)): Path<(String, String)>,
    Json(mut service): Json<Service>,
) -> Result<Json<Service>, ApiError> {
    let mut client = state.etcd_client.clone();
    let key = service_key(&realm, &hub_name, &service.name);

    if get_from_etcd(&state, &key).await?.kvs().first().is_some() {
        return Err(ApiError::Conflict(format!("Service '{}' already exists in hub '{}'.", service.name, hub_name)));
    }
    
    service.realm = realm.clone();
    service.hub_name = hub_name.clone();
    service.hub = Some(format!("urn:chip-in:hub:{}:{}", realm, hub_name));
    service.urn = Some(format!("urn:chip-in:service:{}:{}:{}", realm, hub_name, service.name));

    let value = serde_json::to_vec(&service)?;
    client.put(key, value, None).await?;
    Ok(Json(service))
}

async fn update_service(
    State(state): State<AppState>,
    Path((realm, hub_name)): Path<(String, String)>,
    Json(mut service): Json<Service>,
) -> Result<Json<Service>, ApiError> {
    let mut client = state.etcd_client.clone();
    let key = service_key(&realm, &hub_name, &service.name);

    service.realm = realm.clone();
    service.hub_name = hub_name.clone();
    service.hub = Some(format!("urn:chip-in:hub:{}:{}", realm, hub_name));
    service.urn = Some(format!("urn:chip-in:service:{}:{}:{}", realm, hub_name, service.name));

    let value = serde_json::to_vec(&service)?;
    client.put(key, value, None).await?;
    Ok(Json(service))
}

async fn get_service(State(state): State<AppState>, Path((realm, hub_name, name)): Path<(String, String, String)>) -> Result<Json<Service>, ApiError> {
    let key = service_key(&realm, &hub_name, &name);
    if let Some(kv) = get_from_etcd(&state, &key).await?.kvs().first() {
        let service = serde_json::from_slice(kv.value())?;
        Ok(Json(service))
    } else {
        Err(ApiError::NotFound(format!("Service '{}' not found in hub '{}'", name, hub_name)))
    }
}

async fn delete_service(State(state): State<AppState>, Path((realm, hub_name, name)): Path<(String, String, String)>) -> Result<Json<Service>, ApiError> {
    let mut client = state.etcd_client.clone();
    let key = service_key(&realm, &hub_name, &name);
    let opts = etcd_client::DeleteOptions::new().with_prev_key();
    let resp = client.delete(key, Some(opts)).await?;
    if let Some(kv) = resp.prev_kvs().first() {
        let service = serde_json::from_slice(kv.value())?;
        Ok(Json(service))
    } else {
        Err(ApiError::NotFound(format!("Service '{}' not found in hub '{}'", name, hub_name)))
    }
}