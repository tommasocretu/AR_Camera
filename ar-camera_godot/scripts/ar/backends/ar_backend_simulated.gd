extends ARBackend
## Backend di simulazione: piano orizzontale a y = 0 e camera orbitale.
## Serve per sviluppare e testare i minigiochi dall'editor desktop.
##
## Comandi: tasto destro trascinato = orbita, rotella = zoom,
## click sinistro = tap (piazza gli oggetti).

const PLANE_ID := 0
const GROUND_EXTENT := 8.0

var _yaw := -0.6
var _pitch := -1.0
var _distance := 3.5
var _orbiting := false


func get_kind() -> Kind:
	return Kind.SIMULATED


func get_backend_name() -> String:
	return "Simulated"


func _ready() -> void:
	_add_ground_reference()
	_update_camera()


func get_tracking_status() -> int:
	return 1 # XR_NORMAL_TRACKING


func get_aim_position() -> Vector2:
	return get_viewport().get_mouse_position()


func get_planes() -> Array:
	return [{
		"id": PLANE_ID,
		"transform": Transform3D.IDENTITY,
		"boundary": PackedVector3Array(),
	}]


func raycast_screen(position: Vector2) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {"hit": false, "transform": Transform3D.IDENTITY}
	var origin := camera.project_ray_origin(position)
	var direction := camera.project_ray_normal(position)
	if absf(direction.y) < 0.0001:
		return {"hit": false, "transform": Transform3D.IDENTITY}
	var distance := -origin.y / direction.y
	if distance <= 0.0:
		return {"hit": false, "transform": Transform3D.IDENTITY}
	var point := origin + direction * distance
	return {"hit": true, "transform": Transform3D(Basis.IDENTITY, point)}


func _add_ground_reference() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "SimulatedGround"
	ground.mesh = _build_grid_mesh()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.45, 0.5, 0.55, 0.55)
	ground.material_override = material
	add_child(ground)


func _build_grid_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var half := GROUND_EXTENT * 0.5
	var steps := 8
	for i in steps + 1:
		var offset := -half + GROUND_EXTENT * float(i) / float(steps)
		mesh.surface_add_vertex(Vector3(offset, 0.0, -half))
		mesh.surface_add_vertex(Vector3(offset, 0.0, half))
		mesh.surface_add_vertex(Vector3(-half, 0.0, offset))
		mesh.surface_add_vertex(Vector3(half, 0.0, offset))
	mesh.surface_end()
	return mesh


func _update_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye := Basis.from_euler(Vector3(_pitch, _yaw, 0.0)) * Vector3(0.0, 0.0, _distance)
	camera.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(Vector3.ZERO, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _orbiting:
		_yaw -= event.relative.x * 0.01
		_pitch = clampf(_pitch - event.relative.y * 0.01, -1.45, -0.2)
		_update_camera()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_distance = maxf(1.2, _distance - 0.35)
				_update_camera()
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_distance = minf(8.0, _distance + 0.35)
				_update_camera()
