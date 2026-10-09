# native

Plugin nativi di proprieta' del progetto (non vendorizzati).

## marker_ar

Plugin Android v2 (`MarkerARPlugin`) che implementa il backend AR "marker ArUco"
senza servizi Google: fotocamera (Camera2), anteprima come feed custom di Godot
e stima della posa dei marker con OpenCV (`ArucoDetector` + `solvePnP`).

- Linguaggio: Kotlin; build: Gradle (`tools/build_marker_ar.sh`).
- Output: `ar-camera_godot/addons/MarkerARPlugin/` (ignorato da git).
- OpenCV: dipendenza Maven `org.opencv:opencv:4.12.0`, dichiarata nell'export
  plugin e quindi presente solo nell'APK (nessun .so nel repository).
- API esposta a GDScript:
  - metodi: `has_camera_permission()`, `request_camera_permission()`,
    `start(config)`, `stop()`, `get_intrinsics()`;
  - segnali: `camera_permission_granted`, `camera_permission_denied`,
    `frame_available(frame)`, `markers_detected(data)`.

Convenzioni delle pose: i punti oggetto del marker sono nell'ordine
alto-sinistra, alto-destra, basso-destra, basso-sinistra (ordine orario di
ArUco) con il frame marker Y-up/Z verso la camera; la conversione OpenCV →
Godot e' `R_godot = M * R_cv`, `t_godot = M * t_cv` con `M = diag(1, -1, -1)`.
La rotazione del frame (per l'anteprima upright) viene compensata ruotando la
posa di `Rz(rotazione)` prima della conversione.

Le trasformazioni dei frame (`FrameTransforms.kt`) sono adattate (MIT) da
<https://github.com/godot-mobile-plugins/godot-native-camera>.

### Config di `start(config)`

| Chiave | Default | Significato |
| --- | --- | --- |
| `camera_id` | prima posteriore | ID della fotocamera |
| `capture_width` / `capture_height` | 1280 x 720 | risoluzione di cattura (approssimata alla piu' vicina supportata) |
| `preview_width` / `preview_height` | 540 x 960 | dimensione del frame di anteprima emesso (scambiata se l'orientamento non combacia) |
| `preview_every_frames` | 2 | emette 1 frame di anteprima ogni N catture |
| `detect_every_frames` | 3 | esegue la detection 1 volta ogni N catture |
| `auto_upright` | true | calcola la rotazione dal sensore/orientamento device |
| `rotation` | 0 | rotazione fissa, usata con `auto_upright = false` |
| `marker_size` | 0.12 | lato del quadrato nero del marker in metri |
| `marker_dictionary` | `DICT_4X4_50` | dizionario ArUco (`DICT_5X5_50`, `DICT_6X6_50`, `DICT_ARUCO_ORIGINAL`) |
