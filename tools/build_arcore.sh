#!/usr/bin/env bash
#
# Compila il plugin ARCore vendorizzato (thirdparty/godot_arcore) e popola
# l'addon del progetto Godot (ar-camera_godot/addons/ARCorePlugin).
#
# Requisiti (una tantum):
#   - Android SDK in $ANDROID_HOME (default: ~/Android/Sdk) con:
#       platforms;android-33, build-tools;33.0.2, ndk;23.2.8568313, cmake;3.22.1
#   - JDK 17 in $JAVA_HOME (default: ~/.local/opt/temurin-17)
#   - python3
#
# Uso:
#   tools/build_arcore.sh            # build completo
#   tools/build_arcore.sh --gradle   # salta godot-cpp (se gia' compilato)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/thirdparty/godot_arcore"
PROJECT="$ROOT/ar-camera_godot"
SDK="${ANDROID_HOME:-$HOME/Android/Sdk}"
NDK_VERSION="23.2.8568313"
JDK="${JAVA_HOME:-$HOME/.local/opt/temurin-17}"
VENV="$ROOT/tools/.venv"
SCONS="$VENV/bin/scons"
JOBS="$(nproc)"

log() { printf '\n==> %s\n' "$*"; }
fail() { printf 'ERRORE: %s\n' "$*" >&2; exit 1; }

[ -d "$VENDOR" ] || fail "vendor mancante: $VENDOR"
[ -d "$SDK" ] || fail "Android SDK non trovato in $SDK (imposta ANDROID_HOME)"
[ -d "$SDK/ndk/$NDK_VERSION" ] || fail "NDK $NDK_VERSION mancante in $SDK/ndk (installa con sdkmanager)"
[ -x "$JDK/bin/java" ] || fail "JDK 17 non trovato in $JDK (imposta JAVA_HOME)"

if [ ! -x "$SCONS" ]; then
	log "Creo il virtualenv con scons in tools/.venv"
	python3 -m venv "$VENV"
	"$VENV/bin/pip" install -q scons
fi

export ANDROID_HOME="$SDK"
export ANDROID_NDK_ROOT="$SDK/ndk/$NDK_VERSION"
export JAVA_HOME="$JDK"

if [ "${1:-}" != "--gradle" ]; then
	log "Build godot-cpp (Android arm64, debug + release)"
	(
		cd "$VENDOR/godot-cpp"
		"$SCONS" platform=android target=template_debug arch=arm64 -j"$JOBS"
		"$SCONS" platform=android target=template_release arch=arm64 -j"$JOBS"
	)
fi

log "Assemblo il plugin Android (Gradle)"
printf 'sdk.dir=%s\n' "$SDK" > "$VENDOR/local.properties"
(cd "$VENDOR" && ./gradlew assemble)

log "Copio l'addon nel progetto Godot"
rm -rf "$PROJECT/addons/ARCorePlugin"
mkdir -p "$PROJECT/addons"
cp -r "$VENDOR/plugin/demo/addons/ARCorePlugin" "$PROJECT/addons/ARCorePlugin"

log "Fatto: $PROJECT/addons/ARCorePlugin"
