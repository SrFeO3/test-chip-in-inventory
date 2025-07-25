use crate::db::AppState;
use crate::error::ApiError;
use etcd_client::GetResponse;

pub async fn get_from_etcd(state: &AppState, key: &str) -> Result<GetResponse, ApiError> {
    let mut client = state.etcd_client.clone();
    let resp = client.get(key, None).await?;
    Ok(resp)
}