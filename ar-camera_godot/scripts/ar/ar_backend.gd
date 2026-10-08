class_name ARBackend
extends Node
## Interfaccia comune dei backend AR.
##
## Il gioco non usa mai direttamente un backend: parla solo con l'autoload
## [ARSession]. Ogni backend concreto (ARCore su device, simulazione su
## desktop) implementa i metodi di questa classe.

enum Kind { NONE, ARCORE, SIMULATED }


func get_kind() -> Kind:
	return Kind.NONE


func get_backend_name() -> String:
	return "none"


## Avvia la sessione AR (no-op per i backend che non ne hanno bisogno).
func start() -> void:
	pass


func stop() -> void:
	pass


## Posizione in coordinate schermo dove punta il reticolo di puntamento.
func get_aim_position() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5


## Converte la posizione di un input (tap/click) in coordinate schermo.
func get_pointer_position(event_position: Vector2) -> Vector2:
	return event_position


## Stato di tracking come int, valori di XRInterface.TrackingStatus
## (1 = tracking normale, 4 = non tracciato).
func get_tracking_status() -> int:
	return 4


## Piani rilevati: Array di Dictionary con chiavi "id", "transform", "boundary".
func get_planes() -> Array:
	return []


## Raycast dalla posizione schermo verso il mondo.
## Ritorna un Dictionary: {"hit": bool, "transform": Transform3D}.
func raycast_screen(_position: Vector2) -> Dictionary:
	return {"hit": false, "transform": Transform3D.IDENTITY}


## Aggancia il nodo alla trasformazione nel mondo. Il backend reale potra'
## raffinare in futuro con ancore native; la simulazione posiziona e basta.
func attach_to_world(node: Node3D, world_transform: Transform3D) -> void:
	node.global_transform = world_transform


## ID del feed camera da usare come sfondo (Environment.background_camera_feed_id),
## -1 se non disponibile.
func get_camera_feed_id() -> int:
	return -1
