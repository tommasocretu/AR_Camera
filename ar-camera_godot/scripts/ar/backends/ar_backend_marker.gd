extends ARBackend
## Backend marker ArUco, senza servizi Google.
##
## Usa il plugin Android "MarkerARPlugin" (Kotlin + OpenCV):
##  - i frame RGBA "upright" del plugin alimentano un CameraFeed custom,
##    mostrato come sfondo (Environment.background_camera_feed_id), come fa
##    il backend ARCore;
##  - le pose dei marker diventano l'ancora di mondo per i minigiochi.
##
## Limiti rispetto ad ARCore: nessun rilevamento piani, nessun motion tracking.
## Il contenuto e' ancorato al marker e la posa e' valida solo finche' una
## detection recente e' disponibile.

const PLUGIN_NAME := "MarkerARPlugin"
const MAX_POSE_AGE_MSEC := 700
const CAPTURE_WIDTH := 1280
const CAPTURE_HEIGHT := 720
const PREVIEW_WIDTH := 540
const PREVIEW_HEIGHT := 960
const PREVIEW_EVERY_FRAMES := 2
const DETECT_EVERY_FRAMES := 3
const MARKER_SIZE_METERS := 0.12
const MARKER_DICTIONARY := "DICT_4X4_50"

var _plugin: Object = null
var _feed: CameraFeed = null
var _started := false

var _last_pose := Transform3D.IDENTITY
var _last_marker_id := -1
var _last_detection_msec := -100000
var _camera_fov_applied := false


func get_kind() -> Kind:
	return Kind.MARKER


func get_backend_name() -> String:
	return "Marker (ArUco)"


func start() -> void:
	_plugin = Engine.get_singleton(PLUGIN_NAME)
	if _plugin == null:
		push_error("Marker: singleton %s non disponibile" % PLUGIN_NAME)
		return
	_started = true
	_connect_signals()
	if _plugin.has_camera_permission():
		_start_camera()
	else:
		_plugin.request_camera_permission()


func stop() -> void:
	if not _started:
		return
	_started = false
	if _plugin != null:
		_plugin.stop()
	_remove_feed()


func get_tracking_status() -> int:
	if get_marker_id() >= 0:
		return 1 # TRACKING
	return 4 # NOT_TRACKING


func get_planes() -> Array:
	return []


## Con il backend marker non esiste un raycast vero: quando un marker e'
## visibile il "colpo" e' la posa del marker stesso, indipendentemente dal
## punto dello schermo toccato.
func raycast_screen(_position: Vector2) -> Dictionary:
	if get_marker_id() < 0:
		return {"hit": false, "transform": Transform3D.IDENTITY}
	return {"hit": true, "transform": _last_pose}


func get_camera_feed_id() -> int:
	if _feed == null:
		return -1
	return _feed.get_id()


## ID del marker attualmente tracciato, -1 se nessuno.
func get_marker_id() -> int:
	if _last_marker_id < 0:
		return -1
	if Time.get_ticks_msec() - _last_detection_msec > MAX_POSE_AGE_MSEC:
		return -1
	return _last_marker_id


func _connect_signals() -> void:
	_plugin.connect("camera_permission_granted", _on_permission_granted)
	_plugin.connect("camera_permission_denied", _on_permission_denied)
	_plugin.connect("frame_available", _on_frame)
	_plugin.connect("markers_detected", _on_markers_detected)


func _start_camera() -> void:
	_plugin.start({
		"capture_width": CAPTURE_WIDTH,
		"capture_height": CAPTURE_HEIGHT,
		"preview_width": PREVIEW_WIDTH,
		"preview_height": PREVIEW_HEIGHT,
		"preview_every_frames": PREVIEW_EVERY_FRAMES,
		"detect_every_frames": DETECT_EVERY_FRAMES,
		"marker_size": MARKER_SIZE_METERS,
		"marker_dictionary": MARKER_DICTIONARY,
	})


func _on_permission_granted() -> void:
	if _started:
		_start_camera()


func _on_permission_denied() -> void:
	push_warning("Marker: permesso fotocamera negato")


func _on_frame(frame: Dictionary) -> void:
	if _feed == null:
		_create_feed()
	var width: int = frame.get("width", 0)
	var height: int = frame.get("height", 0)
	var raw: Variant = frame.get("data", null)
	var data := PackedByteArray()
	if raw is PackedByteArray:
		data = raw
	elif raw is Array:
		data = PackedByteArray(raw)
	if width <= 0 or height <= 0 or data.size() < width * height * 4:
		return
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)
	_feed.set_rgb_image(image)
	_apply_camera_fov(frame)


func _create_feed() -> void:
	_feed = CameraFeed.new()
	_feed.set_name("MarkerAR")
	_feed.set_position(CameraFeed.FEED_BACK)
	CameraServer.add_feed(_feed)
	# set_rgb_image() aggiorna la texture solo se il feed e' attivo.
	_feed.feed_is_active = true


func _remove_feed() -> void:
	if _feed == null:
		return
	_feed.feed_is_active = false
	CameraServer.remove_feed(_feed)
	_feed = null


func _on_markers_detected(data: Dictionary) -> void:
	if int(data.get("count", 0)) <= 0:
		return
	var marker_id := int(data.get("id", -1))
	if marker_id < 0:
		return
	if not _apply_pose(data.get("pose", null)):
		return
	_last_marker_id = marker_id
	_last_detection_msec = Time.get_ticks_msec()


func _apply_pose(pose: Variant) -> bool:
	var values: PackedFloat32Array
	if pose is PackedFloat32Array:
		values = pose
	elif pose is PackedFloat64Array:
		values = PackedFloat32Array(pose)
	elif pose is Array:
		values = PackedFloat32Array(pose)
	else:
		return false
	if values.size() < 12:
		return false
	# Il plugin espone il frame del marker (X destra, Y "alto" nel piano,
	# Z normale uscente). Le esperienze (e place_cube in particolare) usano
	# la convenzione dei piani ARCore: Y = normale dell'ancora. Rimappiamo:
	#   X_ancora = X_marker, Y_ancora = Z_marker (normale), Z_ancora = -Y_marker.
	var marker_x := Vector3(values[0], values[1], values[2])
	var marker_y := Vector3(values[3], values[4], values[5])
	var marker_z := Vector3(values[6], values[7], values[8])
	var basis := Basis(marker_x, marker_z, -marker_y)
	_last_pose = Transform3D(basis, Vector3(values[9], values[10], values[11]))
	return true


## Allinea la Camera3D agli intrinsics della fotocamera (FOV verticale).
func _apply_camera_fov(frame: Dictionary) -> void:
	if _camera_fov_applied:
		return
	var fy := float(frame.get("fy", 0.0))
	var height := float(frame.get("height", 0.0))
	if fy <= 0.0 or height <= 0.0:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = rad_to_deg(2.0 * atan(height / (2.0 * fy)))
	_camera_fov_applied = true
