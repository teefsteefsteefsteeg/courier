extends RefCounted
## Shared marker registry for the Phase 4 minimap. One model can feed several
## MinimapViews (the compact corner map and the expanded M map).
##
## A marker follows either a Node3D (read every frame, so moving NPCs/enemies
## track themselves) or a fixed world position. Freed nodes are dropped
## automatically by prune().
##
## Marker kinds (style comes from the view):
##   player     the courier, drawn as a heading arrow (use set_player())
##   objective  quest target; pinned to the map edge when out of range
##   npc        friendly character
##   enemy      hostile; defeated enemies can be dimmed with set_marker_state()
##   poi        any other point of interest

signal markers_changed

const KIND_PLAYER := &"player"
const KIND_OBJECTIVE := &"objective"
const KIND_NPC := &"npc"
const KIND_ENEMY := &"enemy"
const KIND_POI := &"poi"
const KINDS: Array[StringName] = [KIND_PLAYER, KIND_OBJECTIVE, KIND_NPC, KIND_ENEMY, KIND_POI]
const STATE_NORMAL := &"normal"
const STATE_DEFEATED := &"defeated"
const STATE_COMPLETE := &"complete"
const PLAYER_ID := &"__player"

## id (StringName) -> {id, kind, node, position, label, color, visible, pin, state}
var markers: Dictionary = {}
var route_points := PackedVector3Array()  ## world space

var _player_heading := Vector3(0, 0, -1)
var _player_last := Vector3.INF


# --- markers -------------------------------------------------------------------

## target is a Node3D (tracked) or a Vector3 (fixed). options keys, all optional:
##   label: String, color: Color (overrides the kind colour), pin: bool (stay on
##   the map edge when out of range; default true for objectives), visible: bool,
##   state: StringName.
func set_marker(id: StringName, kind: StringName, target: Variant, options := {}) -> Dictionary:
	var m: Dictionary = markers.get(id, {})
	var is_new := m.is_empty()
	if is_new:
		m = {
			"id": id, "kind": kind, "node": null, "position": Vector3.ZERO, "label": "",
			"color": Color(0, 0, 0, 0), "visible": true, "pin": kind == KIND_OBJECTIVE,
			"state": STATE_NORMAL,
		}
		markers[id] = m
	m["kind"] = kind
	_assign_target(m, target)
	for key in ["label", "color", "pin", "visible", "state"]:
		if options.has(key):
			m[key] = options[key]
	markers_changed.emit()
	return m


func has_marker(id: StringName) -> bool:
	return markers.has(id)


func get_marker(id: StringName) -> Dictionary:
	return markers.get(id, {})


func remove_marker(id: StringName) -> void:
	if markers.erase(id):
		markers_changed.emit()


## Removes every marker of a kind (or all markers when kind is empty), except
## the player.
func clear_markers(kind: StringName = &"") -> void:
	for id in markers.keys():
		if id == PLAYER_ID:
			continue
		if kind == &"" or markers[id]["kind"] == kind:
			markers.erase(id)
	markers_changed.emit()


func move_marker(id: StringName, target: Variant) -> void:
	if markers.has(id):
		_assign_target(markers[id], target)


func set_marker_visible(id: StringName, shown: bool) -> void:
	if markers.has(id) and bool(markers[id]["visible"]) != shown:
		markers[id]["visible"] = shown
		markers_changed.emit()


func set_marker_state(id: StringName, state: StringName) -> void:
	if markers.has(id) and markers[id]["state"] != state:
		markers[id]["state"] = state
		markers_changed.emit()


func set_marker_label(id: StringName, text: String) -> void:
	if markers.has(id):
		markers[id]["label"] = text
		markers_changed.emit()


## The marker's current world position, or Vector3.INF if its node is gone or
## outside the tree.
func get_marker_world(id: StringName) -> Vector3:
	return _resolve(markers.get(id, {}))


func get_ids(kind: StringName = &"") -> Array[StringName]:
	var out: Array[StringName] = []
	for id in markers:
		if kind == &"" or markers[id]["kind"] == kind:
			out.append(id)
	return out


func count(kind: StringName = &"") -> int:
	return get_ids(kind).size()


## Marker id used for a tracked node, so the same node is never added twice.
static func id_for_node(node: Node, prefix := "node") -> StringName:
	return StringName("%s_%d" % [prefix, node.get_instance_id()])


func find_id_for_node(node: Node) -> StringName:
	for id in markers:
		if markers[id]["node"] == node:
			return id
	return &""


## Drops markers whose node was freed. Returns how many were removed.
func prune() -> int:
	var gone: Array = []
	for id in markers:
		var node = markers[id]["node"]
		if node != null and (not is_instance_valid(node) or (node as Node).is_queued_for_deletion()):
			gone.append(id)
	for id in gone:
		markers.erase(id)
	if not gone.is_empty():
		markers_changed.emit()
	return gone.size()


# --- player --------------------------------------------------------------------

func set_player(target: Variant) -> void:
	if target == null:
		remove_marker(PLAYER_ID)
		return
	set_marker(PLAYER_ID, KIND_PLAYER, target, {"label": "You"})
	_player_last = Vector3.INF


func has_player() -> bool:
	return markers.has(PLAYER_ID) and get_marker_world(PLAYER_ID).is_finite()


func get_player_world() -> Vector3:
	return get_marker_world(PLAYER_ID)


## Unit world heading of the player. Taken from movement between updates; while
## standing still the last heading is kept. Seeded from the node's -Z axis.
func get_player_heading() -> Vector3:
	return _player_heading


## Call once per frame (views do this through MinimapHUD/update()).
func update_player_heading() -> void:
	var at := get_player_world()
	if not at.is_finite():
		_player_last = Vector3.INF
		return
	if not _player_last.is_finite():
		var node = markers[PLAYER_ID]["node"]
		if node is Node3D:
			var f := -(node as Node3D).global_basis.z
			f.y = 0.0
			if f.length_squared() > 0.0001:
				_player_heading = f.normalized()
	else:
		var d := at - _player_last
		d.y = 0.0
		if d.length_squared() > 0.0004:
			_player_heading = d.normalized()
	_player_last = at


# --- route ---------------------------------------------------------------------

func set_route(world_points: PackedVector3Array) -> void:
	route_points = world_points
	markers_changed.emit()


func clear_route() -> void:
	set_route(PackedVector3Array())


# --- internals -----------------------------------------------------------------

func _assign_target(m: Dictionary, target: Variant) -> void:
	if target is Node3D:
		m["node"] = target
	elif target is Vector3:
		m["node"] = null
		m["position"] = target
	elif target is Vector2:
		m["node"] = null
		m["position"] = Vector3(target.x, 0.0, target.y)


func _resolve(m: Dictionary) -> Vector3:
	if m.is_empty():
		return Vector3.INF
	var node = m["node"]
	if node == null:
		return m["position"]
	if not is_instance_valid(node) or not (node as Node3D).is_inside_tree():
		return Vector3.INF
	return (node as Node3D).global_position
