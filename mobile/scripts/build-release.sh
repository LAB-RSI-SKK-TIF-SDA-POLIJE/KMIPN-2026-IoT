#!/usr/bin/env bash
# =====================================================================
# SafeRise - Production Release Build (Linux/macOS)
# Membangun APK release dengan dart-define dari scripts/build.config
# Pemakaian:
#   ./scripts/build-release.sh              # build apk release
#   ./scripts/build-release.sh --clean      # bersihkan dulu (flutter clean)
#   ./scripts/build-release.sh --target appbundle
# =====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_PATH="$SCRIPT_DIR/build.config"

if [ ! -f "$CONFIG_PATH" ]; then
    cp "$SCRIPT_DIR/build.config.example" "$CONFIG_PATH"
    echo "ERROR: build.config belum ada -> sudah disalin dari build.config.example." >&2
    echo "ISI nilainya dulu, lalu jalankan ulang." >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_PATH"

MQTT_PORT="${MQTT_PORT:-8883}"
FLUTTER_TARGET="${FLUTTER_TARGET:-apk}"
CLEAN=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)  CLEAN="1" ;;
        --target) FLUTTER_TARGET="$2"; shift ;;
        *) echo "Argumen tidak dikenal: $1" >&2; exit 1 ;;
    esac
    shift
done

: "${MQTT_HOST:?MQTT_HOST wajib diisi di build.config}"
: "${BACKEND_URL:?BACKEND_URL wajib diisi di build.config}"

cd "$PROJECT_DIR"

if [ -n "$CLEAN" ]; then
    echo ">> flutter clean"
    flutter clean
    flutter pub get
fi

ARGS=(build "$FLUTTER_TARGET" --release
    "--dart-define=MQTT_HOST=$MQTT_HOST"
    "--dart-define=MQTT_PORT=$MQTT_PORT"
    "--dart-define=BACKEND_URL=$BACKEND_URL")
[ -n "${MQTT_USERNAME:-}" ] && ARGS+=("--dart-define=MQTT_USERNAME=$MQTT_USERNAME")
[ -n "${MQTT_PASSWORD:-}" ] && ARGS+=("--dart-define=MQTT_PASSWORD=$MQTT_PASSWORD")

echo ">> flutter ${ARGS[*]}"
flutter "${ARGS[@]}"

echo ""
echo "✅ Build selesai."
case "$FLUTTER_TARGET" in
    apk)       echo "   APK : build/app/outputs/flutter-apk/app-release.apk" ;;
    appbundle) echo "   AAB : build/app/outputs/bundle/release/app-release.aab" ;;
esac
