class_name ExplorationService
extends Node
## World exploration state, in GameplayServices next to the wallet and inventory:
## - the shared location registry (WorldLocation nodes register themselves),
## - which locations the courier has discovered (once per save),
## - which teleport portals are activated,
## - which parts of the map have been explored (fog of war): a grid of CELL_SIZE metre
##   cells over WORLD_RECT, revealed within reveal_radius of the courier as they travel.
## SaveGame stores to_dict() under "exploration"; saves without it start unexplored.
## The fog only affects the map UI, never the 3D view.

signal location_discovered(location: WorldLocation)
signal portal_activated(portal_id: StringName)
## Explored cells changed (at most every SCAN_INTERVAL seconds).
signal explored_changed

const GROUP := &"exploration_service"
## World X/Z area the map and fog cover (the village terrain is 128 m across).
const WORLD_RECT := Rect2(-64.0, -64.0, 128.0, 128.0)
const CELL_SIZE := 2.0
const SCAN_INTERVAL := 0.2
## Fog texel colours: unexplored parchment-dark, explored clear.
const FOG_HIDDEN := Color(0.09, 0.075, 0.06, 1.0)
const FOG_CLEAR := Color(0.09, 0.075, 0.06, 0.0)

@export_range(2.0, 40.0, 0.5, "suffix:m") var reveal_radius: float = 14.0

## location_id -> WorldLocation (live registry).
var locations: Dictionary[StringName, WorldLocation] = {}
var _discovered: Dictionary[StringName, bool] = {}
var _portals: Dictionary[StringName, bool] = {}
var _cells := PackedByteArray()
var _grid := Vector2i.ZERO
var _fog_image: Image
var _fog_texture: ImageTexture
var _scan_left := 0.0
var _last_reveal := Vector2.INF
var _player: Node3D = null
var region_id: StringName = &"village"
var _region_fog: Dictionary = {}


func _enter_tree() -> void:
	add_to_group(GROUP)
	_grid = Vector2i(ceili(WORLD_RECT.size.x / CELL_SIZE), ceili(WORLD_RECT.size.y / CELL_SIZE))
	_cells.resize(_grid.x * _grid.y)
	_cells.fill(0)
	_fog_image = Image.create(_grid.x, _grid.y, false, Image.FORMAT_RGBA8)
	_fog_image.fill(FOG_HIDDEN)
	_fog_texture = ImageTexture.create_from_image(_fog_image)


static func find(tree: SceneTree) -> ExplorationService:
	return tree.get_first_node_in_group(GROUP) as ExplorationService


func _process(delta: float) -> void:
	_scan_left -= delta
	if _scan_left > 0.0:
		return
	_scan_left = SCAN_INTERVAL
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(CombatController.PLAYER_GROUP) as Node3D
		if _player == null:
			return
	# The surface map must not reveal village cells while walking the underground vault.
	if _player.global_position.y < -20.0:
		return
	var at := Vector2(_player.global_position.x, _player.global_position.z)
	if _last_reveal.distance_to(at) >= 1.0:
		_last_reveal = at
		reveal_around(at)
	for id in locations:
		var location := locations[id]
		if not _discovered.has(id) and is_instance_valid(location) and location.region_id == region_id and location.discover_radius > 0.0 \
				and location.get_map_position().distance_to(at) <= location.discover_radius:
			discover(id)


# --- registry ----------------------------------------------------------------------

func register_location(location: WorldLocation) -> void:
	if location == null or location.location_id == &"":
		return
	if locations.has(location.location_id) and locations[location.location_id] != location and is_instance_valid(locations[location.location_id]):
		push_warning("ExplorationService: duplicate location_id %s" % location.location_id)
		return
	locations[location.location_id] = location


func get_location(location_id: StringName) -> WorldLocation:
	var location: WorldLocation = locations.get(location_id)
	return location if location != null and is_instance_valid(location) else null


## Registered locations of a kind (all kinds when kind < 0), in registration order.
func get_locations(kind: int = -1) -> Array[WorldLocation]:
	var out: Array[WorldLocation] = []
	for id in locations:
		var location := get_location(id)
		if location != null and location.region_id == region_id and (kind < 0 or location.kind == kind):
			out.append(location)
	return out


# --- discovery and portals ---------------------------------------------------------

func is_discovered(location_id: StringName) -> bool:
	return _discovered.has(location_id)


## Marks a location discovered. Returns true the first time (per save) only.
func discover(location_id: StringName) -> bool:
	if location_id == &"" or _discovered.has(location_id):
		return false
	_discovered[location_id] = true
	var location := get_location(location_id)
	if location != null:
		location_discovered.emit(location)
	return true


func get_discovered_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_discovered.keys())
	return ids


func is_portal_active(portal_id: StringName) -> bool:
	return _portals.has(portal_id)


## Activates a portal (and discovers its location). Returns true the first time only.
func activate_portal(portal_id: StringName) -> bool:
	if portal_id == &"" or _portals.has(portal_id):
		return false
	discover(portal_id)
	_portals[portal_id] = true
	portal_activated.emit(portal_id)
	return true


func get_active_portal_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_portals.keys())
	return ids


# --- fog of war --------------------------------------------------------------------

func get_grid_size() -> Vector2i:
	return _grid


func cell_of(world_xz: Vector2) -> Vector2i:
	var local := (world_xz - WORLD_RECT.position) / CELL_SIZE
	return Vector2i(floori(local.x), floori(local.y))


func is_explored(world_xz: Vector2) -> bool:
	var cell := cell_of(world_xz)
	if cell.x < 0 or cell.y < 0 or cell.x >= _grid.x or cell.y >= _grid.y:
		return false
	return _cells[cell.y * _grid.x + cell.x] != 0


## Fraction of the map explored (0..1).
func get_explored_ratio() -> float:
	return float(_cells.count(1)) / float(maxi(_cells.size(), 1))


## Reveals every cell whose centre lies within reveal_radius of world_xz.
func reveal_around(world_xz: Vector2, radius: float = -1.0) -> void:
	var r := reveal_radius if radius < 0.0 else radius
	var lo := cell_of(world_xz - Vector2(r, r))
	var hi := cell_of(world_xz + Vector2(r, r))
	var changed := false
	for y in range(maxi(lo.y, 0), mini(hi.y, _grid.y - 1) + 1):
		for x in range(maxi(lo.x, 0), mini(hi.x, _grid.x - 1) + 1):
			var index := y * _grid.x + x
			if _cells[index] != 0:
				continue
			var centre := WORLD_RECT.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * CELL_SIZE
			if centre.distance_to(world_xz) <= r:
				_cells[index] = 1
				_fog_image.set_pixel(x, y, FOG_CLEAR)
				changed = true
	if changed:
		_fog_texture.update(_fog_image)
		explored_changed.emit()


## Fog over WORLD_RECT, one texel per cell: opaque dark where unexplored, clear where explored.
func get_fog_texture() -> ImageTexture:
	return _fog_texture


# --- save ----------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"explored": Marshalls.raw_to_base64(_cells.compress(FileAccess.COMPRESSION_DEFLATE)),
		"explored_size": [_grid.x, _grid.y],
		"discovered": _discovered.keys().map(func(id: StringName) -> String: return String(id)),
		"portals": _portals.keys().map(func(id: StringName) -> String: return String(id)),
		"region_id": String(region_id),
		"region_fog": _region_fog.duplicate(true),
	}


## Restores saved exploration. Unknown or malformed data is ignored (a fresh map), so old
## saves and saves from before new locations or portals load cleanly.
func from_dict(data: Dictionary) -> void:
	region_id = StringName(data.get("region_id","village"))
	var saved_regions: Variant = data.get("region_fog",{})
	_region_fog = saved_regions.duplicate(true) if saved_regions is Dictionary else {}
	_discovered.clear()
	_portals.clear()
	_cells.fill(0)
	var size: Array = data.get("explored_size", [])
	if size.size() == 2 and int(size[0]) == _grid.x and int(size[1]) == _grid.y:
		var raw := Marshalls.base64_to_raw(String(data.get("explored", "")))
		var cells := raw.decompress(_grid.x * _grid.y, FileAccess.COMPRESSION_DEFLATE) if not raw.is_empty() else PackedByteArray()
		if cells.size() == _cells.size():
			_cells = cells
	for id in data.get("discovered", []):
		_discovered[StringName(id)] = true
	for id in data.get("portals", []):
		_portals[StringName(id)] = true
	for y in _grid.y:
		for x in _grid.x:
			_fog_image.set_pixel(x, y, FOG_CLEAR if _cells[y * _grid.x + x] != 0 else FOG_HIDDEN)
	_fog_texture.update(_fog_image)
	_last_reveal = Vector2.INF
	explored_changed.emit()


## Switch fog grids without replacing discovery, portal activation or the player.
func set_region(next: StringName) -> void:
	if region_id == next:
		return
	_region_fog[String(region_id)] = Marshalls.raw_to_base64(_cells.compress(FileAccess.COMPRESSION_DEFLATE))
	region_id = next
	_cells.fill(0)
	var encoded: String = _region_fog.get(String(next),"")
	if not encoded.is_empty():
		var raw := Marshalls.base64_to_raw(encoded)
		var restored := raw.decompress(_grid.x*_grid.y,FileAccess.COMPRESSION_DEFLATE) if not raw.is_empty() else PackedByteArray()
		if restored.size() == _cells.size():
			_cells = restored
	for y in _grid.y:
		for x in _grid.x:
			_fog_image.set_pixel(x,y,FOG_CLEAR if _cells[y*_grid.x+x] else FOG_HIDDEN)
	_fog_texture.update(_fog_image)
	_last_reveal = Vector2.INF
	explored_changed.emit()
