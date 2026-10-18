class_name DestinationArea
extends Area3D
## Reports REACH_DESTINATION progress when the player body enters.
## Collision mask should include the player layer (layer 2).

signal player_entered(destination_id: StringName)

## Every destination joins this group (quest waypoints).
const GROUP := &"destination_areas"

@export var destination_id: StringName
@export var display_name: String = ""


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body is PlayerController:
		return
	player_entered.emit(destination_id)
	var manager := QuestManager.find(get_tree())
	if manager != null:
		manager.notify_destination_reached(destination_id)
