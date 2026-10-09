extends Node
## Facade unica verso il layer AR.
##
## Esperienze e minigiochi parlano solo con questo autoload: il backend
## concreto (ARCore sul telefono, simulazione su desktop) resta un dettaglio
## interno. Vedi scripts/ar/ar_backend.gd per il contratto dei backend.

signal session_started

const TRACKING_STATUS_NAMES := {
	0: "UNKNOWN",
	1: "TRACKING",
	2: "EXCESSIVE_MOTION",
	3: "INSUFFICIENT_FEATURES",
	4: "NOT_TRACKING",
}

## True quando il backend attivo e' ARCore su device.
var is_device := false

var _backend: ARBackend = null
var _started := false


func _ready() -> void:
	_backend = _create_backend()
	if _backend == null:
		push_warning("ARSession: nessun backend AR disponibile")
		return
	_backend.name = "ARBackend"
	add_child(_backend)
	is_device = _backend.get_kind() in [ARBackend.Kind.ARCORE, ARBackend.Kind.MARKER]


func _create_backend() -> ARBackend:
	# ARCore solo quando il servizio e' effettivamente installato: sui device
	# senza "Google Play Services for AR" la detection fallisce e subentra il
	# backend marker (nessun prompt di installazione automatico).
	var arcore_plugin: Object = Engine.get_singleton("ARCorePlugin")
	if ClassDB.class_exists("ARCoreInterface") and arcore_plugin != null and _is_arcore_usable(arcore_plugin):
		return preload("res://scripts/ar/backends/ar_backend_arcore.gd").new()
	if Engine.has_singleton("MarkerARPlugin"):
		return preload("res://scripts/ar/backends/ar_backend_marker.gd").new()
	if not OS.has_feature("mobile"):
		return preload("res://scripts/ar/backends/ar_backend_simulated.gd").new()
	return null


## True se il plugin ARCore riporta il servizio come installato. Plugin piu'
## vecchi senza la patch non espongono il metodo: in quel caso si mantiene il
## comportamento precedente (backend ARCore).
func _is_arcore_usable(plugin: Object) -> bool:
	if not plugin.has_method("getArCoreAvailability"):
		return true
	return plugin.getArCoreAvailability() == "supported_installed"


func is_available() -> bool:
	return _backend != null


func start() -> void:
	if _backend == null or _started:
		return
	_started = true
	_backend.start()
	session_started.emit()


func stop() -> void:
	if _backend == null or not _started:
		return
	_started = false
	_backend.stop()


func get_backend_name() -> String:
	if _backend == null:
		return "none"
	return _backend.get_backend_name()


func get_tracking_status() -> int:
	if _backend == null:
		return 4
	return _backend.get_tracking_status()


func tracking_status_name(status: int) -> String:
	return TRACKING_STATUS_NAMES.get(status, "UNKNOWN(%d)" % status)


## Piani rilevati: Array di Dictionary con chiavi "id", "transform", "boundary".
func get_planes() -> Array:
	if _backend == null:
		return []
	return _backend.get_planes()


## Posizione in coordinate schermo dove punta il reticolo di puntamento.
func get_aim_position() -> Vector2:
	if _backend == null:
		return Vector2.ZERO
	return _backend.get_aim_position()


## Converte la posizione di un input (tap/click) in coordinate schermo.
func get_pointer_position(event_position: Vector2) -> Vector2:
	if _backend == null:
		return event_position
	return _backend.get_pointer_position(event_position)


## Raycast dalla posizione schermo verso il mondo.
## Ritorna {"hit": bool, "transform": Transform3D}.
func raycast_screen(position: Vector2) -> Dictionary:
	if _backend == null:
		return {"hit": false, "transform": Transform3D.IDENTITY}
	return _backend.raycast_screen(position)


## Aggancia il nodo alla trasformazione nel mondo.
func attach_to_world(node: Node3D, world_transform: Transform3D) -> void:
	if _backend == null:
		node.global_transform = world_transform
		return
	_backend.attach_to_world(node, world_transform)


## ID del feed camera da usare come sfondo, -1 se non disponibile.
func get_camera_feed_id() -> int:
	if _backend == null:
		return -1
	return _backend.get_camera_feed_id()


## ID del marker tracciato (solo backend marker), -1 se nessuno/disponibile.
func get_marker_id() -> int:
	if _backend == null:
		return -1
	if not _backend.has_method("get_marker_id"):
		return -1
	return _backend.get_marker_id()
