extends SceneTree
## Renders Phase 8 Wyrmfall Vale in the real game (GPU window, NOT --headless): the gate on
## Willowmere's south edge, the real E key into the vale, its landmarks (arrival, the falls
## and pool, the river and the Old Stone Bridge, the fisher's camp, the ruins, the cliffs),
## walking over the bridge with real keys, the M map, and the real E key back through the
## gate to Willowmere. SaveGame is removed and UISettings does not persist.
##   godot --path . --resolution 1600x900 --script res://tests/capture_phase8_wyrmfall.gd -- <output_dir>

const L := preload("res://scripts/world/wyrmfall_layout.gd")

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var router: Node
var out_dir: String
var problems: PackedStringArray = []
var shot_index := 46


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/phase8")
	DirAccess.make_dir_recursive_absolute(out_dir)
	UISettings.persist = false
	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	for node in level.find_children("*", "SaveGame", true, false):
		node.get_parent().remove_child(node)
		node.free()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	rig.set_process_unhandled_input(false)
	router = get_first_node_in_group(&"phase6_router")
	await _seconds(1.0)

	# The gate on the village's south edge.
	var gate := level.get_node("WyrmfallGate") as RegionGate
	player.teleport_to(gate.get_exit_point() + Vector3.UP * 0.2)
	rig.set_zoom(12.0)
	rig.snap_to_target()
	for i in 40:
		await physics_frame
		if player.interaction.focused == gate.interactable:
			break
	await _seconds(0.4)
	_expect(player.interaction.focused == gate.interactable, "the village gate takes focus")
	await _shot("wyrmfall_village_gate")
	await _key(KEY_E)
	await _wait_region(&"wyrmfall")
	_expect(router.get(&"region_id") == &"wyrmfall", "E at the gate enters Wyrmfall Vale")
	await _seconds(0.8)
	await _shot("wyrmfall_arrival")

	# Landmarks, from a wider camera.
	await _view(L.POOL_CENTRE + Vector2(-4.0, 10.0), 26.0, "wyrmfall_falls")
	await _view(Vector2(-14.0, -12.5), 18.0, "wyrmfall_falls_close")
	await _view(L.bridge_point() + Vector2(-2.0, 3.0), 18.0, "wyrmfall_bridge")
	await _view(L.CAMP_CENTRE + Vector2(0.0, 2.0), 16.0, "wyrmfall_camp")
	await _view(L.RUINS_CENTRE + Vector2(2.0, 3.0), 16.0, "wyrmfall_ruins")
	await _view(L.CLIFF_END + Vector2(-2.0, 4.0), 18.0, "wyrmfall_cliffs")
	await _view(Vector2(0.0, 6.0), 44.0, "wyrmfall_overview")

	# Walk over the bridge with the real keys.
	var along := L.bridge_direction()
	var start := L.bridge_point() - along * 7.0
	player.teleport_to(Vector3(start.x, _ground(start) + 0.3, start.y))
	rig.set_zoom(14.0)
	rig.camera.size = 14.0
	rig.snap_to_target()
	await _seconds(0.5)
	var held := _hold_towards(along)
	await _seconds(1.6)
	await _shot("wyrmfall_crossing_bridge")
	await _seconds(1.6)
	_release(held)
	await _seconds(0.3)
	var crossed := Vector2(player.global_position.x, player.global_position.z) - L.bridge_point()
	_expect(crossed.dot(along) > 4.0, "walked across the bridge (%.1f m past its middle)" % crossed.dot(along))

	# The map.
	await _key(KEY_M)
	await _seconds(0.5)
	await _shot("wyrmfall_map")
	await _key(KEY_M)
	await _seconds(0.3)

	# Back home through the gate.
	var back := (router.get(&"active_level") as Node).get_node("ReturnGate") as RegionGate
	player.teleport_to(back.interactable.global_position + Vector3.UP * 0.2)
	rig.camera.size = 12.0
	rig.snap_to_target()
	for i in 40:
		await physics_frame
		if player.interaction.focused == back.interactable:
			break
	await _seconds(0.3)
	_expect(player.interaction.focused == back.interactable, "the return gate takes focus")
	await _shot("wyrmfall_return_gate")
	await _key(KEY_E)
	await _wait_region(&"village")
	await _seconds(0.6)
	var distance := player.global_position.distance_to(gate.get_exit_point())
	_expect(router.get(&"region_id") == &"village" and distance < 1.0, "back in Willowmere at the gate (%.2f m)" % distance)
	await _shot("wyrmfall_back_in_village")

	print("problems: ", problems.size())
	for problem in problems:
		print("  - ", problem)
	quit(problems.size())


func _ground(p: Vector2) -> float:
	var space := (router.get(&"active_level") as Node3D).get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, 40.0, p.y), Vector3(p.x, -10.0, p.y), 1))
	return (hit["position"] as Vector3).y if not hit.is_empty() else 0.0


func _view(at: Vector2, size: float, name: String) -> void:
	player.teleport_to(Vector3(at.x, _ground(at) + 0.3, at.y))
	rig.max_zoom_size = 60.0
	rig.set_zoom(size)
	rig.camera.size = size
	rig.snap_to_target()
	await _seconds(0.8)
	await _shot(name)


func _hold_towards(direction: Vector2) -> Array[StringName]:
	# Movement is camera-relative.
	var basis := rig.camera.global_basis
	var forward := Vector2(-basis.z.x, -basis.z.z).normalized()
	var right := Vector2(basis.x.x, basis.x.z).normalized()
	var actions: Array[StringName] = []
	var f := direction.dot(forward)
	var r := direction.dot(right)
	if f > 0.35: actions.append(&"move_forward")
	if f < -0.35: actions.append(&"move_back")
	if r > 0.35: actions.append(&"move_right")
	if r < -0.35: actions.append(&"move_left")
	for action in actions:
		Input.action_press(action)
	return actions


func _release(actions: Array[StringName]) -> void:
	for action in actions:
		Input.action_release(action)


func _wait_region(region: StringName) -> void:
	for i in 120:
		await physics_frame
		if router.get(&"region_id") == region and not router.get(&"crossing"):
			break


func _expect(condition: bool, label: String) -> void:
	print(("  ok    " if condition else "  PROBLEM ") + label)
	if not condition:
		problems.append(label)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await physics_frame
		await process_frame


func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join("%d_%s.png" % [shot_index, name])
	shot_index += 1
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
