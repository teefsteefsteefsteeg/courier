class_name FarmService
extends Node
## The courier's garden (Phase 7): which crop grows in which FarmPlot and since when.
## Lives in GameplayServices; FarmPlots find it by group and only show its state.
##
## Growth runs on the service's own play-time clock (`play_time`, seconds the game has been
## running with the service processing, saved with the farm), not on the system clock:
## changing the computer's date or leaving the game closed never ripens a crop. A crop
## planted at play time t is in stage floor((now - t) / stage_seconds), ripe at
## stage_count. Planting takes exactly one seed and fails on an occupied plot; harvesting
## needs a ripe crop and room in the produce stack, pays once and empties the plot.
##
## SaveGame stores to_dict() under "farming"; saves without it start with empty plots.

## A plot was planted, harvested or restored.
signal plot_changed(plot_id: StringName)
## A growing crop reached a new stage (checked once a second).
signal stage_changed(plot_id: StringName, stage: int)

const GROUP := &"farm_service"
const CHECK_INTERVAL := 1.0

enum PlantResult { OK, OCCUPIED, NO_SEED, UNKNOWN_CROP, NO_INVENTORY }

## Every crop that can be planted. Unknown crop ids in a save are dropped.
@export var crops: Array[CropDefinition] = []

## Seconds of play the farm has seen (the growth clock).
var play_time: float = 0.0
## Lifetime number of harvests.
var harvests: int = 0
## The seed the courier picked in the inventory (Tools view); FarmPlots plant it first.
var preferred_seed: StringName = &""
var rng := RandomNumberGenerator.new()

var _crops: Dictionary[StringName, CropDefinition] = {}
## plot_id -> {"crop": StringName, "planted": float play_time}
var _plots: Dictionary[StringName, Dictionary] = {}
var _stages: Dictionary[StringName, int] = {}
var _check_left: float = CHECK_INTERVAL


func _enter_tree() -> void:
	add_to_group(GROUP)
	for crop in crops:
		register_crop(crop)


static func find(tree: SceneTree) -> FarmService:
	return tree.get_first_node_in_group(GROUP) as FarmService


func _process(delta: float) -> void:
	advance(delta)


## Moves the growth clock on (the game does this every frame; tests call it directly).
func advance(seconds: float) -> void:
	if seconds <= 0.0:
		return
	play_time += seconds
	_check_left -= seconds
	if _check_left <= 0.0:
		_check_left = CHECK_INTERVAL
		for plot_id in _plots:
			var stage := get_stage(plot_id)
			if stage != _stages.get(plot_id, -1):
				_stages[plot_id] = stage
				stage_changed.emit(plot_id, stage)


func register_crop(crop: CropDefinition) -> void:
	if crop != null and crop.crop_id != &"":
		_crops[crop.crop_id] = crop


func get_crop(crop_id: StringName) -> CropDefinition:
	return _crops.get(crop_id)


func get_crops() -> Array[CropDefinition]:
	var out: Array[CropDefinition] = []
	for id in _crops:
		out.append(_crops[id])
	return out


## The crop that seed_id grows, or null.
func crop_for_seed(seed_id: StringName) -> CropDefinition:
	for id in _crops:
		var crop := _crops[id]
		if crop.seed_item != null and crop.seed_item.material_id == seed_id:
			return crop
	return null


## Picks the seed FarmPlots plant first (the inventory's "Plant first" button).
func set_preferred_seed(seed_id: StringName) -> void:
	if seed_id != preferred_seed:
		preferred_seed = seed_id
		plot_changed.emit(&"")


func is_empty(plot_id: StringName) -> bool:
	return not _plots.has(plot_id)


## The crop growing in plot_id, or null when it is empty.
func get_planted_crop(plot_id: StringName) -> CropDefinition:
	return get_crop(_plots[plot_id]["crop"]) if _plots.has(plot_id) else null


## 0 just after planting .. crop.stage_count when ripe; -1 for an empty plot.
func get_stage(plot_id: StringName) -> int:
	var crop := get_planted_crop(plot_id)
	if crop == null:
		return -1
	var grown: float = play_time - float(_plots[plot_id]["planted"])
	return clampi(floori(grown / crop.stage_seconds), 0, crop.stage_count)


## 0..1 growth of the crop in plot_id (0 when empty).
func get_growth(plot_id: StringName) -> float:
	var crop := get_planted_crop(plot_id)
	if crop == null:
		return 0.0
	return clampf((play_time - float(_plots[plot_id]["planted"])) / crop.get_grow_seconds(), 0.0, 1.0)


func is_ripe(plot_id: StringName) -> bool:
	var crop := get_planted_crop(plot_id)
	return crop != null and get_stage(plot_id) >= crop.stage_count


func seconds_until_ripe(plot_id: StringName) -> float:
	var crop := get_planted_crop(plot_id)
	if crop == null:
		return 0.0
	return maxf(crop.get_grow_seconds() - (play_time - float(_plots[plot_id]["planted"])), 0.0)


## Plants crop_id in an empty plot, taking one of its seeds from inventory (all or nothing).
func plant(plot_id: StringName, crop_id: StringName, inventory: CourierInventory) -> PlantResult:
	if inventory == null:
		return PlantResult.NO_INVENTORY
	var crop := get_crop(crop_id)
	if crop == null or crop.seed_item == null:
		return PlantResult.UNKNOWN_CROP
	if not is_empty(plot_id):
		return PlantResult.OCCUPIED
	if not inventory.remove_materials({crop.seed_item.material_id: 1}):
		return PlantResult.NO_SEED
	_plots[plot_id] = {"crop": crop.crop_id, "planted": play_time}
	_stages[plot_id] = 0
	plot_changed.emit(plot_id)
	return PlantResult.OK


## Harvests a ripe plot: adds yield_min..yield_max produce and empties the plot. Returns
## how many were added (0, and the crop stays, when it is not ripe or the stack is full).
func harvest(plot_id: StringName, inventory: CourierInventory) -> int:
	if inventory == null or not is_ripe(plot_id):
		return 0
	var crop := get_planted_crop(plot_id)
	if inventory.get_material_count(crop.produce.material_id) >= CourierInventory.MAX_STACK:
		return 0
	var added := inventory.add_material(crop.produce, rng.randi_range(crop.yield_min, maxi(crop.yield_min, crop.yield_max)))
	if added <= 0:
		return 0
	_plots.erase(plot_id)
	_stages.erase(plot_id)
	harvests += 1
	plot_changed.emit(plot_id)
	return added


static func plant_result_text(result: PlantResult, crop: CropDefinition = null) -> String:
	match result:
		PlantResult.OK:
			return "Planted %s." % crop.display_name.to_lower() if crop != null else "Planted."
		PlantResult.OCCUPIED:
			return "Something is already growing here."
		PlantResult.NO_SEED:
			return "You have no seeds. The Toolwright sells them."
	return "Nothing to plant."


# --- save -----------------------------------------------------------------------

func to_dict() -> Dictionary:
	var plots := {}
	for plot_id in _plots:
		plots[String(plot_id)] = {"crop": String(_plots[plot_id]["crop"]), "planted": _plots[plot_id]["planted"]}
	return {"play_time": play_time, "plots": plots, "harvests": harvests, "preferred_seed": String(preferred_seed)}


## Replaces the farm with saved data. Unknown crops are dropped; a planted time after the
## saved clock (an edited save) is treated as just planted.
func from_dict(data: Dictionary) -> void:
	var changed: Array[StringName] = _plots.keys()
	_plots.clear()
	_stages.clear()
	play_time = maxf(float(data.get("play_time", 0.0)), 0.0)
	harvests = maxi(int(data.get("harvests", 0)), 0)
	preferred_seed = StringName(str(data.get("preferred_seed", "")))
	var plots: Dictionary = data.get("plots", {})
	for id in plots:
		var entry: Dictionary = plots[id] if plots[id] is Dictionary else {}
		var crop := get_crop(StringName(entry.get("crop", "")))
		if crop == null:
			continue
		var plot_id := StringName(id)
		_plots[plot_id] = {"crop": crop.crop_id, "planted": minf(float(entry.get("planted", play_time)), play_time)}
		_stages[plot_id] = get_stage(plot_id)
		if not changed.has(plot_id):
			changed.append(plot_id)
	for plot_id in changed:
		plot_changed.emit(plot_id)
