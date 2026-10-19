class_name HarvestNode
extends ToolTarget
## A resource node worked with a gathering tool (Phase 5H): a marked tree (woodcutting
## axe -> wood), an ore rock (pickaxe -> stone, sometimes iron ore), a patch of soft soil
## (shovel -> clay). After the last stroke it pays yield_min..yield_max of yield_material
## (plus bonus_material with bonus_chance), shows depleted_visual instead of
## standing_visual, and stays used up for respawn_seconds (0 = for good). The depletion is
## kept by the GatheringService, so it survives save and load, and a node can never pay out
## twice while depleted. Only nodes built from this script can be harvested: decorative
## trees and rocks are untouched.

@export var yield_material: MaterialItem
@export_range(1, 20) var yield_min: int = 2
@export_range(1, 20) var yield_max: int = 3
@export var bonus_material: MaterialItem
@export_range(0.0, 1.0, 0.01) var bonus_chance: float = 0.0
## Seconds until it can be harvested again (0 = never).
@export_range(0.0, 3600.0, 1.0, "suffix:s") var respawn_seconds: float = 180.0
## Lifetime tally key in the GatheringService (&"chop", &"mine", &"dig").
@export var activity: StringName = &"chop"
## Shown while it can be harvested.
@export var standing_visual: Node3D
## Shown while depleted (a stump, rubble, a dug hole).
@export var depleted_visual: Node3D
## Text while depleted, before the regrow time ("Tree stump").
@export var depleted_name: String = ""

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
	return "used up" if is_inf(left) else "back in %s" % format_time(left)


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
		service.mark_depleted(target_id, respawn_seconds)
		service.add_count(activity)
	refresh()
	return ", ".join(gained)


func refresh() -> void:
	var available := is_available()
	set_active(standing_visual, available)
	set_active(depleted_visual, not available)
	if interactable != null:
		# A depleted node still answers (its prompt says when it is back).
		interactable.enabled = true
