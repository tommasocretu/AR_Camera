# thirdparty

## godot_arcore

Copia vendorizzata del plugin GDExtension ARCore per Godot.

- Fork di riferimento: <https://github.com/tGautot/godot_arcore> (fork di <https://github.com/GodotVR/godot_arcore>)
- Commit pinnato: `a738cab8779e606428494fe2e5d3fd5c93029fab` (master, 1 agosto 2025)
- godot-cpp: branch `4.4`, commit `b0e3b1e4b78a606f48d162898afb5eeda533d2a9`
- Licenza: MIT (vedi `LICENSE` nel repository vendorizzato)

Perché il fork e non l'upstream: contiene correzioni al raycast (`getHitPose`/`getHitRayPose`),
il plane tracker esposto a GDScript (`plane_tracker_*`), la gestione della rotazione del device
via JNI e alcune correzioni a image tracking. L'upstream è fermo a novembre 2024 e non è più
mantenuto attivamente.

### Patch locali da mantenere in caso di aggiornamento del vendor

File: `plugin/export_scripts_template/ARCoreInterface.gd`

- l'autoload istanzia l'interfaccia dinamicamente con `ClassDB.class_exists` +
  `ClassDB.instantiate`, così sui desktop (dove l'estensione nativa non esiste) il progetto
  non genera errori di parsing;
- `start()` e `get_tracking_status()` sono null-safe;
- bug fix: `enable_point_cloud_detection()` chiamava `enable_light_estimation()`.

File: `plugin/src/main/java/org/godotengine/plugin/android/arcore/ARCorePlugin.kt`

- patch per il backend marker: `getArCoreAvailability()` e `requestArCoreInstall()`
  esposti a GDScript; l'installazione di ARCore non è più automatica in
  `onMainResume` (flag `automaticInstallEnabled`, default `false`). L'app sceglie
  il backend ARCore solo se il servizio è già installato, altrimenti usa il
  backend marker senza mostrare il prompt di installazione.

File: `plugin/src/main/AndroidManifest.xml`

- patch per il backend marker: meta-data `com.google.ar.core` da `required` a
  `optional` e `uses-feature android.hardware.camera.ar` con `required=false`,
  così l'app resta installabile (e non viene filtrata dallo store) sui device
  senza "Google Play Services for AR".

File: `gradle/wrapper/gradle-wrapper.properties`

- Gradle portato da 8.9 a 7.6.4: il progetto Gradle usa ancora AGP 7.4.1, che non è
  compatibile con Gradle 8.x. In alternativa si può aggiornare AGP, ma questa via non
  richiede modifiche ai file di build.

File: `thirdparty/godot_cpp_extension_api/`

- rimosso: era il dump dell'API di Godot 4.2 usato dal vecchio build con
  `custom_api_file`; il nostro build usa il branch `4.4` di godot-cpp e il suo
  `extension_api.json`.

### Build

Vedi `tools/build_arcore.sh`. Tutti gli artefatti di build sono ignorati da git
(centos anche l'addon generato `ar-camera_godot/addons/ARCorePlugin/`).
