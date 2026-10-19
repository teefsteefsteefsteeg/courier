class_name FishingSpot
extends ToolTarget
## A designated place to fish from (Phase 5H), e.g. the end of the pond jetty: "[E] Fish at
## Willowmere Pond Jetty" with the rod in hand casts at cast_point. Fishing itself (cast,
## wait, bite, timed hook, reel) is run by ToolUser; catch_bonus raises the odds of rare
## fish here. The rod also fishes from any bank of a Pond without a spot (see ToolUser).
## With requires_repair set, the spot only works once that structure is repaired.

@export var pond: Pond
## Where the line lands (over open water).
@export var cast_point: Marker3D
## Multiplies the weight of the pond's rare fish.
@export_range(1.0, 10.0, 0.1) var catch_bonus: float = 1.0
@export var requires_repair: RepairSite


func _init() -> void:
	required_tool = ItemDefinition.ToolType.FISHING_ROD
	verb = "Fish at"
	action = &"tool_cast"
	strokes = 1
	chip_color = Color(0, 0, 0, 0)


func is_available() -> bool:
	return requires_repair == null or requires_repair.is_repaired()


func get_unavailable_text() -> String:
	return "repair the %s first" % requires_repair.display_name if requires_repair != null else ""


func get_work_point() -> Vector3:
	return cast_point.global_position if cast_point != null else global_position


func refresh() -> void:
	if interactable != null:
		interactable.enabled = is_available()
