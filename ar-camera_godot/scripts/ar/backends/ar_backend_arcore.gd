extends ARBackend
## Backend ARCore: adapter verso il plugin godot_arcore vendorizzato.
##
## Usa due componenti del plugin:
##  - il singleton Android "ARCorePlugin" (lato Java/Kotlin) che inizializza
##    l'ambiente ARCore;
##  - l'autoload "ARCoreInterfaceInstance" (lato GDScript) che registra
##    l'interfaccia XR ed espone raycast e piani.

const NOT_TRACKING := 4


func get_kind() -> Kind:
	return Kind.ARCORE


func get_backend_name() -> String:
	return "ARCore"


func start() -> void:
	var android_plugin: Object = Engine.get_singleton("ARCorePlugin")
	if android_plugin != null:
		android_plugin.initializeEnvironment()

	var iface := _interface()
	if iface == null:
		push_error("ARCore: autoload ARCoreInterfaceInstance non disponibile")
		return

	iface.enable_horizontal_plane_detection(true)
	iface.enable_vertical_plane_detection(false)
	iface.start()


func stop() -> void:
	var android_plugin: Object = Engine.get_singleton("ARCorePlugin")
	if android_plugin != null:
		android_plugin.uninitializeEnvironment()


func get_tracking_status() -> int:
	var iface := _interface()
	if iface == null:
		return NOT_TRACKING
	var status: Variant = iface.get_tracking_status()
	if status == null:
		return NOT_TRACKING
	return int(status)


func get_planes() -> Array:
	var iface := _interface()
	if iface == null or iface.arcore_interface == null:
		return []
	var planes: Array = []
	for id in iface.plane_tracker_get_all_plane_ids():
		planes.append({
			"id": id,
			"transform": iface.plane_tracker_get_plane_transform(id),
			"boundary": iface.plane_tracker_get_plane_boundary(id),
		})
	return planes


func raycast_screen(position: Vector2) -> Dictionary:
	var iface := _interface()
	if iface == null or iface.arcore_interface == null:
		return {"hit": false, "transform": Transform3D.IDENTITY}
	var result: Transform3D = iface.screenRayCast(position.x, position.y)
	# ARCore restituisce una trasformazione con origine zero quando non c'e' hit.
	var hit := result.origin.length_squared() > 0.0001
	return {"hit": hit, "transform": result}


func get_camera_feed_id() -> int:
	var iface := _interface()
	if iface == null or iface.arcore_interface == null:
		return -1
	var feed: CameraFeed = iface.get_camera_feed()
	if feed == null:
		return -1
	return feed.get_id()


func _interface() -> Node:
	return get_node_or_null("/root/ARCoreInterfaceInstance")
