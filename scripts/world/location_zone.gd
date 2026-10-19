class_name LocationZone
extends Area3D
## A named region of the world (village, post office, forest edge). Zones may
## nest; while the player is inside several, the highest `zone_priority` wins.
## LocationBanner listens to these to announce where the player is.
##
## location_id links the zone to its WorldLocation in the shared registry: entering the
## zone discovers that location (ExplorationService) before player_entered is emitted, so
## the banner can tell a first discovery from a normal entry.

signal player_entered(zone: LocationZone)
signal player_exited(zone: LocationZone)

const GROUP := &"location_zone"

@export var display_name: String = "Somewhere"
## Smaller line under the name, e.g. the parent region.
@export var subtitle: String = ""
@export var zone_priority: int = 0
## Stable id of this place in the location registry (WorldLocation.location_id).
@export var location_id: StringName


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		if location_id != &"":
			var service := ExplorationService.find(get_tree())
			if service != null:
				service.discover(location_id)
		player_entered.emit(self)


func _on_body_exited(body: Node3D) -> void:
	if body is PlayerController:
		player_exited.emit(self)
