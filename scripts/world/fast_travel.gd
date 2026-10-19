class_name FastTravel
extends Node
## Moves the courier between activated teleport portals, in GameplayServices. One trip:
## input and attacks off, a short fade to the portal colour, the courier placed on a safe
## spot in front of the destination portal (checked against collision, nudged outward if
## blocked), velocity / dash / swing cleared, the camera snapped, fade back in, input back
## on. Health, shield, stamina, inventory, equipment and quests are untouched.
##
## A trip is refused (with a reason) for an unknown, inactive or same portal, or while
## another trip is running, so it cannot be spammed or looped. The destination portal
## ignores interaction for a moment after arrival.

signal travel_started(from_id: StringName, to_id: StringName)
signal travel_finished(to_id: StringName)
signal travel_refused(reason: StringName)

const GROUP := &"fast_travel"
const FADE_COLOR := Color(0.12, 0.06, 0.24)
## Capsule matching the courier's collider, used to test landing spots.
const COURIER_RADIUS := 0.35
const COURIER_HEIGHT := 1.6

@export_range(0.05, 2.0, 0.05, "suffix:s") var fade_out_time: float = 0.35
@export_range(0.05, 2.0, 0.05, "suffix:s") var fade_in_time: float = 0.45

var travelling := false
var _overlay: ColorRect


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.name = "FadeLayer"
	layer.layer = 30
	add_child(layer)
	_overlay = ColorRect.new()
	_overlay.name = "Fade"
	_overlay.color = Color(FADE_COLOR, 0.0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_overlay)


static func find(tree: SceneTree) -> FastTravel:
	return tree.get_first_node_in_group(GROUP) as FastTravel


## Why a trip from from_id to to_id is not possible (&"" when it is).
func check(from_id: StringName, to_id: StringName) -> StringName:
	var service := ExplorationService.find(get_tree())
	if travelling:
		return &"busy"
	if service == null:
		return &"no_service"
	if to_id == from_id:
		return &"same_portal"
	var target := TeleportPortal.find(get_tree(), to_id)
	if target == null:
		return &"unknown_portal"
	if not service.is_portal_active(to_id) or not service.is_portal_active(from_id):
		return &"inactive"
	return &""


## Starts a trip; returns false (and emits travel_refused) when check() refuses it.
func travel(from_id: StringName, to_id: StringName) -> bool:
	var reason := check(from_id, to_id)
	if reason != &"":
		travel_refused.emit(reason)
		return false
	_run_trip.call_deferred(from_id, to_id)
	travelling = true
	return true


func _run_trip(from_id: StringName, to_id: StringName) -> void:
	var player := get_tree().get_first_node_in_group(CombatController.PLAYER_GROUP) as PlayerController
	var target := TeleportPortal.find(get_tree(), to_id)
	if player == null or target == null:
		travelling = false
		travel_refused.emit(&"unknown_portal")
		return
	travel_started.emit(from_id, to_id)
	player.input_enabled = false
	var combat := CombatController.find_on(player)
	if combat != null:
		combat.input_enabled = false
	var fade := create_tween()
	fade.tween_property(_overlay, ^"color:a", 1.0, fade_out_time)
	await fade.finished
	var landing := safe_landing(target.get_arrival_position(), player)
	player.teleport_to(landing)
	player.velocity = Vector3.ZERO
	if combat != null:
		combat.cancel_dash()
		combat.cancel_melee()
	target.lock_arrival()
	for rig in get_tree().root.find_children("*", "IsoCameraRig", true, false):
		(rig as IsoCameraRig).snap_to_target()
	await get_tree().physics_frame
	var back := create_tween()
	back.tween_property(_overlay, ^"color:a", 0.0, fade_in_time)
	await back.finished
	player.input_enabled = true
	if combat != null:
		combat.input_enabled = true
	travelling = false
	travel_finished.emit(to_id)


## A spot near `wanted` where the courier's capsule touches no solid collider: wanted
## itself if free, else the first free point on rings around it (up to 3 m out).
func safe_landing(wanted: Vector3, player: CollisionObject3D = null) -> Vector3:
	var space := (player.get_world_3d() if player != null else get_viewport().world_3d).direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = COURIER_RADIUS
	capsule.height = COURIER_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = player.collision_mask if player != null else 5
	query.collide_with_areas = false
	if player != null:
		query.exclude = [player.get_rid()]
	for ring: float in [0.0, 0.75, 1.5, 2.25, 3.0]:
		var steps := 1 if ring == 0.0 else 12
		for i in steps:
			var offset := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(i) / float(steps)) * ring
			var at := Vector3(wanted.x + offset.x, 0.0, wanted.z + offset.z)
			query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * (COURIER_HEIGHT * 0.5 + 0.05))
			if space.intersect_shape(query, 1).is_empty():
				return at
	return Vector3(wanted.x, 0.0, wanted.z)
