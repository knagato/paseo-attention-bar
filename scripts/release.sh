#!/bin/bash
# 配布用の zip を作る: ユニバーサルビルド → Developer ID 署名 → 公証 → staple → zip。
#
# 事前に一度だけ、公証用の認証情報をキーチェーンに登録しておく:
#   xcrun notarytool store-credentials paseo-notary --apple-id <Apple ID> --team-id <Team ID>
#
# 環境変数:
#   SIGN_IDENTITY   署名 ID（既定 "Developer ID Application"。キーチェーンに 1 つだけならこれで一意に決まる）
#   NOTARY_PROFILE  notarytool の keychain profile 名（既定 paseo-notary）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="PaseoAttentionBar"
APP_DIR="$ROOT/dist/$APP_NAME.app"
export SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-paseo-notary}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
ZIP_PATH="$ROOT/dist/$APP_NAME-$VERSION.zip"

UNIVERSAL=1 "$ROOT/scripts/bundle.sh"

echo "==> verifying signature"
codesign --verify --strict --deep --verbose=2 "$APP_DIR"

echo "==> notarizing (profile: $NOTARY_PROFILE)"
NOTARIZE_ZIP="$(mktemp -d)/$APP_NAME.zip"
ditto -c -k --keepParent "$APP_DIR" "$NOTARIZE_ZIP"
xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
rm -f "$NOTARIZE_ZIP"

echo "==> stapling"
xcrun stapler staple "$APP_DIR"
spctl --assess --type execute --verbose=2 "$APP_DIR"

echo "==> packaging $ZIP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH"

echo "==> done: $ZIP_PATH"
