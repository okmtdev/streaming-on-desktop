#!/bin/bash
# StreamWall を .app バンドルとしてビルドするスクリプト。
# 使い方: ./build.sh   →   ./StreamWall.app が生成されます。
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="StreamWall"
APP_DIR="${APP_NAME}.app"

echo "==> swift build (release)"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"
if [ ! -f "$BIN_PATH" ]; then
    echo "ビルド成果物が見つかりません: $BIN_PATH" >&2
    exit 1
fi

echo "==> ${APP_DIR} を生成"
rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "$BIN_PATH" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp Info.plist "${APP_DIR}/Contents/Info.plist"
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

# ローカル実行用に ad-hoc 署名（Gatekeeper / ローカルネットワーク許可のため）
if command -v codesign >/dev/null 2>&1; then
    echo "==> ad-hoc 署名"
    codesign --force --deep --sign - "$APP_DIR" || echo "(署名はスキップされました)"
fi

echo ""
echo "完成: ${APP_DIR}"
echo "起動: open ${APP_DIR}   （または Finder でダブルクリック）"
