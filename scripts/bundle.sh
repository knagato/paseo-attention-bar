#!/bin/bash
# SwiftPM の実行ファイルから .app バンドルを組み立てる。
#
# 環境変数:
#   CONFIG         ビルド構成（既定 release）
#   UNIVERSAL=1    arm64 + x86_64 のユニバーサルバイナリにする（配布用）
#   SIGN_IDENTITY  codesign の署名 ID（既定 "-" = ad-hoc）。
#                  Developer ID を指定すると Hardened Runtime とタイムスタンプを付ける（公証に必要）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_NAME="PaseoAttentionBar"
APP_DIR="$ROOT/dist/$APP_NAME.app"

BUILD_ARGS=(--package-path "$ROOT" -c "$CONFIG")
ARCH_LABEL="native"
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
  ARCH_LABEL="universal"
fi
BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/$APP_NAME"

echo "==> building ($CONFIG, $ARCH_LABEL)"
swift build "${BUILD_ARGS[@]}"

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

SIGN_ARGS=(--force --sign "$SIGN_IDENTITY" --identifier com.knagato.PaseoAttentionBar)
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "==> code signing (ad-hoc)"
else
  echo "==> code signing ($SIGN_IDENTITY)"
  SIGN_ARGS+=(--options runtime --timestamp)
fi
codesign "${SIGN_ARGS[@]}" "$APP_DIR"

echo "==> done: $APP_DIR"
