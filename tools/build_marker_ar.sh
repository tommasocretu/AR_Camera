#!/usr/bin/env bash
#
# Compila il plugin Android MarkerAR (native/marker_ar) e popola l'addon del
# progetto Godot (ar-camera_godot/addons/MarkerARPlugin).
#
# Requisiti (una tantum):
#   - Android SDK in $ANDROID_HOME (default: ~/Android/Sdk) con:
#       platforms;android-33, build-tools;33.0.2
#   - JDK 17 in $JAVA_HOME (default: ~/.local/opt/temurin-17)
#
# Uso:
#   tools/build_marker_ar.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="$ROOT/native/marker_ar"
PROJECT="$ROOT/ar-camera_godot"
SDK="${ANDROID_HOME:-$HOME/Android/Sdk}"
JDK="${JAVA_HOME:-$HOME/.local/opt/temurin-17}"

log() { printf '\n==> %s\n' "$*"; }
fail() { printf 'ERRORE: %s\n' "$*" >&2; exit 1; }

[ -d "$PLUGIN" ] || fail "plugin mancante: $PLUGIN"
[ -d "$SDK" ] || fail "Android SDK non trovato in $SDK (imposta ANDROID_HOME)"
[ -d "$SDK/platforms/android-33" ] || fail "platforms;android-33 mancante in $SDK (installa con sdkmanager)"
[ -x "$JDK/bin/java" ] || fail "JDK 17 non trovato in $JDK (imposta JAVA_HOME)"

export ANDROID_HOME="$SDK"
export JAVA_HOME="$JDK"

log "Assemblo il plugin Android (Gradle)"
printf 'sdk.dir=%s\n' "$SDK" > "$PLUGIN/local.properties"
(cd "$PLUGIN" && ./gradlew assemble)

ADDON_BUILD="$PLUGIN/plugin/build/addon/MarkerARPlugin"
[ -d "$ADDON_BUILD" ] || fail "addon non generato: $ADDON_BUILD"

log "Copio l'addon nel progetto Godot"
rm -rf "$PROJECT/addons/MarkerARPlugin"
mkdir -p "$PROJECT/addons"
cp -r "$ADDON_BUILD" "$PROJECT/addons/MarkerARPlugin"

log "Fatto: $PROJECT/addons/MarkerARPlugin"
