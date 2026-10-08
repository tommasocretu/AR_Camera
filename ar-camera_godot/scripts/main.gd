extends Node3D
## Scena principale: configura l'ambiente, avvia ARSession e carica
## l'esperienza corrente, con un piccolo HUD di debug.

const PLACE_CUBE_SCENE := preload("res://scenes/minigames/place_cube.tscn")

@onready var _environment: Environment = $WorldEnvironment.environment
@onready var _debug_label: Label = $UI/DebugLabel
@onready var _reset_button: Button = $UI/ResetButton

var _experience: Node3D
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
		_environment.background_mode = Environment.BG_CAMERA_FEED
		_apply_camera_feed_id()
	else:
		_environment.background_mode = Environment.BG_COLOR
		_environment.background_color = Color(0.06, 0.07, 0.09)
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color.WHITE
	_environment.ambient_light_energy = 0.5
	_environment.ambient_light_sky_contribution = 0.0


func _apply_camera_feed_id() -> void:
	var feed_id := ARSession.get_camera_feed_id()
	if feed_id >= 0:
		_environment.background_camera_feed_id = feed_id


func _update_hud() -> void:
	_apply_camera_feed_id()
	var lines := PackedStringArray()
	lines.append("backend: %s" % ARSession.get_backend_name())
	if ARSession.is_available():
		lines.append("tracking: %s" % ARSession.tracking_status_name(ARSession.get_tracking_status()))
		lines.append("piani: %d" % ARSession.get_planes().size())
	else:
		lines.append("ARSession non disponibile")
	_debug_label.text = "\n".join(lines)


func _on_reset_pressed() -> void:
	if _experience != null and _experience.has_method("reset"):
		_experience.call("reset")
