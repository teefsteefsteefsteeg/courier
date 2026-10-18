class_name Phase4EncounterSpawnPoint
extends Marker3D
## One forest encounter slot for Phase4DeliveryIntegration. The integration spawns
## enemy_scene here when a Dragon Egg run enters the forest, and again respawn_delay
## seconds after that enemy is defeated (or leashed back). Runtime fields are owned by
## the integration; the marker itself never spawns anything.

## Scene whose root is an Enemy (ForestSlime, FrostWisp).
@export var enemy_scene: PackedScene
@export_range(0.0, 120.0, 0.5, "suffix:s") var respawn_delay: float = 10.0

## Enemy currently occupying this slot (may be freed; use has_live_enemy()).
var enemy: Enemy = null
## Seconds until the slot may respawn.
var respawn_left: float = 0.0
## Enemies spawned here since the scene started (all encounters).
var spawn_count: int = 0
## True until the first spawn of the current encounter; the first wave ignores the
## minimum respawn distance.
var initial_spawn_pending: bool = true


func has_live_enemy() -> bool:
	return is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and not enemy.is_dead()


## Forgets the slot's enemy and timers (encounter ended).
func reset_runtime() -> void:
	enemy = null
	respawn_left = 0.0
	initial_spawn_pending = true
