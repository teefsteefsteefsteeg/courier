class_name WorldStreamer
extends Node3D
## Seamless open-world streaming (Phase 8). The village scene (Willowmere and the
## Whisperwood) is the always-present home area; every other outdoor biome is cut by its
## generator into WorldChunks (scenes whose roots carry their own world transform, listed in
## WorldChunkSets). This node keeps the chunks near the courier in the tree:
##   - a chunk within load_distance of the focus (the courier, or focus_override, e.g. the
##     dragon in flight) starts loading on a background thread (ResourceLoader threaded
##     requests), and its instance is added under this node when ready, at most one per
##     frame, so there is no loading screen and no teleport at a biome boundary
##   - the focus is extended ahead by its velocity x lookahead_seconds, and extra_distance
##     can grow the radius (fast flight), so chunks are in place before they come into view
##   - a chunk beyond unload_distance (hysteresis) is parked: removed from the tree but kept,
##     so trees felled, ore mined, enemies and their health stay as they were
##   - if the focus stands on a chunk that is not loaded yet (teleport, fast travel), that
##     chunk is loaded at once (blocking) so nothing falls through the ground;
##     prepare_at() does the same for a destination before a teleport
##   - always_loaded chunks (landmarks, water) stay in the tree
## Chunks never change what other systems see: everything in them is ordinary nodes in the
## level once active (WorldLocations, tool sites, enemies, colliders).

signal chunk_activated(chunk_id: StringName)
signal chunk_parked(chunk_id: StringName)

const GROUP := &"world_streamer"
enum State { UNLOADED, LOADING, ACTIVE, PARKED }

@export var chunk_sets: Array[WorldChunkSet] = []
## Load chunks whose ground lies within this distance of the focus.
@export_range(10.0, 500.0, 1.0, "suffix:m") var load_distance: float = 70.0
## Park chunks beyond this distance (larger than load_distance, so nothing flickers).
@export_range(10.0, 800.0, 1.0, "suffix:m") var unload_distance: float = 110.0
## Seconds of the focus's current velocity to look ahead.
@export_range(0.0, 10.0, 0.1, "suffix:s") var lookahead_seconds: float = 2.0
## Added to both distances (raised while flying).
@export var extra_distance: float = 0.0
@export_range(0.05, 2.0, 0.05, "suffix:s") var scan_interval: float = 0.2
@export var enabled: bool = true

## Followed instead of the courier when set (the dragon while flying).
var focus_override: Node3D = null
## chunk_id -> {"chunk": WorldChunk, "state": State, "node": Node3D}
var entries: Dictionary[StringName, Dictionary] = {}
## Longest single chunk activation (instantiate + add), ms: the worst hitch streaming caused.
var max_activation_ms: float = 0.0
var last_activation_ms: float = 0.0
var activations: int = 0
var _scan_left: float = 0.0
var _last_focus := Vector3.INF
var _velocity := Vector3.ZERO
var _queue: Array[StringName] = []


static func find(tree: SceneTree) -> WorldStreamer:
	return tree.get_first_node_in_group(GROUP) as WorldStreamer if tree != null else null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	for chunk_set in chunk_sets:
		if chunk_set == null:
			continue
		for chunk in chunk_set.chunks:
			if chunk != null and chunk.chunk_id != &"":
				entries[chunk.chunk_id] = {"chunk": chunk, "state": State.UNLOADED, "node": null}
	# What is under and around the starting point is there before the first frame.
	_update(true)


func _process(delta: float) -> void:
	if not enabled:
		return
	var focus := get_focus()
	if focus != null:
		var at := focus.global_position
		if _last_focus.is_finite() and delta > 0.0:
			var step := (at - _last_focus) / delta
			# A teleport is not a velocity.
			_velocity = _velocity.lerp(step, 0.2) if step.length() < 80.0 else Vector3.ZERO
		_last_focus = at
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = scan_interval
		_update(false)
	_poll_loading()
	# One activation per frame keeps any hitch to a single chunk.
	if not _queue.is_empty():
		_activate(_queue.pop_front())


## The node streaming follows: focus_override, else the courier.
func get_focus() -> Node3D:
	if focus_override != null and is_instance_valid(focus_override) and focus_override.is_inside_tree():
		return focus_override
	return get_tree().get_first_node_in_group(CombatController.PLAYER_GROUP) as Node3D if is_inside_tree() else null


func get_state(chunk_id: StringName) -> State:
	return entries[chunk_id]["state"] if entries.has(chunk_id) else State.UNLOADED


func is_active(chunk_id: StringName) -> bool:
	return get_state(chunk_id) == State.ACTIVE


func get_chunk_node(chunk_id: StringName) -> Node3D:
	return entries[chunk_id]["node"] if entries.has(chunk_id) else null


## Chunk ids whose ground contains the world X/Z point.
func chunks_at(point: Vector2) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in entries:
		if (entries[id]["chunk"] as WorldChunk).bounds.has_point(point):
			out.append(id)
	return out


func get_active_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in entries:
		if entries[id]["state"] == State.ACTIVE:
			out.append(id)
	return out


## Loads (blocking) everything a point needs before something is put there: every chunk
## within load_distance of it. Use right before teleporting: chunks far from the focus are
## parked again by the next scan if nothing moves there.
func prepare_at(world_position: Vector3) -> void:
	var point := Vector2(world_position.x, world_position.z)
	for id in entries:
		var chunk: WorldChunk = entries[id]["chunk"]
		if chunk.always_loaded or chunk.distance_to(point) <= load_distance + extra_distance:
			_activate(id)


func _update(blocking: bool) -> void:
	var focus := get_focus()
	if focus == null:
		# Nothing to follow yet: the always-loaded chunks only.
		for id in entries:
			if (entries[id]["chunk"] as WorldChunk).always_loaded:
				_want(id, blocking)
		return
	var here := Vector2(focus.global_position.x, focus.global_position.z)
	var ahead := here + Vector2(_velocity.x, _velocity.z) * lookahead_seconds
	var load := load_distance + extra_distance
	var unload := unload_distance + extra_distance
	for id in entries:
		var chunk: WorldChunk = entries[id]["chunk"]
		var near := minf(chunk.distance_to(here), chunk.distance_to(ahead))
		if chunk.always_loaded or near <= load:
			# Standing on it: no waiting for the thread.
			_want(id, blocking or chunk.distance_to(here) < 0.5)
		elif near > unload and entries[id]["state"] == State.ACTIVE:
			_park(id)


func _want(chunk_id: StringName, blocking: bool) -> void:
	var entry := entries[chunk_id]
	match entry["state"]:
		State.ACTIVE:
			return
		State.PARKED:
			if blocking:
				_activate(chunk_id)
			elif not _queue.has(chunk_id):
				_queue.append(chunk_id)
		State.UNLOADED, State.LOADING:
			if blocking:
				_activate(chunk_id)
				return
			if entry["state"] == State.UNLOADED:
				var path: String = (entry["chunk"] as WorldChunk).scene_path
				if ResourceLoader.load_threaded_request(path, "PackedScene", true) == OK:
					entry["state"] = State.LOADING
				else:
					_activate(chunk_id)


func _poll_loading() -> void:
	for id in entries:
		var entry := entries[id]
		if entry["state"] != State.LOADING or _queue.has(id):
			continue
		var status := ResourceLoader.load_threaded_get_status((entry["chunk"] as WorldChunk).scene_path)
		if status == ResourceLoader.THREAD_LOAD_LOADED or status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_queue.append(id)


## Puts a chunk in the tree now (instancing it the first time; blocking if still loading).
func _activate(chunk_id: StringName) -> void:
	var entry := entries[chunk_id]
	if entry["state"] == State.ACTIVE:
		return
	_queue.erase(chunk_id)
	var started := Time.get_ticks_usec()
	var node: Node3D = entry["node"]
	if node == null:
		var chunk: WorldChunk = entry["chunk"]
		var scene: PackedScene = null
		if entry["state"] == State.LOADING:
			scene = ResourceLoader.load_threaded_get(chunk.scene_path) as PackedScene
		if scene == null:
			scene = load(chunk.scene_path) as PackedScene
		if scene == null:
			push_warning("WorldStreamer: cannot load chunk %s (%s)" % [chunk_id, chunk.scene_path])
			entry["state"] = State.UNLOADED
			return
		node = scene.instantiate() as Node3D
		node.name = String(chunk_id)
		entry["node"] = node
	add_child(node)
	entry["state"] = State.ACTIVE
	last_activation_ms = (Time.get_ticks_usec() - started) / 1000.0
	max_activation_ms = maxf(max_activation_ms, last_activation_ms)
	activations += 1
	chunk_activated.emit(chunk_id)


## Takes a far chunk out of the tree, keeping the instance (and so its state).
func _park(chunk_id: StringName) -> void:
	var entry := entries[chunk_id]
	var node: Node3D = entry["node"]
	if node != null and node.get_parent() == self:
		remove_child(node)
	entry["state"] = State.PARKED
	chunk_parked.emit(chunk_id)


func _notification(what: int) -> void:
	# Parked chunks are not children: free them with the streamer (not merely when it leaves
	# the tree, e.g. while the router has the village out for an interior).
	if what == NOTIFICATION_PREDELETE:
		for id in entries:
			var node: Node3D = entries[id]["node"]
			if node != null and is_instance_valid(node) and node.get_parent() == null:
				node.free()
