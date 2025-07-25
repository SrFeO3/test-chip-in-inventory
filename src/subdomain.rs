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
pub struct Subdomain {
    pub name: String,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fqdn: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub zone: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub destination_realm: Option<String>,
    #[serde(default)]
    pub share_cookie: bool,
}

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(list_subdomains).post(add_subdomain).put(update_subdomain))
        .route("/{subdomain_name}", get(get_subdomain).delete(delete_subdomain))
}

fn subdomain_key(realm: &str, zone: &str, name: &str) -> String {
    format!("/realms/{}/zones/{}/subdomains/{}", realm, zone, name)
}

fn subdomain_prefix(realm: &str, zone: &str) -> String {
    format!("/realms/{}/zones/{}/subdomains/", realm, zone)
}

async fn list_subdomains(
    State(state): State<AppState>,
    Path((realm, zone_name)): Path<(String, String)>,
) -> Result<Json<Vec<Subdomain>>, ApiError> {
    let mut client = state.etcd_client.clone();
    let prefix = subdomain_prefix(&realm, &zone_name);
    let resp = client.get(prefix, Some(etcd_client::GetOptions::new().with_prefix())).await?;
    let subdomains = resp
        .kvs()
        .iter()
        .filter_map(|kv| serde_json::from_slice(kv.value()).ok())
        .collect();
    Ok(Json(subdomains))
}

async fn add_subdomain(
    State(state): State<AppState>,
    Path((realm, zone_name)): Path<(String, String)>,
    Json(mut subdomain): Json<Subdomain>,
) -> Result<Json<Subdomain>, ApiError> {
    let mut client = state.etcd_client.clone();
    let key = subdomain_key(&realm, &zone_name, &subdomain.name);

    if get_from_etcd(&state, &key).await?.kvs().first().is_some() {
        return Err(ApiError::Conflict(format!(
            "Subdomain '{}' already exists in zone '{}'.",
            subdomain.name, zone_name
        )));
    }
    
    subdomain.zone = Some(format!("urn:chip-in:zone:{}:{}", realm, zone_name));
    subdomain.fqdn = Some(if subdomain.name == "@" { zone_name.clone() } else { format!("{}.{}", subdomain.name, zone_name) });
    
    let value = serde_json::to_vec(&subdomain)?;
    client.put(key, value, None).await?;
    Ok(Json(subdomain))
}

async fn update_subdomain(
    State(state): State<AppState>,
    Path((realm, zone_name)): Path<(String, String)>,
    Json(mut subdomain): Json<Subdomain>,
) -> Result<Json<Subdomain>, ApiError> {
    let mut client = state.etcd_client.clone();
    let key = subdomain_key(&realm, &zone_name, &subdomain.name);

    subdomain.zone = Some(format!("urn:chip-in:zone:{}:{}", realm, zone_name));
    subdomain.fqdn = Some(if subdomain.name == "@" { zone_name.clone() } else { format!("{}.{}", subdomain.name, zone_name) });

    let value = serde_json::to_vec(&subdomain)?;
    client.put(key, value, None).await?;
    Ok(Json(subdomain))
}

async fn get_subdomain(
    State(state): State<AppState>,
    Path((realm, zone_name, subdomain_name)): Path<(String, String, String)>,
) -> Result<Json<Subdomain>, ApiError> {
    let key = subdomain_key(&realm, &zone_name, &subdomain_name);
    if let Some(kv) = get_from_etcd(&state, &key).await?.kvs().first() {
        let subdomain = serde_json::from_slice(kv.value())?;
        Ok(Json(subdomain))
    } else {
        Err(ApiError::NotFound(format!(
            "Subdomain '{}' not found in zone '{}'", subdomain_name, zone_name
        )))
    }
}

async fn delete_subdomain(
    State(state): State<AppState>,
    Path((realm, zone_name, subdomain_name)): Path<(String, String, String)>,
) -> Result<Json<Subdomain>, ApiError> {
    let mut client = state.etcd_client.clone();
    let key = subdomain_key(&realm, &zone_name, &subdomain_name);
    let opts = etcd_client::DeleteOptions::new().with_prev_key();
    let resp = client.delete(key, Some(opts)).await?;

    if let Some(kv) = resp.prev_kvs().first() {
        let subdomain = serde_json::from_slice(kv.value())?;
        Ok(Json(subdomain))
    } else {
        Err(ApiError::NotFound(format!(
            "Subdomain '{}' not found in zone '{}'", subdomain_name, zone_name
        )))
    }
}