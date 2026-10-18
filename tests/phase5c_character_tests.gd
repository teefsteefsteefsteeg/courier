extends SceneTree
## Phase 5C character checks: the courier and NPCs use animated KayKit models,
## the old primitive meshes are hidden (not deleted), every gameplay action maps
## to a clip that exists, and gameplay events drive the right animations.
## Run headless from the project root:
##   godot --headless --path . --script res://tests/phase5c_character_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"
const CAST := {
	"Player": "Ranger.glb",
	"NPCs/PostmasterBram": "Barbarian.glb",
	"NPCs/MerchantMira": "Rogue.glb",
	"NPCs/AlchemistCorvin": "Rogue_Hooded.glb",
	"NPCs/MageElowen": "Mage.glb",
	"NPCs/VillagerPip": "Knight.glb",
}
## Actions the FREE pack has no clip for, and the fallback each must resolve to.
const FALLBACKS := {&"attack": &"general/Throw", &"dash": &"move/Running_B"}

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var character: KayKitCharacter


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	level = (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(level)
	player = level.get_node("Player")
	character = player.get_node("Visual/Character") as KayKitCharacter
	await _frames(10)

	_test_cast()
	_test_animation_mapping()
	_test_player_body_unchanged()
	await _test_locomotion()
	await _test_combat_animations()
	await _test_npc_talk()

	print("\n=== Phase 5C character tests: %d passed, %d failed ===" % [_passes, _failures])
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
		await physics_frame


func _test_cast() -> void:
	print("[Cast]")
	var models := {}
	for path in CAST:
		var owner_node := level.get_node(path) as Node3D
		var visual := owner_node.get_node("Visual") as Node3D
		var kaykit := visual.get_node_or_null("Character") as KayKitCharacter
		_check(kaykit != null and kaykit.model != null and kaykit.model.resource_path.ends_with(CAST[path]), "%s wears %s" % [path, CAST[path]])
		if kaykit == null:
			continue
		models[kaykit.model.resource_path] = true
		var shown := visual.find_children("*", "MeshInstance3D", false, false).filter(func(m: MeshInstance3D) -> bool: return m.visible)
		_check(shown.is_empty(), "%s hides its primitive placeholder meshes (%d still visible)" % [path, shown.size()])
		var skinned := kaykit.model_root.find_children("*", "MeshInstance3D", true, false)
		_check(skinned.size() >= 6 and kaykit.skeleton != null and kaykit.skeleton.get_bone_count() == 23, "%s has a skinned Rig_Medium model (%d meshes)" % [path, skinned.size()])
		# glTF faces +Z; the visual's forward is -Z, so the model's own +Z must point along the visual's -Z.
		var model_forward := kaykit.model_root.global_basis.z.normalized()
		var visual_forward := -visual.global_basis.z.normalized()
		_check(model_forward.dot(visual_forward) > 0.99, "%s model faces the visual's forward" % path)
		var top := 0.0
		for mesh in skinned:
			top = maxf(top, ((mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()).end.y - owner_node.global_position.y)
		_check(top > 1.2 and top < 2.4, "%s stands at a sensible height (%.2f m)" % [path, top])
	_check(models.size() == CAST.size(), "every character uses a distinct model (%d)" % models.size())
	for path in ["NPCs/PostmasterBram", "NPCs/AlchemistCorvin", "NPCs/MageElowen", "NPCs/VillagerPip"]:
		var kaykit := level.get_node(path + "/Visual/Character") as KayKitCharacter
		_check(kaykit.skeleton.has_node("RightHandSlot"), "%s holds a prop" % path)


func _test_animation_mapping() -> void:
	print("[Animation clips]")
	for action in KayKitCharacter.ACTIONS:
		var clip := character.resolve(action)
		_check(clip != &"" and character.animation_player.has_animation(clip), "action %s plays existing clip %s" % [action, clip])
	for action in FALLBACKS:
		_check(character.resolve(action) == FALLBACKS[action], "missing %s clip falls back to %s" % [action, FALLBACKS[action]])
	for clip in [&"general/Idle_A", &"move/Walking_A", &"move/Running_A"]:
		_check(character.animation_player.get_animation(clip).loop_mode == Animation.LOOP_LINEAR, "%s loops" % clip)
	var track := String(character.animation_player.get_animation(&"general/Idle_A").track_get_path(0))
	_check(character.model_root.has_node(NodePath(track.get_slice(":", 0))), "animation tracks resolve to the model's skeleton (%s)" % track)


func _test_player_body_unchanged() -> void:
	print("[Player body]")
	var shape := player.get_node("CollisionShape3D") as CollisionShape3D
	var capsule := shape.shape as CapsuleShape3D
	_check(capsule != null and is_equal_approx(capsule.radius, 0.35) and is_equal_approx(capsule.height, 1.6), "player collision capsule unchanged")
	_check(player.facing.visual_root == player.get_node("Visual"), "facing still rotates the Visual node")
	_check(player.get_node("PackageCarrier").position.y > 1.9, "carried packages stay above the new model's head")


func _test_locomotion() -> void:
	print("[Locomotion]")
	player.teleport_to(Vector3(0, 0, -2))
	await _frames(20)
	_check(character.current_clip == &"general/Idle_A", "standing still plays Idle_A (%s)" % character.current_clip)
	Input.action_press(&"move_right")
	await _frames(25)
	_check(character.current_clip == &"move/Walking_A" and character.animation_player.is_playing(), "walking plays Walking_A (%s)" % character.current_clip)
	Input.action_press(&"run")
	await _frames(25)
	_check(character.current_clip == &"move/Running_A", "running plays Running_A (%s)" % character.current_clip)
	var yaw_before: float = (player.get_node("Visual") as Node3D).rotation.y
	Input.action_release(&"move_right")
	Input.action_press(&"move_left")
	await _frames(30)
	_check(absf(angle_difference(yaw_before, (player.get_node("Visual") as Node3D).rotation.y)) > 2.5, "the model turns around with the facing component")
	Input.action_release(&"move_left")
	Input.action_release(&"run")
	await _frames(40)
	_check(character.current_clip == &"general/Idle_A", "stopping returns to Idle_A (%s)" % character.current_clip)


func _test_combat_animations() -> void:
	print("[Combat]")
	var combat := CombatController.find_on(player)
	player.teleport_to(Vector3(13, 0, -24))
	await _frames(10)
	_check(combat.try_magic_bolt(Vector3(0, 0, -1)), "magic bolt still fires")
	await _frames(2)
	_check(character.current_clip == &"general/Throw", "magic bolt plays the Throw fallback (%s)" % character.current_clip)
	await _frames(90)
	_check(character.current_clip == &"general/Idle_A", "returns to idle after the cast (%s)" % character.current_clip)
	_check(combat.try_dash(Vector3(0, 0, 1)), "dash still works")
	await _frames(2)
	_check(character.current_clip == &"move/Running_B", "dash plays the Running_B fallback (%s)" % character.current_clip)
	await _frames(60)
	var health := combat.health
	health.apply_damage(5.0, player.global_position + Vector3.FORWARD)
	await _frames(2)
	_check(character.current_clip == &"general/Hit_A", "taking damage plays Hit_A (%s)" % character.current_clip)
	await _frames(60)
	health.apply_damage(9999.0, player.global_position + Vector3.FORWARD)
	# Gameplay respawns the courier on the next deferred call (health reset + teleport),
	# so the get-up clip, not the death pose, is what the player sees.
	await _frames(3)
	_check(health.get_health() > 0.0 and character.current_clip == &"general/Spawn_Ground", "knockout respawn plays the Spawn_Ground get-up (%s)" % character.current_clip)
	await _frames(120)
	_check(character.current_clip == &"general/Idle_A", "back to idle after getting up (%s)" % character.current_clip)


func _test_npc_talk() -> void:
	print("[NPC interaction]")
	var mira := level.get_node("NPCs/MerchantMira") as NPC
	var kaykit := mira.get_node("Visual/Character") as KayKitCharacter
	player.teleport_to(mira.global_position + Vector3(0, 0, 1.6))
	await _frames(10)
	_check(kaykit.current_clip in [&"general/Idle_A", &"general/Idle_B"], "Mira idles (%s)" % kaykit.current_clip)
	mira.interactable.interact(player)
	await _frames(2)
	_check(mira.speech_label.visible or mira.interaction_count > 0, "Mira's dialogue still triggers")
	_check(kaykit.current_clip == &"general/Interact", "Mira gestures while talking (%s)" % kaykit.current_clip)
	await _frames(20)
	var to_player := player.global_position - mira.global_position
	var facing := -(mira.get_node("Visual") as Node3D).global_basis.z
	_check(Vector2(facing.x, facing.z).normalized().dot(Vector2(to_player.x, to_player.z).normalized()) > 0.9, "Mira's model turns to face the courier")
