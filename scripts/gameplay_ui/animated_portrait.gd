class_name AnimatedPortrait
extends SubViewport
## The courier's live HUD portrait (Phase 8): a small SubViewport with its own world that
## renders the player's own model (the KayKit Ranger, PORTRAIT_MODEL, the same scene the
## Player uses) head and shoulders, the way tools/render_courier_portrait.gd framed the old
## still. It breathes through the idle clip, glances left and right now and then, flinches
## (Hit_A) on damage, droops and slows down when health is low, and cheers (a hop) when a
## reward comes in. CombatHUD shows get_texture() in its round frame and calls react_damage()
## / set_health_ratio(); celebrate() is also called on QuestManager.quest_rewarded.
##
## Cheap by design: 128x128, no shadows, its own tiny world (nothing of the level is drawn),
## and it renders every other frame (about 30 fps).

signal reacted(kind: StringName)

const PORTRAIT_MODEL := "res://assets/characters/kaykit_adventurers/Ranger.glb"
const PIXELS := 128
const LOW_HEALTH := 0.25
## Seconds between glances (random in this range).
const GLANCE_EVERY := Vector2(3.5, 7.0)

var character: KayKitCharacter
var camera: Camera3D
## &"idle", &"hit", &"low", &"cheer" (for tests).
var mood: StringName = &"idle"
var _yaw := 0.0
var _yaw_target := 0.0
var _glance_left := 4.0
var _frame := 0
var _low := false
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	size = Vector2i(PIXELS, PIXELS)
	transparent_bg = true
	own_world_3d = true
	msaa_3d = Viewport.MSAA_2X
	render_target_update_mode = SubViewport.UPDATE_ONCE
	positional_shadow_atlas_size = 0


func _ready() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.82, 0.9)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.92, 0.8)
	key.light_energy = 1.3
	key.rotation_degrees = Vector3(-30, 35, 0)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.6, 0.7, 1.0)
	rim.light_energy = 0.6
	rim.rotation_degrees = Vector3(-10, 200, 0)
	add_child(rim)
	character = KayKitCharacter.new()
	character.name = "PortraitCourier"
	character.model = load(PORTRAIT_MODEL) as PackedScene
	add_child(character)
	camera = Camera3D.new()
	camera.fov = 26.0
	add_child(camera)
	camera.current = true
	_frame_head()
	_glance_left = _rng.randf_range(GLANCE_EVERY.x, GLANCE_EVERY.y)
	var manager := QuestManager.find(get_tree()) if is_inside_tree() else null
	if manager != null:
		manager.quest_rewarded.connect(func(_id: StringName, _reward: QuestReward) -> void: celebrate())


## Frames the head from the front-right, as the old still portrait did.
func _frame_head() -> void:
	var focus := Vector3(0, 1.35, 0)
	if character.skeleton != null:
		var skeleton := character.skeleton
		var head := skeleton.find_bone("head")
		if head >= 0:
			focus = (skeleton.global_transform * skeleton.get_bone_global_rest(head)).origin + Vector3(0, 0.16, 0)
	camera.look_at_from_position(focus + Vector3(0.75, 0.12, -2.05).normalized() * 3.5, focus, Vector3.UP)


func _process(delta: float) -> void:
	# About 30 fps: render every other frame.
	_frame += 1
	if _frame % 2 == 0:
		render_target_update_mode = SubViewport.UPDATE_ONCE
	if character == null or character.model_root == null:
		return
	_glance_left -= delta
	if _glance_left <= 0.0:
		_glance_left = _rng.randf_range(GLANCE_EVERY.x, GLANCE_EVERY.y)
		_yaw_target = 0.0 if absf(_yaw_target) > 0.01 else _rng.randf_range(-0.28, 0.28)
	_yaw = lerpf(_yaw, _yaw_target, 1.0 - exp(-4.0 * delta))
	# Glances turn the head and shoulders a little; a low courier sags forward.
	character.rotation = Vector3(0.12 if _low else 0.0, _yaw, 0.0)
	if mood != &"idle" and mood != &"low" and not character.is_playing_one_shot():
		mood = &"low" if _low else &"idle"


## A flinch for a hit that got through.
func react_damage() -> void:
	if character == null or character.animation_player == null:
		return
	character.play_once(&"hit", 1.4)
	mood = &"hit"
	reacted.emit(&"hit")


## Low health (ratio <= LOW_HEALTH) slows the breathing and sags the courier.
func set_health_ratio(ratio: float) -> void:
	var low := ratio <= LOW_HEALTH and ratio > 0.0
	if low == _low or character == null:
		return
	_low = low
	character.play_loop(&"idle", 0.6 if low else 1.0)
	if not character.is_playing_one_shot():
		mood = &"low" if low else &"idle"
	reacted.emit(&"low" if low else &"recovered")


## A happy hop for a reward or a victory.
func celebrate() -> void:
	if character == null or character.animation_player == null:
		return
	character.play_once(&"cheer", 1.3)
	mood = &"cheer"
	reacted.emit(&"cheer")


func is_low() -> bool:
	return _low
