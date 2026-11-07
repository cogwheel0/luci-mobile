#!/usr/bin/env bash
# Упаковывает исходники, отправляет на сборочную ноду (проверка SHA-256 архива),
# собирает там release и забирает APK обратно с проверкой SHA-256.
# Использование: ci/remote_build.sh   → dist/LuCI-Mobile-X.Y.Z.apk
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${BUILD_HOST:-relkin@192.168.177.98}"
RDIR="${BUILD_DIR:-ci/luci-mobile}"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10 -i "$HOME/.ssh/id_rsa")
ssh "${SSH_OPTS[@]}" "$HOST" true || { echo "сборочная нода недоступна — стоп" >&2; exit 2; }

mkdir -p dist
tar --exclude=./build --exclude=./.dart_tool --exclude=./dist --exclude=./.git --exclude=./.idea \
    --exclude=./site --exclude=./.mega --exclude=./claude.md --exclude=./CLAUDE.md --exclude=./ios \
    --exclude=./android/.gradle --exclude=./android/app/build --exclude=./android/local.properties \
    --exclude=./fastlane --exclude=./store-badges \
    -czf dist/src.tgz .
(cd dist && sha256sum src.tgz > src.tgz.sha256)
scp -q "${SSH_OPTS[@]}" dist/src.tgz dist/src.tgz.sha256 "$HOST:/tmp/"
ssh "${SSH_OPTS[@]}" "$HOST" "set -e; cd /tmp && sha256sum -c src.tgz.sha256 \
  && mkdir -p ~/$RDIR && cd ~/$RDIR && rm -rf lib test assets android/app/src ci l10n.yaml pubspec.* \
  && tar -xzf /tmp/src.tgz && bash ci/build.sh"
version="$(sed -nE 's/^version: ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' pubspec.yaml)"
apk="LuCI-Mobile-$version.apk"
scp -q "${SSH_OPTS[@]}" "$HOST:$RDIR/dist/$apk" "$HOST:$RDIR/dist/$apk.sha256" dist/
(cd dist && sha256sum -c "$apk.sha256")
echo "dist/$apk"
