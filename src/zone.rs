use crate::db::AppState;
use crate::error::ApiError;
use crate::subdomain;
use crate::utils::get_from_etcd;
use axum::{
  extract::{Path, State},
    routing::get,
    Json, Router,
};
use serde::{Deserialize, Serialize};

/// Zone データモデル (OpenAPI仕様に基づく)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub struct Zone {
    pub zone: String,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    // This field is read-only in the spec and will be populated by the server in responses.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub realm: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dns_provider: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub acme_certificate_provider: Option<String>,
}

/// Zone関連のエンドポイントをまとめたルーターを返す
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(list_zones).post(add_zone))
        .route("/{zone}", get(get_zone).put(update_zone).delete(delete_zone)).nest("/{zone}/subdomains", subdomain::routes())
}

// etcdでのキー構造: /realms/{realm_name}/zones/{zone_name}
fn zone_key(realm: &str, zone: &str) -> String {
    format!("/realms/{}/zones/{}", realm, zone)
}

fn zone_prefix(realm: &str) -> String {
    format!("/realms/{}/zones/", realm)
}

/// GET /realms/{realm}/zones
async fn list_zones(
    State(state): State<AppState>,
    Path(realm): Path<String>,
) -> Result<Json<Vec<Zone>>, ApiError> {
    let mut client = state.etcd_client.clone();
    let prefix = zone_prefix(&realm);
    let resp = client.get(prefix, Some(etcd_client::GetOptions::new().with_prefix())).await?;
    let zones = resp
        .kvs()
        .iter()
        .filter_map(|kv| serde_json::from_slice(kv.value()).ok())
        .collect();
    Ok(Json(zones))
}

/// POST /realms/{realm}/zones
async fn add_zone(
    State(state): State<AppState>,
    Path(realm): Path<String>,
    Json(mut zone): Json<Zone>,
) -> Result<Json<Zone>, ApiError> {
    let mut client = state.etcd_client.clone();
    let key = zone_key(&realm, &zone.zone);

    if get_from_etcd(&state, &key).await?.kvs().first().is_some() {
        return Err(ApiError::Conflict(format!(
            "Zone '{}' in realm '{}' already exists.",

            zone.zone, realm
        )));
    }
    
    zone.realm = Some(format!("urn:chip-in:realm:{}", realm));

    let value = serde_json::to_vec(&zone)?;
    client.put(key, value, None).await?;

    Ok(Json(zone))
}

/// PUT /realms/{realm}/zones/{zone}
async fn update_zone(
    State(state): State<AppState>,
    Path((realm, zone_name)): Path<(String, String)>,
    Json(mut zone): Json<Zone>,
) -> Result<Json<Zone>, ApiError> {
    let mut client = state.etcd_client.clone();    let key = zone_key(&realm, &zone.zone);

    if zone.zone != zone_name {        return Err(ApiError::BadRequest(format!("Zone name in path ('{}') does not match name in body ('{}')", zone_name, zone.zone)));
    }
    zone.realm = Some(format!("urn:chip-in:realm:{}", realm));

    let value = serde_json::to_vec(&zone)?;
    client.put(key, value, None).await?;
    Ok(Json(zone))
}

/// GET /realms/{realm}/zones/{zone}
async fn get_zone(
    State(state): State<AppState>,
    Path((realm, zone_name)): Path<(String, String)>,
) -> Result<Json<Zone>, ApiError> {
   let key = zone_key(&realm, &zone_name);


    if let Some(kv) = get_from_etcd(&state, &key).await?.kvs().first() {
        let zone = serde_json::from_slice(kv.value())?;
        Ok(Json(zone))
    } else {
        Err(ApiError::NotFound(format!("Zone '{}' not found in realm '{}'", zone_name, realm)))
    }
}

/// DELETE /realms/{realm}/zones/{zone}
async fn delete_zone(
    State(state): State<AppState>,
    Path((realm, zone_name)): Path<(String, String)>,
) -> Result<Json<Zone>, ApiError> {
    let mut client = state.etcd_client.clone();    // Retrieve the zone details to ensure we have the correct zone name
    let zone = get_zone(State(state.clone()), Path((realm.clone(), zone_name.clone()))).await?;
    let key = zone_key(&realm, &zone.zone); // Use the zone name from the retrieved data
    let opts = etcd_client::DeleteOptions::new().with_prev_key();
    let resp = client.delete(key, Some(opts)).await?;

    if let Some(kv) = resp.prev_kvs().first() {
        let zone = serde_json::from_slice(kv.value())?;
        Ok(Json(zone))
    } else {
        Err(ApiError::NotFound(format!("Zone '{}' not found in realm '{}'", zone_name, realm)))
    }
}