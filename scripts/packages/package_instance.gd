class_name PackageInstance
extends RefCounted
## One physical package in play. Runtime values (integrity) live here, never on
## the shared PackageDefinition resource.

signal integrity_changed(new_value: float, old_value: float)

var definition: PackageDefinition
var integrity: float


func _init(package_definition: PackageDefinition) -> void:
	definition = package_definition
	integrity = package_definition.integrity


func get_package_id() -> StringName:
	return definition.package_id


func get_quest_id() -> StringName:
	return definition.quest_id


func get_recipient_id() -> StringName:
	return definition.recipient_id


func set_integrity(value: float) -> void:
	var old := integrity
	integrity = clampf(value, 0.0, definition.integrity)
	if not is_equal_approx(old, integrity):
		integrity_changed.emit(integrity, old)
