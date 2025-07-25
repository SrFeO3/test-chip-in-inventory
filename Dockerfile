# Stage 1: ビルダー
# Rustの公式イメージをビルド環境として使用します
FROM rust:1-bookworm as builder

# ビルドに必要な依存関係をインストールします
RUN apt-get update && apt-get install -y pkg-config libssl-dev protobuf-compiler

# 作業ディレクトリを作成します
WORKDIR /usr/src/app

# プロジェクトファイルをコピーします
COPY . .

# リリースモードでアプリケーションをビルドします
# これにより /usr/src/app/target/release/repoapi というバイナリが生成されます
RUN cargo build --release

# Stage 2: ランナー
# 軽量なDebianイメージを実行環境として使用します
FROM debian:bookworm-slim
# ビルダーからコンパイル済みのバイナリをコピーします
COPY --from=builder /usr/src/app/target/release/repoapi /usr/local/bin/repoapi
# アプリケーションが使用するポートを公開します
EXPOSE 8080
# コンテナ起動時にAPIサーバーを実行します
CMD ["repoapi"]