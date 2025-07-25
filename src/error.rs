use axum::{
  http::StatusCode,
    response::{Response, IntoResponse}, 
    Json,
};
use serde_json::json;

pub enum ApiError {
    NotFound(String),
    Conflict(String), 
    BadRequest(String),
    Internal(anyhow::Error),
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, error_message) = match self {
            ApiError::NotFound(msg) => (StatusCode::NOT_FOUND, msg),
            ApiError::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg),
            ApiError::Conflict(msg) => (StatusCode::CONFLICT, msg),
            ApiError::Internal(err) => {
                tracing::error!("Internal server error: {:?}", err);
                (StatusCode::INTERNAL_SERVER_ERROR, "Internal server error".to_string())
            }
        };

        (status, Json(json!({ "code": status.as_u16().to_string(), "message": error_message }))).into_response()
    }
}

impl From<etcd_client::Error> for ApiError {
    fn from(err: etcd_client::Error) -> Self {
        ApiError::Internal(err.into())
    }
}

impl From<serde_json::Error> for ApiError {
    fn from(err: serde_json::Error) -> Self {
        ApiError::Internal(err.into())
    }
}