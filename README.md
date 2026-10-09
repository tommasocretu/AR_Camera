# AR_Camera

Esperienza AR per Android basata su Godot 4.7: feed della fotocamera, rilevamento
dei piani e minigiochi ancorati allo spazio reale. Il primo contenuto e' il
posizionamento di un cubo sul pavimento rilevato.

Due backend AR, selezionati a runtime:

- **ARCore** sui device con "Google Play Services for AR" installato (piani e
  motion tracking);
- **marker ArUco** su qualunque altro device Android, senza servizi Google
  (nessun rilevamento piani: il contenuto e' ancorato al marker).

## Stato

- [x] Toolchain Android e build del plugin ARCore vendorizzato
- [x] Facade `ARSession` con backend ARCore (device) e simulato (desktop)
- [x] Esperienza "place cube": reticolo di puntamento, ghost e tap per piazzare
- [x] Backend marker ArUco "Google-free" (`native/marker_ar` + `MarkerARPlugin`)
- [ ] Primo deploy su device da verificare
- [ ] Menu minigiochi e framework delle esperienze

## Struttura

| Percorso | Contenuto |
| --- | --- |
| `ar-camera_godot/` | progetto Godot (gioco) |
| `ar-camera_godot/scripts/ar/` | facade `ARSession` e backend (`ar_backend_arcore.gd`, `ar_backend_marker.gd`, `ar_backend_simulated.gd`) |
| `ar-camera_godot/scripts/minigames/` | esperienze/minigiochi (oggi: `place_cube.gd`) |
| `ar-camera_godot/assets/markers/` | marker ArUco stampabile per il backend marker |
| `thirdparty/godot_arcore/` | plugin ARCore vendorizzato (vedi `thirdparty/README.md`) |
| `native/marker_ar/` | plugin Android marker Kotlin + OpenCV (vedi `native/README.md`) |
| `tools/build_arcore.sh` | compila il plugin ARCore e popola l'addon del progetto |
| `tools/build_marker_ar.sh` | compila il plugin marker e popola l'addon del progetto |
| `tools/generate_aruco_marker.py` | rigenera il marker ArUco stampabile |

## Prerequisiti di sviluppo

- Godot 4.7 (nel repo si usa il Flatpak `org.godotengine.Godot`)
- Android SDK in `$HOME/Android/Sdk` con, per il plugin:
  `platforms;android-33`, `build-tools;33.0.2`, `ndk;23.2.8568313`, `cmake;3.22.1`
  e, per il template Android di Godot: `platforms;android-36`, `build-tools;36.1.0`
- JDK 17 per la build Gradle del plugin (default atteso: `$HOME/.local/opt/temurin-17`)
- `python3` (lo script crea da solo un venv con `scons` in `tools/.venv`)
- OpenCV per il plugin marker: scaricato da Maven Central (`org.opencv:opencv:4.12.0`)
  durante la build Gradle, non serve installarlo a mano.

## Build del plugin ARCore

```bash
tools/build_arcore.sh
```

Compila `godot-cpp` per Android (arm64), assembla il plugin con Gradle e copia
l'addon in `ar-camera_godot/addons/ARCorePlugin/`. Va rieseguito solo quando si
aggiorna `thirdparty/godot_arcore`. L'addon generato non e' versionato.

## Build del plugin marker

```bash
tools/build_marker_ar.sh
```

Compila il plugin Android `native/marker_ar` (Gradle, niente NDK) e copia
l'addon in `ar-camera_godot/addons/MarkerARPlugin/`. L'addon generato non e'
versionato. OpenCV viene impacchettato nell'APK dall'export plugin, non nel
repository.

## Marker ArUco

Il backend marker usa un marker `DICT_4X4_50` id 0 stampato su carta:

1. stampare `ar-camera_godot/assets/markers/aruco_4x4_50_id0.png` in modo che il
   **quadrato nero misuri 12 cm di lato** (l'immagine intera risulta ~15 cm,
   quiet zone inclusa);
2. inquadrarlo con la fotocamera posteriore: il reticolo si posiziona sul
   marker e un tap piazza il cubo.

Se si cambia la dimensione stampata, aggiornare `MARKER_SIZE_METERS` in
`ar-camera_godot/scripts/ar/backends/ar_backend_marker.gd`. Il marker PNG si
rigenera con `tools/generate_aruco_marker.py` (richiede `opencv-python`).

## Sviluppo su desktop (backend simulato)

Aprire `ar-camera_godot/` con Godot ed eseguire il progetto: su desktop si attiva
il backend simulato (piano a `y = 0`, tasto destro trascinato = orbita,
rotella = zoom, click sinistro = piazza un cubo). Su device il backend e' scelto
a runtime: ARCore se il servizio e' installato, altrimenti il backend marker
(il backend marker non e' disponibile su desktop).

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
- L'export richiede entrambi gli addon: eseguire `tools/build_arcore.sh` e
  `tools/build_marker_ar.sh` almeno una volta.
- L'APK include OpenCV (~25 MB per arm64) e il plugin ARCore, quindi e' piu'
  grande di un'app Godot vuota.
- Il keystore di debug e' gia' configurato nelle impostazioni dell'editor Godot
  (`~/.var/app/org.godotengine.Godot/data/godot/keystores/debug.keystore`).
- Su Android il renderer e' forzato a `gl_compatibility` (vedi
  `renderer/rendering_method.mobile` in `project.godot`); su desktop resta il
  renderer Mobile.
- Log del gioco: `adb logcat | grep -i godot` (il plugin marker usa il tag
  `MarkerARPlugin`).
