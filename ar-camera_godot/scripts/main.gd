extends Node3D
## Scena principale: configura l'ambiente, avvia ARSession e carica
## l'esperienza corrente, con un piccolo HUD di debug.

const PLACE_CUBE_SCENE := preload("res://scenes/minigames/place_cube.tscn")
const MARKER_BACKGROUND_DISTANCE := 9.0

@onready var _environment: Environment = $WorldEnvironment.environment
@onready var _camera: Camera3D = $Origin3D/Camera3D
@onready var _debug_label: Label = $UI/DebugLabel
@onready var _reset_button: Button = $UI/ResetButton

var _experience: Node3D
var _marker_background: MeshInstance3D = null
var _hud_timer := 0.0


func _ready() -> void:
	ARSession.start()
	_configure_environment()
	_reset_button.pressed.connect(_on_reset_pressed)
	_experience = PLACE_CUBE_SCENE.instantiate()
	$Minigames.add_child(_experience)


func _process(delta: float) -> void:
	_hud_timer -= delta
	if _hud_timer > 0.0:
		return
	_hud_timer = 0.25
	_update_hud()


func _configure_environment() -> void:
	if ARSession.is_device:
		if ARSession.get_backend_name().begins_with("Marker"):
			# Il feed RGB del backend marker non passa dal percorso camera feed
			# del renderer GL (samplerExternalOES): lo mostriamo su un quad
			# attaccato alla camera, dietro al contenuto AR.
			_environment.background_mode = Environment.BG_COLOR
			_environment.background_color = Color.BLACK
			_setup_marker_background()
		else:
			_environment.background_mode = Environment.BG_CAMERA_FEED
			_apply_camera_feed_id()
	else:
		_environment.background_mode = Environment.BG_COLOR
		_environment.background_color = Color(0.06, 0.07, 0.09)
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color.WHITE
	_environment.ambient_light_energy = 0.5
	_environment.ambient_light_sky_contribution = 0.0


func _setup_marker_background() -> void:
	if _marker_background != null:
		return
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.disable_receive_shadows = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_marker_background = MeshInstance3D.new()
	_marker_background.name = "MarkerBackground"
	_marker_background.mesh = QuadMesh.new()
	_marker_background.material_override = material
	_marker_background.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker_background.position = Vector3(0.0, 0.0, -MARKER_BACKGROUND_DISTANCE)
	_marker_background.visible = false
	_camera.add_child(_marker_background)
	_update_marker_background()


func _update_marker_background() -> void:
	if _marker_background == null:
		return
	var material := _marker_background.material_override as StandardMaterial3D
	var quad := _marker_background.mesh as QuadMesh
	if material == null or quad == null:
		return
	var texture := ARSession.get_preview_texture()
	if texture != null:
		if material.albedo_texture != texture:
			material.albedo_texture = texture
		_marker_background.visible = true
	# Copre esattamente il frustum verticale della camera (KEEP_HEIGHT).
	var height := 2.0 * tan(deg_to_rad(_camera.fov) * 0.5) * MARKER_BACKGROUND_DISTANCE
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / viewport_size.y if viewport_size.y > 0.0 else 1.0
	quad.size = Vector2(height * aspect, height)


func _apply_camera_feed_id() -> void:
	var feed_id := ARSession.get_camera_feed_id()
	if feed_id >= 0:
		_environment.background_camera_feed_id = feed_id


func _update_hud() -> void:
	_apply_camera_feed_id()
	_update_marker_background()
	var lines := PackedStringArray()
	lines.append("backend: %s" % ARSession.get_backend_name())
	if ARSession.is_available():
		lines.append("tracking: %s" % ARSession.tracking_status_name(ARSession.get_tracking_status()))
		if ARSession.get_backend_name().begins_with("Marker"):
			var marker_id := ARSession.get_marker_id()
			lines.append("marker: %s" % ("nessuno" if marker_id < 0 else str(marker_id)))
			if ARSession.arcore_availability != "":
				lines.append("arcore: %s" % _arcore_availability_text())
		else:
			lines.append("piani: %d" % ARSession.get_planes().size())
	else:
		lines.append("ARSession non disponibile")
	_debug_label.text = "\n".join(lines)


func _arcore_availability_text() -> String:
	match ARSession.arcore_availability:
		"supported_installed":
			return "installato"
		"supported_not_installed":
			return "non installato"
		"supported_apk_too_old":
			return "da aggiornare"
		"unsupported_device_not_capable":
			return "non supportato"
		"unknown":
			return "sconosciuto"
		_:
			return ARSession.arcore_availability


func _on_reset_pressed() -> void:
	if _experience != null and _experience.has_method("reset"):
		_experience.call("reset")
