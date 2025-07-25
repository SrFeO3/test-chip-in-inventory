use crate::db::AppState;
use crate::error::ApiError;
use crate::utils::get_from_etcd;
use axum::{
    extract::{Path, State},
    routing::get,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub struct RoutingChain {
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub realm: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub urn: Option<String>,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub rules: Vec<Rule>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Rule {
    #[serde(rename = "match")]
    pub match_expr: String,
    pub action: Action,
}

/// Helper function for `serde` to skip serializing boolean fields that are false.
fn is_false(b: &bool) -> bool {
    !*b
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
#[serde(tag = "type")]
pub enum Action {
    Proxy(ProxyAction),
    Redirect(RedirectAction),
    Jump(JumpAction),
    SetVariables(SetVariablesAction),
    SetHeaders(SetHeadersAction),
    AccessLog(AccessLogAction),
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub struct ProxyAction {
    pub target: String,
    #[serde(default, skip_serializing_if = "is_false")]
    pub no_body: bool,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct RedirectAction {
    pub target: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct JumpAction {
    pub target: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct SetVariablesAction {
    pub variables: HashMap<String, String>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub struct SetHeadersAction {
    pub target: String,
    pub headers: HashMap<String, String>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub struct AccessLogAction {
    pub target: String,
    #[serde(default = "default_max_value_length")]
    pub max_value_length: i32,
    pub format: HashMap<String, String>,
}

fn default_max_value_length() -> i32 { 512 }

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(list_routing_chains).post(add_routing_chain).put(update_routing_chain))
        .route("/{routing_chain_name}", get(get_routing_chain).delete(delete_routing_chain))
}

fn routing_chain_key(realm: &str, name: &str) -> String {
    format!("/realms/{}/routing-chains/{}", realm, name)
}

fn routing_chain_prefix(realm: &str) -> String {
    format!("/realms/{}/routing-chains/", realm)
}

async fn list_routing_chains(
    State(state): State<AppState>,
    Path(realm): Path<String>,
) -> Result<Json<Vec<RoutingChain>>, ApiError> {
    let mut client = state.etcd_client.clone();
    let prefix = routing_chain_prefix(&realm);
    let resp = client.get(prefix, Some(etcd_client::GetOptions::new().with_prefix())).await?;
    let chains = resp
        .kvs()
        .iter()
        .filter_map(|kv| serde_json::from_slice(kv.value()).ok())
        .collect();
    Ok(Json(chains))
}

async fn add_routing_chain(
    State(state): State<AppState>,
    Path(realm): Path<String>,
    Json(mut chain): Json<RoutingChain>,
) -> Result<Json<RoutingChain>, ApiError> {
    let mut client = state.etcd_client.clone();
    let key = routing_chain_key(&realm, &chain.name);

    if get_from_etcd(&state, &key).await?.kvs().first().is_some() {
        return Err(ApiError::Conflict(format!("RoutingChain '{}' already exists in realm '{}'.", chain.name, realm)));
    }
    
    chain.realm = Some(realm.clone());
    chain.urn = Some(format!("urn:chip-in:routing-chain:{}:{}", realm, chain.name));
    let value = serde_json::to_vec(&chain)?;
    client.put(key, value, None).await?;
    Ok(Json(chain))
}

async fn update_routing_chain(
    State(state): State<AppState>,
    Path(realm): Path<String>,
    Json(mut chain): Json<RoutingChain>,
) -> Result<Json<RoutingChain>, ApiError> {
    let mut client = state.etcd_client.clone();
    let key = routing_chain_key(&realm, &chain.name);
    chain.realm = Some(realm.clone());
    chain.urn = Some(format!("urn:chip-in:routing-chain:{}:{}", realm, chain.name));
    let value = serde_json::to_vec(&chain)?;
    client.put(key, value, None).await?;
    Ok(Json(chain))
}

async fn get_routing_chain(State(state): State<AppState>, Path((realm, name)): Path<(String, String)>) -> Result<Json<RoutingChain>, ApiError> {
    let key = routing_chain_key(&realm, &name);
    if let Some(kv) = get_from_etcd(&state, &key).await?.kvs().first() {
        let chain = serde_json::from_slice(kv.value())?;
        Ok(Json(chain))
    } else {
        Err(ApiError::NotFound(format!("RoutingChain '{}' not found in realm '{}'", name, realm)))
    }
}

async fn delete_routing_chain(State(state): State<AppState>, Path((realm, name)): Path<(String, String)>) -> Result<Json<RoutingChain>, ApiError> {
    let mut client = state.etcd_client.clone();
    let key = routing_chain_key(&realm, &name);
    let opts = etcd_client::DeleteOptions::new().with_prev_key();
    let resp = client.delete(key, Some(opts)).await?;
    if let Some(kv) = resp.prev_kvs().first() {
        let chain = serde_json::from_slice(kv.value())?;
        Ok(Json(chain))
    } else {
        Err(ApiError::NotFound(format!("RoutingChain '{}' not found in realm '{}'", name, realm)))
    }
}