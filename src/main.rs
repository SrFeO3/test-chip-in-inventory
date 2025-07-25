mod db;
mod error;
mod realm;
mod zone;
mod virtual_host;
mod subdomain;
mod routing_chain;
mod hub;
mod service;
mod utils;

use crate::db::AppState;
use axum::{
    response::{Html, IntoResponse},
    routing::get,
    Router,
};
use etcd_client::Client;
use std::env;
use std::net::SocketAddr;
use tracing::info;

/// Web UI (index.html, webui.html, webui2.html) を提供するハンドラ
async fn index_handler() -> impl IntoResponse {
    Html(include_str!("../webroot/index.html"))
}
async fn webui() -> impl IntoResponse {
    Html(include_str!("../webroot/webui.html"))
}
async fn webui2() -> impl IntoResponse {
    Html(include_str!("../webroot/webui2.html"))
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // ロギングの初期化
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    // etcdへの接続
    let etcd_endpoints = env::var("ETCD_ENDPOINTS").unwrap_or_else(|_| "http://127.0.0.1:2379".to_string());
    let etcd_client = Client::connect([etcd_endpoints], None).await?;
    info!("Connected to etcd");

    // アプリケーションの状態を生成
    let app_state = AppState { etcd_client };

    // ルーターの構築
    let app = Router::new()
        // Web UI
        .route("/", get(index_handler))
        .route("/index.html", get(index_handler))
        .route("/webui.html", get(webui))
        .route("/webui2.html", get(webui2))
        // API Server
        .nest("/realms", realm::routes()
            .nest("/{realm}/zones", zone::routes())
            .nest("/{realm}/virtual-hosts", virtual_host::routes())
            .nest("/{realm}/routing-chains", routing_chain::routes())
            .nest("/{realm}/hubs", hub::routes()
                .nest("/{hub_name}/services", service::routes())))
        .with_state(app_state);

    // サーバーの起動
    // 0.0.0.0 にバインドすることで、コンテナ外部からの接続を受け付けるようにする
    let addr = SocketAddr::from(([0, 0, 0, 0], 8080));
    info!("Listening on {}", addr);
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}