class_name CombatSandbox
extends Node3D
## Phase 4 combat test arena: the courier starts carrying a parcel (so the Package Shield
## can be raised), Forest Slimes and Frost Wisps respawn at their spawn points after being
## defeated, and the courier respawns at full health on death. A plain-text readout shows
## health, shield and cooldowns; it is a debugging aid, not production UI.

const STARTING_PACKAGE := "res://data/packages/pkg_ordinary_parcel.tres"

@export var enemy_respawn_delay: float = 4.0
@export var player_respawn_delay: float = 2.0
@export var give_starting_package: bool = true
@export var show_readout: bool = true

@onready var player: PlayerController = $Player
@onready var camera_rig: IsoCameraRig = $CameraRig
@onready var enemies_root: Node3D = $Enemies

var combat: CombatController
var player_health: CombatHealth
var _player_spawn: Vector3
var _spawns: Array[Dictionary] = []
var _readout: Label


func _ready() -> void:
	combat = CombatController.find_on(player)
	player_health = combat.health
	_player_spawn = player.global_position
	camera_rig.target = player
	camera_rig.snap_to_target()
	player_health.died.connect(_on_player_died)
	for enemy in enemies_root.get_children():
		if enemy is Enemy:
			_register_enemy(enemy, enemy.scene_file_path, enemy.global_transform)
	if give_starting_package:
		give_package()
	if show_readout:
		_build_readout()


func _process(_delta: float) -> void:
	if _readout != null:
		_readout.text = _readout_text()


## Puts a fresh parcel in the courier's hands unless they already carry one.
func give_package() -> bool:
	var carrier := PackageCarrier.find_on(player)
	if carrier == null or carrier.is_carrying():
		return false
	return carrier.pick_up(PackageInstance.new(load(STARTING_PACKAGE)))


func _register_enemy(enemy: Enemy, scene_path: String, spawn: Transform3D) -> void:
	var entry := {"scene": scene_path, "transform": spawn}
	_spawns.append(entry)
	enemy.defeated.connect(_on_enemy_defeated.bind(entry))


func _on_enemy_defeated(_enemy: Enemy, entry: Dictionary) -> void:
	if entry.scene != "":
		get_tree().create_timer(enemy_respawn_delay).timeout.connect(respawn_enemy.bind(entry))


func respawn_enemy(entry: Dictionary) -> Enemy:
	var enemy := (load(entry.scene) as PackedScene).instantiate() as Enemy
	enemies_root.add_child(enemy)
	enemy.global_transform = entry.transform
	enemy.defeated.connect(_on_enemy_defeated.bind(entry))
	return enemy


func _on_player_died() -> void:
	player.input_enabled = false
	get_tree().create_timer(player_respawn_delay).timeout.connect(respawn_player)


func respawn_player() -> void:
	player.teleport_to(_player_spawn)
	player_health.reset()
	player.input_enabled = true
	if give_starting_package:
		give_package()


func _build_readout() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CombatReadout"
	add_child(layer)
	_readout = Label.new()
	_readout.position = Vector2(16, 16)
	_readout.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_readout.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(_readout)


func _readout_text() -> String:
	var package := "none"
	var carrier := combat.get_carrier()
	if carrier != null and carrier.is_carrying():
		package = "%s (%.0f%%)" % [carrier.get_package().get_display_name(), carrier.get_package().get_integrity_ratio() * 100.0]
	return "\n".join([
		"HP %.0f / %.0f%s" % [player_health.get_health(), player_health.get_max_health(), "  (DEAD)" if player_health.is_dead() else ""],
		"Shield %s  %.0f / %.0f" % ["UP" if combat.is_shield_active() else "down", combat.get_shield_durability(), combat.shield_max_durability],
		"Bolt %s   Dash %s" % [_cooldown_text(combat.get_magic_bolt_cooldown_remaining()), "DASHING" if combat.is_dashing() else _cooldown_text(combat.get_dash_cooldown_remaining())],
		"Package: %s" % package,
		"[Space] Magic Bolt  [Shift] Dash  [Q] Package Shield  [G] Drop  [E] Pick up",
	])


static func _cooldown_text(remaining: float) -> String:
	return "ready" if remaining <= 0.0 else "%.1fs" % remaining
