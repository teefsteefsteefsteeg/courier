extends SceneTree
## Phase 8 milestone 4: the animated HUD avatar, in the real village.
## - The status panel's portrait shows a live AnimatedPortrait render of the courier's own
##   model (the Player's KayKit Ranger), not the still image.
## - It idles (an animation plays and the pose changes over time), flinches on damage (and
##   the portrait flushes red), sags and pulses red at low health, recovers when healed,
##   and cheers on a quest reward.
## - Cheap: 128 px, its own world (no level geometry), renders about every other frame.
##   godot --headless --path . --script res://tests/phase8_avatar_tests.gd

const VILLAGE := "res://scenes/levels/village.tscn"

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var health: CombatHealth
var hud: Node
var live: AnimatedPortrait


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	level = (load(VILLAGE) as PackedScene).instantiate()
	(level.get_node("GameplayServices/SaveGame") as SaveGame).path = "user://phase8_avatar_tests.json"
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	health = CombatController.find_on(player).health
	await _frames(30)
	var panels := level.find_children("*", "AnimatedPortrait", true, false)
	live = panels[0] as AnimatedPortrait if not panels.is_empty() else null
	_check(live != null, "the status panel has a live portrait")
	if live == null:
		quit(_failures)
		return
	hud = live.get_parent()
	while hud != null and not (hud.get(&"portrait") is TextureRect):
		hud = hud.get_parent()

	_test_setup()
	await _test_idle()
	await _test_damage_and_low()
	await _test_celebrate()

	print("\n=== Phase 8 avatar tests: %d passed, %d failed ===" % [_passes, _failures])
	quit(_failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _test_setup() -> void:
	print("[Setup]")
	var portrait := hud.get(&"portrait") as TextureRect
	_check(portrait != null and portrait.texture == live.get_texture(), "the round frame shows the live render, not the still")
	var player_model := (player.find_children("*", "KayKitCharacter", true, false)[0] as KayKitCharacter).model
	_check(live.character != null and live.character.model == player_model, "it renders the player's own model (%s)" % player_model.resource_path.get_file())
	_check(live.size == Vector2i(AnimatedPortrait.PIXELS, AnimatedPortrait.PIXELS) and live.own_world_3d and live.positional_shadow_atlas_size == 0, "128 px, its own world, no shadows")
	var meshes := live.find_children("*", "MeshInstance3D", true, false).size()
	_check(meshes > 0 and meshes < 20, "only the courier is in its world (%d meshes)" % meshes)


func _test_idle() -> void:
	print("[Idle]")
	_check(live.character.animation_player.is_playing() and live.character.current_clip == &"general/Idle_A", "the idle clip plays (%s)" % live.character.current_clip)
	var head := live.character.skeleton.find_bone("head")
	var before := live.character.skeleton.get_bone_global_pose(head).origin
	await create_timer(0.5).timeout
	var after := live.character.skeleton.get_bone_global_pose(head).origin
	_check(before.distance_to(after) > 0.001, "the head moves while idling (%.3f)" % before.distance_to(after))
	live._glance_left = 0.0
	await create_timer(0.8).timeout
	_check(absf(live.character.rotation.y) > 0.02 or absf(live._yaw_target) < 0.01, "it glances aside now and then (yaw %.2f)" % live.character.rotation.y)


func _test_damage_and_low() -> void:
	print("[Damage and low health]")
	var reactions: Array[StringName] = []
	live.reacted.connect(func(kind: StringName) -> void: reactions.append(kind))
	health.reset()
	await _frames(3)
	health.apply_damage(10.0, player.global_position + Vector3.FORWARD)
	await _frames(3)
	var portrait := hud.get(&"portrait") as TextureRect
	_check(reactions.has(&"hit") and live.character.one_shot_action == &"hit", "a hit makes the portrait flinch (%s)" % live.character.one_shot_action)
	_check(portrait.self_modulate.g < 0.95, "and flush red (%s)" % portrait.self_modulate)
	await create_timer(1.2).timeout
	_check(portrait.self_modulate.is_equal_approx(Color.WHITE), "the flush fades")
	health.apply_damage(health.get_health() - health.get_max_health() * 0.15, Vector3.ZERO)
	await _frames(5)
	_check(live.is_low() and reactions.has(&"low"), "at %.0f%% health the portrait is low" % (health.get_health_ratio() * 100.0))
	_check(is_equal_approx(live.character.current_loop_speed, 0.6) and live.character.rotation.x > 0.05, "it breathes slower and sags")
	var reds: Array[float] = []
	for i in 12:
		await create_timer(0.1).timeout
		reds.append(portrait.self_modulate.g)
	_check(reds.max() - reds.min() > 0.05, "and pulses red (%.2f..%.2f)" % [reds.min(), reds.max()])
	health.heal(health.get_max_health())
	await create_timer(0.5).timeout
	_check(not live.is_low() and reactions.has(&"recovered") and is_equal_approx(live.character.current_loop_speed, 1.0), "healing brings it back")


func _test_celebrate() -> void:
	print("[Victory]")
	var manager := QuestManager.find(self)
	var cheered := [false]
	live.reacted.connect(func(kind: StringName) -> void:
		if kind == &"cheer":
			cheered[0] = true)
	manager.quest_rewarded.emit(&"test_reward", null)
	await _frames(3)
	_check(cheered[0] and live.mood == &"cheer" and live.character.one_shot_action == &"cheer", "a quest reward makes the courier cheer")
	await create_timer(2.0).timeout
	_check(live.mood == &"idle", "then it returns to idle")
