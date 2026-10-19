class_name GroundSnap
extends Node3D
## Places its children on the ground (Phase 8): after the level's colliders exist, each
## child Node3D whose name does not start with "Fixed" is moved down (or up) onto the first
## world collider below SNAP_FROM metres above it, keeping its X and Z. Used for tool sites
## added to generated regions (Runewood, the new region), where the terrain height is not
## known when the scene is authored. Emits snapped once every child is placed.

signal snapped

const SNAP_FROM := 40.0
## World geometry (CombatController.WORLD_LAYER), not enemies, triggers or interactables.
const WORLD_MASK := 1

var is_snapped := false


func _ready() -> void:
	_snap.call_deferred()


func _snap() -> void:
	# Colliders of the level (and of our own children) register on the next physics frames.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	for child in get_children():
		var node := child as Node3D
		if node == null or String(node.name).begins_with("Fixed"):
			continue
		var at := node.global_position
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * SNAP_FROM, at + Vector3.DOWN * SNAP_FROM, WORLD_MASK)
		query.exclude = _own_bodies(node)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			node.global_position = Vector3(at.x, (hit["position"] as Vector3).y, at.z)
	is_snapped = true
	snapped.emit()


func _own_bodies(node: Node) -> Array[RID]:
	var rids: Array[RID] = []
	for body in node.find_children("*", "CollisionObject3D", true, false):
		rids.append((body as CollisionObject3D).get_rid())
	if node is CollisionObject3D:
		rids.append((node as CollisionObject3D).get_rid())
	return rids
