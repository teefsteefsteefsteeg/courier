extends SceneTree
## Rendered evidence for the seamless open world (GPU window, NOT --headless): the courier
## walks with held keys from Willowmere's plaza through the Whisperwood and the pass into
## Wyrmfall Vale to the waterfall, as a player would, and screenshots are taken on the way
## to docs/validation/phase8/:
##   90 plaza start         91 Whisperwood trail       92 clearing, trail on north
##   93 approaching the pass (vale hills ahead)        94 in the pass (seam)
##   95 the vale road        96 Old Stone Bridge area   97 at the waterfall (+ zoomed out)
##   98 world map (M) at the falls                     99 zoomed-out world map
## Performance while walking (real frame times) and streaming hitches are printed and
## written to docs/validation/phase8/open_world_performance.txt.
## SaveGame is removed (the player's save is never touched).
##   godot --path . --resolution 1600x900 --script res://tests/capture_phase8_open_world.gd -- <output_dir>

const L := preload("res://scripts/world/wyrmfall_layout.gd")
const VILLAGE_ROUTE := [Vector2(3.0, -3.0), Vector2(4.8, -5.2), Vector2(7.6, -9.6), Vector2(11.4, -15.6), Vector2(13.6, -18.6),
		Vector2(14.0, -24.0), Vector2(14.0, -28.6), Vector2(12.6, -36.0), Vector2(15.5, -45.0), Vector2(14.2, -53.0),
		Vector2(18.5, -62.0), Vector2(13.5, -71.0), Vector2(16.5, -80.0), Vector2(14.0, -90.0), Vector2(14.0, -98.6),
		Vector2(13.0, -104.0), Vector2(13.6, -111.0), Vector2(13.2, -117.5), Vector2(14.0, -124.0)]
## Screenshot when the courier first comes within 1.5 m of these route points (index -> file).
const SHOTS := {6: "91_whisperwood_trail.png", 15: "92_moonstone_clearing.png", 17: "93_approaching_the_pass.png",
		19: "94_in_the_pass.png", 22: "95_vale_road.png", 24: "96_towards_the_bridge.png"}

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var streamer: WorldStreamer
var out_dir: String
var problems: PackedStringArray = []
var frame_times: PackedFloat32Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "res://docs/validation/phase8"
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
	streamer = WorldStreamer.find(self)
	await _wait(40)
	player.teleport_to(Vector3(VILLAGE_ROUTE[0].x, 0.1, VILLAGE_ROUTE[0].y))
	rig.snap_to_target()
	await _wait(30)
	await _shot("90_plaza_start.png")
	var route: Array[Vector2] = []
	route.assign(VILLAGE_ROUTE)
	for i in 7:
		var w := L.to_world(L.ROAD[i])
		route.append(Vector2(w.x, w.z))
	for i in range(1, L.FALLS_PATH.size()):
		var w := L.to_world(L.FALLS_PATH[i])
		route.append(Vector2(w.x, w.z))
	var start := Time.get_ticks_msec()
	await _walk(route)
	var seconds := (Time.get_ticks_msec() - start) / 1000.0
	await _wait(20)
	await _shot("97_at_the_waterfall.png")
	rig.set_zoom(rig.max_zoom_size)
	await _wait(40)
	await _shot("97_at_the_waterfall_wide.png")
	rig.set_zoom(14.0)
	_expect(Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(L.to_world(L.POOL_CENTRE).x, L.to_world(L.POOL_CENTRE).z)) < 14.0, "reached the waterfall")
	await _key(KEY_M)
	await _wait(10)
	await _shot("98_world_map_at_the_falls.png")
	var controller := level.get_node("GameplayHUD/Minimap")
	controller.zoom_map(3.0)
	await _wait(10)
	await _shot("99_world_map_zoomed_out.png")
	await _key(KEY_M)
	# Performance.
	var sorted := frame_times.duplicate()
	sorted.sort()
	var total := 0.0
	for t in frame_times:
		total += t
	var average_ms := total / maxf(frame_times.size(), 1) * 1000.0
	var p99_ms := sorted[int(sorted.size() * 0.99)] * 1000.0 if not sorted.is_empty() else 0.0
	var worst_ms := sorted[sorted.size() - 1] * 1000.0 if not sorted.is_empty() else 0.0
	var report := "Open world walk, plaza -> Whisperwood -> pass -> Wyrmfall falls (GPU, %s, %s)\n" % [RenderingServer.get_video_adapter_name(), DisplayServer.window_get_size()]
	report += "walk time %.1f s, %d frames\n" % [seconds, frame_times.size()]
	report += "frame time: average %.2f ms (%.0f fps), 99th percentile %.2f ms, worst %.2f ms\n" % [average_ms, 1000.0 / maxf(average_ms, 0.01), p99_ms, worst_ms]
	report += "streaming: %d chunk activations, worst activation %.1f ms, last %.1f ms\n" % [streamer.activations, streamer.max_activation_ms, streamer.last_activation_ms]
	report += "active chunks at the falls: %s\n" % [streamer.get_active_ids()]
	print(report)
	var file := FileAccess.open(out_dir.path_join("open_world_performance.txt"), FileAccess.WRITE)
	file.store_string(report)
	file.close()
	print("CAPTURE problems: %d %s" % [problems.size(), problems])
	quit(problems.size())


func _walk(route: Array[Vector2]) -> void:
	var index := 0
	var stuck_time := 0.0
	var progress_at := player.global_position
	var sidestep := 0.0
	var side := 1.0
	var frames := 0
	var shot_done := {}
	Input.action_press(&"run")
	while index < route.size():
		var here := Vector2(player.global_position.x, player.global_position.z)
		var target: Vector2 = route[index]
		if here.distance_to(target) < 1.3:
			if SHOTS.has(index) and not shot_done.has(index):
				shot_done[index] = true
				_release_moves()
				await _wait(3)
				await _shot(SHOTS[index])
			index += 1
			continue
		var direction := (target - here).normalized()
		if sidestep > 0.0:
			direction = (direction + Vector2(-direction.y, direction.x) * side * 1.5).normalized()
			sidestep -= player.get_process_delta_time()
		_hold_towards(direction)
		await process_frame
		frame_times.append(player.get_process_delta_time())
		frames += 1
		stuck_time += player.get_process_delta_time()
		if stuck_time >= 1.0:
			if player.global_position.distance_to(progress_at) < 0.6:
				sidestep = 0.5
				side = -side
			progress_at = player.global_position
			stuck_time = 0.0
		if frames > 60 * 180:
			_expect(false, "walk stuck near %s" % here)
			break
	_release_moves()
	Input.action_release(&"run")


func _hold_towards(direction: Vector2) -> void:
	var camera := get_root().get_camera_3d()
	var forward := Vector2(-camera.global_basis.z.x, -camera.global_basis.z.z).normalized()
	var right := Vector2(camera.global_basis.x.x, camera.global_basis.x.z).normalized()
	var best := [1, 0]
	var best_dot := -INF
	for f: int in [-1, 0, 1]:
		for r: int in [-1, 0, 1]:
			if f == 0 and r == 0:
				continue
			var d := (forward * f + right * r).normalized()
			if d.dot(direction) > best_dot:
				best_dot = d.dot(direction)
				best = [f, r]
	for pair: Array in [[&"move_forward", best[0] == 1], [&"move_back", best[0] == -1], [&"move_right", best[1] == 1], [&"move_left", best[1] == -1]]:
		if pair[1]:
			Input.action_press(pair[0])
		else:
			Input.action_release(pair[0])


func _release_moves() -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right"]:
		Input.action_release(action)


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


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _expect(condition: bool, label: String) -> void:
	if not condition:
		problems.append(label)
		printerr("PROBLEM: ", label)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(file)
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
