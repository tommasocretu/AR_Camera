#!/usr/bin/env bash
#
# Aggiorna la versione dell'app e il versionCode Android.
#
# La versione vive in un solo posto: application/config/version in
# ar-camera_godot/project.godot. Questo script la scrive li' e allinea
# version/code in ar-camera_godot/export_presets.cfg, che Godot usa come
# versionCode dell'APK.
#
# Schema del versionCode: major * 10000 + minor * 100 + patch
# (es. 1.1.0 -> 10100), quindi minor e patch devono stare sotto 100.
#
# Il versionCode non puo' mai scendere: serve ad Android per accettare
# l'installazione sopra la build precedente.
#
# Uso:
#   tools/bump_version.sh 1.2.0
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/ar-camera_godot"
GODOT_FILE="$PROJECT/project.godot"
PRESET_FILE="$PROJECT/export_presets.cfg"

fail() { printf 'ERRORE: %s\n' "$*" >&2; exit 1; }

[ $# -eq 1 ] || fail "uso: tools/bump_version.sh <major.minor.patch>"
NEW="$1"

[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "versione non valida: $NEW (atteso major.minor.patch, es. 1.2.0)"

IFS=. read -r new_major new_minor new_patch <<< "$NEW"

[ "$new_minor" -lt 100 ] || fail "il minor deve essere < 100 per lo schema del versionCode"
[ "$new_patch" -lt 100 ] || fail "la patch deve essere < 100 per lo schema del versionCode"

new_code=$(( 10#$new_major * 10000 + 10#$new_minor * 100 + 10#$new_patch ))

[ -f "$GODOT_FILE" ] || fail "file mancante: $GODOT_FILE"
[ -f "$PRESET_FILE" ] || fail "file mancante: $PRESET_FILE"

old_version="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' "$GODOT_FILE" | head -n 1)"
[ -n "$old_version" ] || old_version="0.0.0"
old_code="$(sed -n 's/^version\/code=\([0-9]\+\)$/\1/p' "$PRESET_FILE" | head -n 1)"
[ -n "$old_code" ] || old_code=0

if [ "$NEW" = "$old_version" ] && [ "$new_code" = "$old_code" ]; then
	printf 'Versione gia\047a %s (code %s): niente da fare.\n' "$NEW" "$new_code"
	exit 0
fi

[ "$new_code" -ge "$old_code" ] || fail "il versionCode scenderebbe da $old_code a $new_code: usa una versione >= $old_version"

# project.godot: sostituisce la riga esistente o la crea dopo config/name.
if grep -q '^config/version=' "$GODOT_FILE"; then
	sed -i "s|^config/version=.*|config/version=\"$NEW\"|" "$GODOT_FILE"
else
	sed -i "/^config\/name=/a config/version=\"$NEW\"" "$GODOT_FILE"
fi

# export_presets.cfg: version/name resta vuoto per ereditare project.godot.
if grep -q '^version/code=' "$PRESET_FILE"; then
	sed -i "s|^version/code=.*|version/code=$new_code|" "$PRESET_FILE"
else
	printf '\nversion/code=%s\n' "$new_code" >> "$PRESET_FILE"
fi
if grep -q '^version/name=' "$PRESET_FILE"; then
	sed -i 's|^version/name=.*|version/name=""|' "$PRESET_FILE"
else
	printf 'version/name=""\n' >> "$PRESET_FILE"
fi

printf 'Versione: %s -> %s\n' "$old_version" "$NEW"
printf 'versionCode: %s -> %s\n' "$old_code" "$new_code"
