#!/bin/bash
# StreamWall を Developer ID で署名・公証(notarize)・.dmg 化する配布用スクリプト（macOS 専用）。
#
# 前提:
#   - Apple Developer Program 登録済み（年 $99）
#   - 「Developer ID Application」証明書がキーチェーンにある
#   - 公証用の認証情報（下のどちらか）
#
# 認証情報の渡し方（どちらか）:
#   A) キーチェーンに保存したプロファイルを使う（推奨。事前に1回だけ実行）:
#        xcrun notarytool store-credentials StreamWallNotary \
#          --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
#      → 実行時:  NOTARY_PROFILE=StreamWallNotary ./release.sh
#
#   B) その都度 環境変数で渡す:
#        APPLE_ID="you@example.com" TEAM_ID="TEAMID" APP_PASSWORD="app-specific-pw" ./release.sh
#
# 署名 ID の指定（任意。省略時はキーチェーンから自動検出）:
#        SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./release.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="StreamWall"
APP_DIR="${APP_NAME}.app"
DMG_PATH="${APP_NAME}.dmg"
ZIP_PATH="${APP_NAME}-notarize.zip"

# 1) 通常ビルドで .app を組み立てる（ad-hoc 署名はこの後 上書きされる）
echo "==> .app を組み立て"
./build.sh

# 2) 署名 ID を決定
if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning \
        | grep "Developer ID Application" | head -1 \
        | sed -E 's/.*"(.*)"/\1/')"
fi
if [ -z "${SIGN_IDENTITY:-}" ]; then
    echo "Developer ID Application 証明書が見つかりません。" >&2
    echo "Apple Developer から証明書を作成・インストールしてください。" >&2
    exit 1
fi
echo "==> 署名 ID: ${SIGN_IDENTITY}"

# 3) Hardened Runtime 付きで署名（公証の必須要件）
echo "==> 署名（hardened runtime）"
codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP_DIR"
codesign --verify --strict --verbose=2 "$APP_DIR"

# 4) 公証用に zip 化して submit
echo "==> 公証へ提出"
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
elif [ -n "${APPLE_ID:-}" ] && [ -n "${TEAM_ID:-}" ] && [ -n "${APP_PASSWORD:-}" ]; then
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD" --wait
else
    echo "公証の認証情報がありません。NOTARY_PROFILE か APPLE_ID/TEAM_ID/APP_PASSWORD を設定してください。" >&2
    echo "（署名済み .app は ${APP_DIR} に出来ています）" >&2
    exit 1
fi

# 5) staple（公証チケットを .app に添付）
echo "==> staple"
xcrun stapler staple "$APP_DIR"
rm -f "$ZIP_PATH"

# 6) .dmg を作成して staple
echo "==> ${DMG_PATH} を作成"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_PATH"
xcrun stapler staple "$DMG_PATH" || echo "(dmg の staple はスキップ)"

echo ""
echo "完成: ${DMG_PATH}（署名・公証済み）"
echo "配布: この .dmg をそのまま渡せば、他の Mac で警告なく開けます。"
