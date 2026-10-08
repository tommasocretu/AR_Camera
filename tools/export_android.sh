#!/usr/bin/env bash
#
# Esporta l'APK debug Android in ar-camera_godot/build/arcamera-debug.apk.
#
# Il processo headless di Godot a volte non si chiude da solo al termine
# dell'export: questo script attende la creazione dell'APK e poi termina
# l'istanza headless, senza toccare eventuali editor Godot aperti.
#
# Uso:
#   tools/export_android.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/ar-camera_godot"
OUT="$PROJECT/build/arcamera-debug.apk"
LOG="$PROJECT/build/export.log"
TIMEOUT_SECONDS=1800

log() { printf '\n==> %s\n' "$*"; }
fail() { printf 'ERRORE: %s\n' "$*" >&2; exit 1; }

[ -d "$PROJECT/addons/ARCorePlugin" ] || fail "addon ARCore mancante: esegui prima tools/build_arcore.sh"
mkdir -p "$PROJECT/build"
rm -f "$OUT"

log "Avvio export Android (prima build: puo' richiedere diversi minuti)"
setsid flatpak run org.godotengine.Godot --headless --path "$PROJECT" \
	--install-android-build-template \
	--export-debug Android "$OUT" > "$LOG" 2>&1 &
EXPORT_PID=$!

log "Attendo l'APK..."
deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
while true; do
	if [ -f "$OUT" ]; then
		size_a=$(stat -c%s "$OUT")
		sleep 3
		size_b=$(stat -c%s "$OUT")
		if [ "$size_a" = "$size_b" ] && unzip -t "$OUT" > /dev/null 2>&1; then
			break
		fi
	fi
	if ! kill -0 "$EXPORT_PID" 2>/dev/null; then
		break
	fi
	if [ "$(date +%s)" -gt "$deadline" ]; then
		break
	fi
	sleep 3
done

# Termina l'istanza headless (non l'editor) se e' rimasta appesa.
pkill -f "godot --headless --path $PROJECT" > /dev/null 2>&1 || true
wait "$EXPORT_PID" 2>/dev/null || true

[ -f "$OUT" ] || fail "APK non generato, vedi $LOG"
unzip -t "$OUT" > /dev/null 2>&1 || fail "APK corrotto: $OUT"

log "APK pronto: $OUT"
