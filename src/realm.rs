use crate::db::{AppState, REALM_PREFIX};
use crate::error::ApiError;
use crate::utils::get_from_etcd;
use axum::{
    extract::{Path, State},
    routing::get,
    Json, Router,
};
use serde::{Deserialize, Serialize};
/// Realm データモデル (OpenAPI仕様に基づく)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub struct Realm {
    pub name: String,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub cacert: String,
    pub signing_key: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session_timeout: Option<i64>,
    #[serde(default)]
    pub administrators: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expired_at: Option<String>,
    pub disabled: bool,
}

/// Realm関連のエンドポイントをまとめたルーターを返す
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(list_realms).post(add_realm).put(update_realm))
        .route("/{realm}", get(get_realm).delete(delete_realm))
}

fn realm_key(name: &str) -> String {
    format!("{}{}", REALM_PREFIX, name)
}

/// GET /realms
async fn list_realms(State(state): State<AppState>) -> Result<Json<Vec<Realm>>, ApiError> {
    let mut client = state.etcd_client.clone();
    let resp = client.get(REALM_PREFIX, Some(etcd_client::GetOptions::new().with_prefix())).await?;
    let realms = resp
        .kvs()
        .iter()
        .filter_map(|kv| serde_json::from_slice(kv.value()).ok())
        .collect();
    Ok(Json(realms))
}

/// POST /realms
async fn add_realm(
    State(state): State<AppState>,
    Json(realm): Json<Realm>,
) -> Result<Json<Realm>, ApiError> {
    let mut client = state.etcd_client.clone();
    let key = realm_key(&realm.name).clone();

    if get_from_etcd(&state, &key).await?.kvs().first().is_some() {
        return Err(ApiError::Conflict(format!("Realm '{}' already exists.", realm.name)))

    }

    let value = serde_json::to_vec(&realm)?;
    client.put(key, value, None).await?;
    Ok(Json(realm))
}

/// PUT /realms
async fn update_realm(
    State(state): State<AppState>,
    Json(realm): Json<Realm>,
) -> Result<Json<Realm>, ApiError> {
    let key = realm_key(&realm.name);
    let value = serde_json::to_vec(&realm)?;    let mut client = state.etcd_client.clone();


    client.put(key, value, None).await?;
    Ok(Json(realm))
}

/// GET /realms/{realm}
async fn get_realm(
    State(state): State<AppState>,
    Path(name): Path<String>,
) -> Result<Json<Realm>, ApiError> {
    let key = realm_key(&name);
    let resp = get_from_etcd(&state, &key).await?;

    if let Some(kv) = resp.kvs().first() {
        let realm = serde_json::from_slice(kv.value())?;
        
        Ok(Json(realm))
    } else {
        Err(ApiError::NotFound(format!("Realm '{}' not found.", name)))
    }
}

/// DELETE /realms/{realm}
async fn delete_realm(
    State(state): State<AppState>,
    Path(name): Path<String>,
) -> Result<Json<Realm>, ApiError> {
    let mut client = state.etcd_client.clone();
    let key = realm_key(&name);

    // 削除する前に値を取得するために GetOptions を使うこともできますが、
    // トランザクション不使用の要件とシンプルさから、delete操作にprev_kvを要求します。
    let opts = etcd_client::DeleteOptions::new().with_prev_key();
    let resp = client.delete(key, Some(opts)).await?;

    if let Some(kv) = resp.prev_kvs().first() {
        let realm = serde_json::from_slice(kv.value())?;
        Ok(Json(realm))
    } else {
        Err(ApiError::NotFound(format!("Realm '{}' not found.", name)))
    }
}