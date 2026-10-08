# AR_Camera

Esperienza AR per Android basata su Godot 4.7: feed della fotocamera, rilevamento
dei piani e minigiochi ancorati allo spazio reale. Il primo contenuto e' il
posizionamento di un cubo sul pavimento rilevato.

## Stato

- [x] Toolchain Android e build del plugin ARCore vendorizzato
- [x] Facade `ARSession` con backend ARCore (device) e simulato (desktop)
- [x] Esperienza "place cube": reticolo di puntamento, ghost e tap per piazzare
- [ ] Primo deploy su device da verificare
- [ ] Menu minigiochi e framework delle esperienze

## Struttura

| Percorso | Contenuto |
| --- | --- |
| `ar-camera_godot/` | progetto Godot (gioco) |
| `ar-camera_godot/scripts/ar/` | facade `ARSession` e backend (`ar_backend_arcore.gd`, `ar_backend_simulated.gd`) |
| `ar-camera_godot/scripts/minigames/` | esperienze/minigiochi (oggi: `place_cube.gd`) |
| `thirdparty/godot_arcore/` | plugin ARCore vendorizzato (vedi `thirdparty/README.md`) |
| `tools/build_arcore.sh` | compila il plugin e popola l'addon del progetto |

## Prerequisiti di sviluppo

- Godot 4.7 (nel repo si usa il Flatpak `org.godotengine.Godot`)
- Android SDK in `$HOME/Android/Sdk` con, per il plugin:
  `platforms;android-33`, `build-tools;33.0.2`, `ndk;23.2.8568313`, `cmake;3.22.1`
  e, per il template Android di Godot: `platforms;android-36`, `build-tools;36.1.0`
- JDK 17 per la build Gradle del plugin (default atteso: `$HOME/.local/opt/temurin-17`)
- `python3` (lo script crea da solo un venv con `scons` in `tools/.venv`)

## Build del plugin ARCore

```bash
tools/build_arcore.sh
```

Compila `godot-cpp` per Android (arm64), assembla il plugin con Gradle e copia
l'addon in `ar-camera_godot/addons/ARCorePlugin/`. Va rieseguito solo quando si
aggiorna `thirdparty/godot_arcore`. L'addon generato non e' versionato.

## Sviluppo su desktop (backend simulato)

Aprire `ar-camera_godot/` con Godot ed eseguire il progetto: su desktop si attiva
il backend simulato (piano a `y = 0`, tasto destro trascinato = orbita,
rotella = zoom, click sinistro = piazza un cubo). Su device si attiva il backend
ARCore reale.

## Export e deploy su Android

```bash
tools/export_android.sh
```

Genera `ar-camera_godot/build/arcamera-debug.apk` (firmato con il keystore di debug,
installabile su qualunque telefono). Lo script attende la creazione dell'APK e
termina da solo il processo headless di Godot, che altrimenti puo' restare appeso
al termine dell'export.

Per installarlo senza cavo: copiare l'APK sul telefono e aprirlo dal gestore file,
consentendo l'installazione da fonti sconosciute. Con il telefono collegato:

```bash
~/Android/Sdk/platform-tools/adb install -r ar-camera_godot/build/arcamera-debug.apk
```

Note:

- La prima esecuzione installa il build template (`ar-camera_godot/android/build/`,
  ignorato da git) e puo' richiedere diversi minuti.
- Il keystore di debug e' gia' configurato nelle impostazioni dell'editor Godot
  (`~/.var/app/org.godotengine.Godot/data/godot/keystores/debug.keystore`).
- Su Android il renderer e' forzato a `gl_compatibility` (vedi
  `renderer/rendering_method.mobile` in `project.godot`); su desktop resta il
  renderer Mobile.
- Log del gioco: `adb logcat | grep -i godot`.
