#!/bin/bash
# SwiftPM の実行ファイルから .app バンドルを組み立てる。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP_NAME="PaseoAttentionBar"
BIN_PATH="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)/$APP_NAME"
APP_DIR="$ROOT/dist/$APP_NAME.app"

echo "==> building ($CONFIG)"
swift build --package-path "$ROOT" -c "$CONFIG"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "実行ファイルが見つかりません: $BIN_PATH" >&2
  exit 1
fi

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "==> code signing (ad-hoc)"
codesign --force --sign - --identifier com.knagato.PaseoAttentionBar "$APP_DIR"

echo "==> done: $APP_DIR"
