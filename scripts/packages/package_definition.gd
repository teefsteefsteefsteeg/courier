class_name PackageDefinition
extends Resource
## Static data for a deliverable package. Authored as .tres in res://data/packages/.
## Phase 2: all packages behave normally (no temperature/curse/instability yet).

@export var package_id: StringName
@export var package_name: String = ""
@export_multiline var package_description: String = ""
## npc_id of the only NPC allowed to accept this package.
@export var recipient_id: StringName
@export var quest_id: StringName
## Visual shown when carried or lying in the world. Must not contain physics bodies.
@export var package_scene: PackedScene
## Starting / maximum integrity (0..100).
@export_range(0.0, 100.0, 0.5) var integrity: float = 100.0
