#!/bin/bash

# ref/master.yaml のデータをAPIサーバーに投入するスクリプト
#
# 依存関係:
# - curl: HTTPリクエスト用
# - jq: JSONのパース用
# - yq: YAMLのパース用 (kislyuk/yq, `apt install yq` でインストールされるPythonラッパー版)
# - envsubst: 環境変数の置換用 (gettextパッケージに含まれることが多い)
#
# Debian/Ubuntuでのインストール例:
#   sudo apt-get install -y curl jq yq gettext
#
# 実行前の準備:
# 以下の環境変数を設定してください。
# - MASTER_CA_CERT: MasterレルムのCA証明書
# - MASTER_REALM_SIGNING_KEY: Masterレルムの署名キー
# - DEFAULT_ZONE_DOMAIN: デフォルトで使用するドメイン名
# - MASTER_HUB_SERVER_CERT: Masterハブのサーバー証明書
# - MASTER_HUB_SERVER_CERT_KEY: Masterハブのサーバー証明書のキー
# - API_TOKEN: (任意) APIサーバーの認証用Bearerトークン

# --- スクリプト設定 ---
set -e
set -o pipefail

# --- ヘルパー関数と変数 ---
API_BASE_URL="${API_BASE_URL:-http://127.0.0.1:8080}"
YAML_FILE="src/ref/master.yaml"

# ログ出力用の関数
step() { echo -e "\n\e[1;34m>>> $1\e[0m"; }
ok() { echo -e "\e[32mOK: $1\e[0m"; }
info() { echo -e "\e[36mINFO: $1\e[0m"; }
fail() { echo -e "\e[1;31mFAIL: $1\e[0m"; exit 1; }

# コマンドの存在チェック
check_command() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &> /dev/null; then
            fail "コマンドが見つかりません: $cmd. このスクリプトの実行には $cmd が必要です。"
        fi
    done
}

# 環境変数の存在チェック
check_env_vars() {
    for var in "$@"; do
        if [ -z "${!var}" ]; then
            fail "環境変数が設定されていません: $var. このスクリプトを実行する前に設定してください。"
        fi
    done
}

# APIリクエストを送信する関数
# $1: HTTP Method (e.g., POST, PUT)
# $2: API Path (e.g., /realms)
# $3: JSON Body
api_request() {
    local method="$1"
    local path="$2"
    local body="$3"
    local url="${API_BASE_URL}${path}"
    local headers=(-H "Content-Type: application/json")

    if [ -n "$API_TOKEN" ]; then
        headers+=(-H "Authorization: Bearer ${API_TOKEN}")
    fi

    info "Sending ${method} request to ${url}..."
    RESPONSE=$(curl -s -w "\n%{http_code}" -X "$method" "${headers[@]}" -d "$body" "$url")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
        ok "Request successful (HTTP ${HTTP_CODE})."
    elif [ "$HTTP_CODE" -eq 409 ]; then
        ok "Resource already exists (HTTP ${HTTP_CODE}). Skipping."
    else
        fail "API request failed (HTTP ${HTTP_CODE}). Path: ${path}\nBody: ${body}\nResponse: ${BODY}"
    fi
}

# --- メイン処理 ---
main() {
    step "1. 依存関係と環境変数のチェック"
    check_command curl jq yq envsubst
    check_env_vars MASTER_CA_CERT MASTER_REALM_SIGNING_KEY DEFAULT_ZONE_DOMAIN MASTER_HUB_SERVER_CERT MASTER_HUB_SERVER_CERT_KEY
    ok "すべての依存関係と環境変数が存在します。"

    step "2. YAMLファイルから環境変数を展開"
    # Pythonラッパー版のyq (kislyuk/yq) は、デフォルトでYAMLをJSONに変換して出力します。
    # Go言語版のyq (mikefarah/yq) を使用している場合は、この行を `... | yq -o=json '.' -` に変更してください。
    PROCESSED_YAML=$(envsubst < "$YAML_FILE" | yq . -)
    info "${YAML_FILE} を処理しました。"

    # 投入順序: 依存関係を考慮する
    # 1. Realm -> 2. Zone -> 5. Subdomain -> 7. VirtualHost
    #           -> 3. RoutingChain -> 7. VirtualHost
    #           -> 4. Hub -> 6. Service

    step "3. Realmの投入"
    REALM_JSON=$(echo "$PROCESSED_YAML" | jq -c '.realm')
    api_request POST "/realms" "$REALM_JSON"

    step "4. Zoneの投入"
    REALM_NAME=$(echo "$REALM_JSON" | jq -r '.name')
    echo "$PROCESSED_YAML" | jq -c '.zones[]' | while read -r zone; do
        api_request POST "/realms/${REALM_NAME}/zones" "$zone"
    done

    step "5. RoutingChainの投入"
    echo "$PROCESSED_YAML" | jq -c '.routingChains[]' | while read -r chain; do
        CHAIN_REALM_NAME=$(echo "$chain" | jq -r '.urn' | cut -d: -f4)
        api_request POST "/realms/${CHAIN_REALM_NAME}/routing-chains" "$chain"
    done

    step "6. Hubの投入"
    echo "$PROCESSED_YAML" | jq -c '.hubs[]' | while read -r hub; do
        HUB_REALM_NAME=$(echo "$hub" | jq -r '.urn' | cut -d: -f4)
        api_request POST "/realms/${HUB_REALM_NAME}/hubs" "$hub"
    done

    step "7. Subdomainの投入"
    echo "$PROCESSED_YAML" | jq -c '.subdomains[]' | while read -r subdomain; do
        ZONE_URN=$(echo "$subdomain" | jq -r '.zone')
        SUBDOMAIN_REALM_NAME=$(echo "$ZONE_URN" | cut -d: -f4)
        ZONE_NAME=$(echo "$ZONE_URN" | cut -d: -f5)
        api_request POST "/realms/${SUBDOMAIN_REALM_NAME}/zones/${ZONE_NAME}/subdomains" "$subdomain"
    done

    step "8. Serviceの投入"
    echo "$PROCESSED_YAML" | jq -c '.services[]' | while read -r service; do
        SERVICE_REALM_NAME=$(echo "$service" | jq -r '.realm' | cut -d: -f4)
        HUB_NAME=$(echo "$service" | jq -r '.hubName')
        api_request POST "/realms/${SERVICE_REALM_NAME}/hubs/${HUB_NAME}/services" "$service"
    done

    step "9. VirtualHostの投入"
    echo "$PROCESSED_YAML" | jq -c '.virtualHosts[]' | while read -r vhost; do
        SUBDOMAIN_URN=$(echo "$vhost" | jq -r '.subdomain')
        VHOST_REALM_NAME=$(echo "$SUBDOMAIN_URN" | cut -d: -f4)
        api_request POST "/realms/${VHOST_REALM_NAME}/virtual-hosts" "$vhost"
    done

    step "🎉 すべてのリソースの投入が完了しました。"
}

main "$@"