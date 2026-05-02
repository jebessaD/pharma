#!/usr/bin/env bash
# Release App Bundle for Google Play with Dart obfuscation and split debug info.
# Upload the generated symbols to Play Console (App bundle explorer) or retain them for crash deobfuscation.
#
# Prerequisites:
#   - Flutter SDK on PATH
#   - For Play upload builds: android/key.properties (see android/key.properties.example)
#
# Optional:
#   - tool/dart_defines.local.json — copy from tool/dart_defines.example.json (gitignored)
#   - DART_DEFINE_FILE=/path/to.json — overrides the default local defines path
#   - REQUIRE_UPLOAD_KEY=1 — fail if android/key.properties is missing (use for CI / store builds)
#
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

KEY_PROPS="$ROOT/android/key.properties"
if [[ "${REQUIRE_UPLOAD_KEY:-}" == "1" ]] && [[ ! -f "$KEY_PROPS" ]]; then
  echo "error: REQUIRE_UPLOAD_KEY=1 but $KEY_PROPS is missing." >&2
  echo "Create an upload keystore and key.properties (see android/key.properties.example)." >&2
  exit 1
elif [[ ! -f "$KEY_PROPS" ]]; then
  echo "warning: $KEY_PROPS not found — release will sign with the debug key (not valid for Play upload)." >&2
fi

DEFINE_FILE="${DART_DEFINE_FILE:-}"
if [[ -z "$DEFINE_FILE" && -f "$ROOT/tool/dart_defines.local.json" ]]; then
  DEFINE_FILE="$ROOT/tool/dart_defines.local.json"
fi

DEFINE_ARGS=()
if [[ -n "$DEFINE_FILE" ]]; then
  DEFINE_ARGS+=(--dart-define-from-file="$DEFINE_FILE")
  echo "Using dart-define-from-file: $DEFINE_FILE"
fi

SYMBOLS_DIR="${SYMBOLS_DIR:-$ROOT/build/app/obfuscation_symbols}"
mkdir -p "$SYMBOLS_DIR"

# Under `set -u`, `"${DEFINE_ARGS[@]}"` can error when the array is empty on some Bash versions.
if [[ ${#DEFINE_ARGS[@]} -gt 0 ]]; then
  flutter build appbundle --release \
    --obfuscate \
    --split-debug-info="$SYMBOLS_DIR" \
    "${DEFINE_ARGS[@]}"
else
  flutter build appbundle --release \
    --obfuscate \
    --split-debug-info="$SYMBOLS_DIR"
fi

echo ""
echo "AAB: $ROOT/build/app/outputs/bundle/release/app-release.aab"
echo "Dart split debug info: $SYMBOLS_DIR (archive securely; do not ship inside the app)"
