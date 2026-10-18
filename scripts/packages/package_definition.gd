class_name PackageDefinition
extends Resource
## Static data for a deliverable package. Authored as .tres in res://data/packages/.
## Phase 3: `behavior` selects the special mechanic simulated by PackageInstance.tick().
## All tuning is deterministic (no randomness); runtime values live on PackageInstance.

enum Behavior {
	## No passive mechanic; only impacts (drops, bumps) reduce integrity.
	ORDINARY,
	## Temperature drifts toward the ambient value; outside the ideal band integrity drains.
	TEMPERATURE,
	## Fast movement and impacts build instability; high instability drains integrity,
	## and reaching PackageInstance.MAX_INSTABILITY makes the package explode.
	INSTABILITY,
}

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
@export var behavior: Behavior = Behavior.ORDINARY
## Integrity lost per unit of force passed to PackageInstance.apply_impact().
@export_range(0.0, 10.0, 0.05) var impact_sensitivity: float = 1.0

@export_group("Temperature")
@export var starting_temperature: float = 20.0
## Inclusive band in which the package takes no temperature damage.
@export var ideal_temperature_min: float = 0.0
@export var ideal_temperature_max: float = 40.0
## Degrees per second the package moves toward the ambient temperature (linear, no overshoot).
@export_range(0.0, 100.0, 0.05) var temperature_change_rate: float = 0.5
## Integrity lost per second while outside the ideal band.
@export_range(0.0, 100.0, 0.1) var temperature_damage_per_second: float = 2.0

@export_group("Instability")
@export_range(0.0, 100.0, 0.5) var starting_instability: float = 0.0
## Movement speed (m/s) the package tolerates; above it instability builds.
@export_range(0.0, 50.0, 0.1) var instability_safe_speed: float = 3.0
## Instability gained per second for each m/s above the safe speed.
@export_range(0.0, 100.0, 0.1) var instability_gain_per_speed: float = 5.0
## Instability lost per second while at or below the safe speed.
@export_range(0.0, 100.0, 0.1) var instability_recovery_per_second: float = 4.0
## Instability gained per unit of impact force.
@export_range(0.0, 100.0, 0.1) var instability_per_impact: float = 10.0
## At or above this instability the package loses integrity every second.
@export_range(0.0, 100.0, 0.5) var instability_damage_threshold: float = 60.0
@export_range(0.0, 100.0, 0.1) var instability_damage_per_second: float = 5.0
