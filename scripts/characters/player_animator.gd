class_name PlayerAnimator
extends Node
## Drives the courier's KayKitCharacter from existing gameplay signals only
## (movement state, combat, health, interaction, package pick-up). It reads
## gameplay, never changes it.

@export var character: KayKitCharacter
@export var movement: MovementComponent
@export var combat: CombatController
@export var interaction: InteractionDetector
@export var carrier: PackageCarrier

var _knocked_out := false


func _ready() -> void:
	if character == null:
		return
	if movement != null:
		movement.state_changed.connect(_on_state_changed)
	if combat != null:
		# Attack poses meet the gameplay hit (Phase 7): a swing reaches its strike when the
		# hit lands (melee_windup after melee_started; a quick slice for a sword, a slower
		# chop for an axe), and a cast or bow pull is at its release when the projectile
		# leaves. AttackEffects times its swing arc to the same moment.
		combat.magic_bolt_fired.connect(func(_origin: Vector3, _direction: Vector3) -> void: character.play_once_strike(&"attack", 0.0, 1.6))
		combat.melee_started.connect(func(_direction: Vector3, heavy: bool) -> void:
			character.play_once_strike(&"melee_heavy" if heavy else &"melee_fast", combat.melee_windup))
		combat.arrow_fired.connect(func(_origin: Vector3, _direction: Vector3) -> void: character.play_once_strike(&"shoot", 0.0, 2.0))
		combat.dash_started.connect(func() -> void: character.play_once(&"dash", 1.8))
		# The dash pose lasts as long as the dash (finished, blocked by a wall or cut short
		# by a knockout), then the current movement loop takes over: idle, walk or run.
		combat.dash_finished.connect(func() -> void: character.end_once(&"dash"))
		if combat.health != null:
			combat.health.damaged.connect(_on_damaged)
			combat.health.died.connect(_on_died)
			combat.health.health_changed.connect(_on_health_changed)
	if interaction != null:
		# Tool targets play their own tool clip (ToolUser), so no generic reach for them.
		interaction.interaction_performed.connect(func(target: Interactable) -> void:
			if not target.get_parent() is ToolTarget:
				character.play_once(&"interact", 1.4))
	if carrier != null:
		carrier.package_picked_up.connect(func(_package: PackageInstance) -> void: character.play_once(&"pickup", 1.6))


func _on_state_changed(new_state: MovementComponent.State, _old_state: MovementComponent.State) -> void:
	# Walk and run clips follow the movement speed (MovementComponent.get_animation_speed_scale).
	match new_state:
		MovementComponent.State.WALK:
			character.play_loop(&"walk", movement.get_animation_speed_scale(new_state))
		MovementComponent.State.RUN:
			character.play_loop(&"run", movement.get_animation_speed_scale(new_state))
		MovementComponent.State.AIRBORNE:
			character.play_loop(&"airborne")
		_:
			character.play_loop(&"idle")


func _on_damaged(_amount: float, _source: Vector3) -> void:
	if not _knocked_out:
		character.play_once(&"hit", 1.2)


func _on_died() -> void:
	_knocked_out = true
	character.play_once(&"death", 1.0, true)


func _on_health_changed(current: float, _maximum: float) -> void:
	# The knockout respawn restores health right away: get back up in the village.
	if _knocked_out and current > 0.0:
		_knocked_out = false
		character.release()
		character.play_once(&"revive")
