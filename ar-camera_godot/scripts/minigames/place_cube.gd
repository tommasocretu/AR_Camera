extends Node3D
## Esperienza AR: piazza cubi sul pavimento rilevato.
##
## Il reticolo segue il punto di impatto del raggio AR; un tap/click piazza
## un cubo ancorato al mondo nel punto puntato.

const CUBE_SIZE := 0.15
const CUBE_COLOR := Color(0.91, 0.36, 0.18)
const MAX_CUBES := 24
const PLANE_REFRESH_SECONDS := 0.25

@onready var _reticle: MeshInstance3D = $Reticle
@onready var _ghost: MeshInstance3D = $Ghost
@onready var _placed_cubes: Node3D = $PlacedCubes
@onready var _plane_visuals: MeshInstance3D = $PlaneVisuals

var _cube_mesh: BoxMesh
var _hit_transform := Transform3D.IDENTITY
var _plane_timer := 0.0


func _ready() -> void:
	_build_visuals()


func _process(delta: float) -> void:
	if not ARSession.is_available():
		return

	_update_aim()

	_plane_timer -= delta
	if _plane_timer <= 0.0:
		_plane_timer = PLANE_REFRESH_SECONDS
		_update_plane_visuals()


## Rimuove tutti i cubi piazzati.
func reset() -> void:
	for cube in _placed_cubes.get_children():
		cube.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	var position := Vector2.ZERO
	var should_place := false
	if event is InputEventScreenTouch:
		should_place = event.pressed
		position = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		should_place = event.pressed
		position = event.position
	if not should_place:
		return
	var result := ARSession.raycast_screen(ARSession.get_pointer_position(position))
	if result["hit"]:
		_place_cube(result["transform"])
		get_viewport().set_input_as_handled()


func _build_visuals() -> void:
	_cube_mesh = BoxMesh.new()
	_cube_mesh.size = Vector3.ONE * CUBE_SIZE

	var reticle_mesh := TorusMesh.new()
	reticle_mesh.inner_radius = 0.045
	reticle_mesh.outer_radius = 0.055
	reticle_mesh.rings = 24
	reticle_mesh.ring_segments = 8
	_reticle.mesh = reticle_mesh
	_reticle.material_override = _make_material(Color(0.2, 0.75, 1.0, 0.9), true)
	_reticle.visible = false

	_ghost.mesh = _cube_mesh
	_ghost.material_override = _make_material(Color(CUBE_COLOR.r, CUBE_COLOR.g, CUBE_COLOR.b, 0.35), true)
	_ghost.visible = false

	_plane_visuals.material_override = _make_material(Color(0.35, 0.95, 0.75, 0.8), true)


func _update_aim() -> void:
	var result := ARSession.raycast_screen(ARSession.get_aim_position())
	if not result["hit"]:
		_reticle.visible = false
		_ghost.visible = false
		return
	_hit_transform = result["transform"]
	var point: Vector3 = _hit_transform.origin
	_reticle.global_position = point + Vector3(0.0, 0.003, 0.0)
	_ghost.global_transform = Transform3D(
			_hit_transform.basis, point + Vector3(0.0, CUBE_SIZE * 0.5, 0.0))
	_reticle.visible = true
	_ghost.visible = true


func _update_plane_visuals() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var has_lines := false
	for plane in ARSession.get_planes():
		var boundary: PackedVector3Array = plane.get("boundary", PackedVector3Array())
		if boundary.size() < 2:
			continue
		var base: Transform3D = plane["transform"]
		for i in boundary.size():
			var a := base * boundary[i]
			var b := base * boundary[(i + 1) % boundary.size()]
			mesh.surface_add_vertex(a)
			mesh.surface_add_vertex(b)
			has_lines = true
	if has_lines:
		mesh.surface_end()
		_plane_visuals.mesh = mesh
	else:
		_plane_visuals.mesh = null


func _place_cube(world_transform: Transform3D) -> void:
	if _placed_cubes.get_child_count() >= MAX_CUBES:
		var oldest := _placed_cubes.get_child(0)
		_placed_cubes.remove_child(oldest)
		oldest.queue_free()

	var cube := MeshInstance3D.new()
	cube.mesh = _cube_mesh
	cube.material_override = _make_material(CUBE_COLOR, false)

	var shadow := MeshInstance3D.new()
	var shadow_quad := QuadMesh.new()
	shadow_quad.size = Vector2(CUBE_SIZE * 1.5, CUBE_SIZE * 1.5)
	shadow.mesh = shadow_quad
	shadow.material_override = _make_material(Color(0.0, 0.0, 0.0, 0.28), true)
	shadow.rotate_x(-PI * 0.5)
	shadow.position = Vector3(0.0, -CUBE_SIZE * 0.5 + 0.002, 0.0)
	cube.add_child(shadow)

	_placed_cubes.add_child(cube)
	var placed := world_transform
	placed.origin += Vector3(0.0, CUBE_SIZE * 0.5, 0.0)
	ARSession.attach_to_world(cube, placed)


func _make_material(color: Color, unshaded: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
