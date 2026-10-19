class_name WorldLocation
extends Marker3D
## One named place in the shared location registry: the world map label and icon, the
## location banner's name, and (for portals) the fast-travel destination all read it, so
## there is a single list of places. Place it where the map should put the place's icon.
##
## It registers itself with the ExplorationService, which discovers it when the courier
## comes within discover_radius (or enters a LocationZone with the same location_id) and
## saves that for the save file. location_id is stable: it is saved, never rename it.

enum Kind { TOWN, GUILD, SHOP, FOREST, CLEARING, PORTAL }

const GROUP := &"world_locations"

@export var location_id: StringName
@export var display_name: String = ""
## Smaller line (banner subtitle, map tooltip).
@export var subtitle: String = ""
@export var kind: Kind = Kind.TOWN
## Metres; the courier discovers the place when this close. 0 = only through its LocationZone.
@export_range(0.0, 60.0, 0.5, "suffix:m") var discover_radius: float = 6.0
## Shown on the map (and as a banner) only once discovered.
@export var hidden_until_discovered := true
## Separate maps share session services, but only show locations for the active region.
@export var region_id: StringName = &"village"


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_register.call_deferred()


func _register() -> void:
	var service := ExplorationService.find(get_tree())
	if service != null:
		service.register_location(self)


func get_map_position() -> Vector2:
	return Vector2(global_position.x, global_position.z)


static func kind_name(value: Kind) -> String:
	return ["Town", "Guild", "Shop", "Forest", "Clearing", "Portal"][value]
