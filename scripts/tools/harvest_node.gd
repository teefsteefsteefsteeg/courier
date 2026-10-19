class_name HarvestNode
extends ToolTarget
## A resource node worked with a gathering tool (Phase 5H): a marked tree (woodcutting
## axe -> wood), an ore rock (pickaxe -> stone, sometimes iron ore), a patch of soft soil
## (shovel -> clay). After the last stroke it pays yield_min..yield_max of yield_material
## (plus bonus_material with bonus_chance), shows depleted_visual instead of
## standing_visual, and stays used up for a random time between respawn_min_seconds and
## respawn_max_seconds (Phase 8; both 0 = for good). The prompt never shows a countdown:
## the node just regrows. The depletion is kept by the GatheringService as a timestamp per
## target_id, so it survives save and load and region changes, and a node can never pay out
## twice while depleted. Only nodes built from this script can be harvested: decorative
## trees and rocks are untouched.

@export var yield_material: MaterialItem
@export_range(1, 20) var yield_min: int = 2
@export_range(1, 20) var yield_max: int = 3
@export var bonus_material: MaterialItem
@export_range(0.0, 1.0, 0.01) var bonus_chance: float = 0.0
## Shortest and longest time until it can be harvested again; each depletion draws a random
## time between them (both 0 = never).
@export_range(0.0, 3600.0, 1.0, "suffix:s") var respawn_min_seconds: float = 150.0
@export_range(0.0, 3600.0, 1.0, "suffix:s") var respawn_max_seconds: float = 240.0
## Lifetime tally key in the GatheringService (&"chop", &"mine", &"dig").
@export var activity: StringName = &"chop"
## Shown while it can be harvested.
@export var standing_visual: Node3D
## Shown while depleted (a stump, rubble, a dug hole).
@export var depleted_visual: Node3D
## Text while depleted ("Tree stump").
@export var depleted_name: String = ""

## What a depleted node says instead of a timer.
const REGROW_TEXT := {&"chop": "regrowing", &"mine": "the ore will return", &"dig": "settling"}

var rng := RandomNumberGenerator.new()


func check_requirements(user: ToolUser) -> String:
	var inventory := user.get_inventory() if user != null else null
	if inventory != null and yield_material != null and inventory.get_material_count(yield_material.material_id) >= CourierInventory.MAX_STACK:
		return "your %s stack is full; sell some to the Toolwright" % yield_material.display_name
	return ""


func is_available() -> bool:
	var service := get_service()
	return service == null or not service.is_depleted(target_id)


func get_unavailable_text() -> String:
	var service := get_service()
	var left := service.seconds_until_respawn(target_id) if service != null else 0.0
	# No countdown (Phase 8): the player only learns that it will come back.
	return "used up" if is_inf(left) else REGROW_TEXT.get(activity, "regrowing")


func get_interaction_prompt(interactor: Node) -> String:
	if not is_available() and not depleted_name.is_empty():
		return "%s · %s" % [depleted_name, get_unavailable_text()]
	return super(interactor)


func complete(user: ToolUser) -> String:
	var service := get_service()
	var inventory := user.get_inventory() if user != null else null
	if inventory == null or yield_material == null or not is_available():
		return ""
	var amount := rng.randi_range(yield_min, maxi(yield_min, yield_max))
	var gained: PackedStringArray = []
	var added := inventory.add_material(yield_material, amount)
	if added <= 0:
		return ""
	gained.append("+%d %s" % [added, yield_material.display_name])
	if bonus_material != null and rng.randf() < bonus_chance:
		if inventory.add_material(bonus_material, 1) > 0:
			gained.append("+1 %s" % bonus_material.display_name)
	if service != null:
		service.mark_depleted(target_id, roll_respawn_seconds())
		service.add_count(activity)
	refresh()
	return ", ".join(gained)


## A respawn time between respawn_min_seconds and respawn_max_seconds (0 = never).
func roll_respawn_seconds() -> float:
	var low := minf(respawn_min_seconds, respawn_max_seconds)
	var high := maxf(respawn_min_seconds, respawn_max_seconds)
	if high <= 0.0:
		return 0.0
	return rng.randf_range(maxf(low, 1.0), high)


func refresh() -> void:
	# Out of the tree there is no GatheringService to ask; _enter_tree refreshes later.
	if not is_inside_tree():
		return
	var available := is_available()
	set_active(standing_visual, available)
	set_active(depleted_visual, not available)
	if interactable != null:
		# A depleted node still answers (its prompt says when it is back).
		interactable.enabled = true
