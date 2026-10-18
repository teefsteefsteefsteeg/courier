class_name KayKitCharacter
extends Node3D
## An animated KayKit Adventurers character. Instances `model` (one of the pack's
## Rig_Medium characters), gives it an AnimationPlayer with the pack's shared
## animation libraries, and maps gameplay actions to clips.
##
## The FREE pack ships General (idle, hit, death, interact, pick-up, throw,
## use-item) and MovementBasic (walk, run, jump) clips only. Actions it lacks
## fall back to the closest existing clip (see ACTIONS); nothing references a
## clip that is not in the imported files.

const LIBRARIES := {
	&"general": "res://assets/characters/kaykit_adventurers/animations/Rig_Medium_General.glb",
	&"move": "res://assets/characters/kaykit_adventurers/animations/Rig_Medium_MovementBasic.glb",
}
## Gameplay action -> candidate clips, first one present wins.
const ACTIONS := {
	&"idle": [&"general/Idle_A"],
	&"idle_alt": [&"general/Idle_B", &"general/Idle_A"],
	&"walk": [&"move/Walking_A"],
	&"run": [&"move/Running_A"],
	&"airborne": [&"move/Jump_Idle", &"general/Idle_A"],
	# No attack or dash clips in the FREE pack: a cast-like throw and a fast run.
	&"attack": [&"general/Attack", &"general/Throw", &"general/Use_Item"],
	&"dash": [&"move/Dash", &"move/Running_B", &"move/Running_A"],
	&"hit": [&"general/Hit_A"],
	&"death": [&"general/Death_A"],
	&"revive": [&"general/Spawn_Ground", &"general/Idle_A"],
	&"interact": [&"general/Interact"],
	&"pickup": [&"general/PickUp"],
}
## Clips that loop (the imported files mark every clip as play-once).
const LOOPING := [&"general/Idle_A", &"general/Idle_B", &"move/Walking_A", &"move/Running_A", &"move/Running_B", &"move/Jump_Idle"]

@export var model: PackedScene
@export var model_scale: float = 0.85
## Optional prop held in the right hand (staff, mug, ...).
@export var held_item: PackedScene
@export var held_item_transform := Transform3D.IDENTITY
## NPCs occasionally swap to the second idle so a crowd does not move in lockstep.
@export var idle_variation: bool = false

var animation_player: AnimationPlayer
var model_root: Node3D
var skeleton: Skeleton3D
var current_loop: StringName = &"idle"
var current_clip: StringName = &""
## Action of the one-shot playing now (&"" when the base loop is playing).
var one_shot_action: StringName = &""

static var _libraries: Dictionary = {}
var _one_shot := false
var _hold := false
var _idle_timer := 0.0
## Seconds until a one-shot on a looping clip ends (negative: wait for animation_finished).
## A looping clip never emits animation_finished, so without this the one-shot would
## never end and every later play_loop() would be swallowed (e.g. the dash, which falls
## back to the looping Running_B clip, kept the courier running in place).
var _one_shot_left := -1.0


func _ready() -> void:
	if model == null:
		return
	model_root = model.instantiate() as Node3D
	model_root.name = "Model"
	# glTF characters face +Z; gameplay visuals face -Z.
	model_root.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * model_scale), Vector3.ZERO)
	add_child(model_root)
	skeleton = model_root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	animation_player = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	model_root.add_child(animation_player)
	animation_player.root_node = animation_player.get_path_to(model_root)
	for key in LIBRARIES:
		animation_player.add_animation_library(key, _library(key))
	animation_player.animation_finished.connect(_on_animation_finished)
	if held_item != null:
		var slot := BoneAttachment3D.new()
		slot.name = "RightHandSlot"
		skeleton.add_child(slot)
		slot.bone_name = "handslot.r"
		var item := held_item.instantiate() as Node3D
		item.transform = held_item_transform
		slot.add_child(item)
	_idle_timer = randf_range(4.0, 9.0)
	play_loop(&"idle")


func _process(delta: float) -> void:
	if _one_shot and not _hold and _one_shot_left > 0.0:
		_one_shot_left -= delta
		if _one_shot_left <= 0.0:
			_finish_one_shot()
	if not idle_variation or _one_shot or current_loop != &"idle":
		return
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_idle_timer = randf_range(6.0, 12.0)
		play_once(&"idle_alt")


## Full clip name ("library/clip") the action maps to, or &"" if none exists.
func resolve(action: StringName) -> StringName:
	if animation_player == null:
		return &""
	for clip in ACTIONS.get(action, [action]):
		if animation_player.has_animation(clip):
			return clip
	return &""


func has_action(action: StringName) -> bool:
	return resolve(action) != &""


## Sets the looping base animation (idle/walk/run). A playing one-shot finishes first.
func play_loop(action: StringName, speed: float = 1.0) -> void:
	current_loop = action
	if _one_shot or _hold:
		return
	_play(action, speed, 0.2)


## Plays a one-shot (attack, hit, ...) and returns to the current loop afterwards.
## `hold` keeps the last frame (death) until `release()`.
func play_once(action: StringName, speed: float = 1.0, hold: bool = false) -> void:
	if _play(action, speed, 0.1):
		_one_shot = true
		_hold = hold
		one_shot_action = action
		# A looping clip plays one cycle; a play-once clip ends on animation_finished.
		var animation := animation_player.get_animation(current_clip)
		_one_shot_left = animation.length / maxf(absf(speed), 0.01) \
				if animation.loop_mode != Animation.LOOP_NONE and not hold else -1.0


## Ends the one-shot now and returns to the current loop, when the one-shot is `action`
## (any one-shot when empty). Held poses are left alone. Use it when the gameplay action
## behind a one-shot ends before its clip does (a dash is shorter than its run clip).
func end_once(action: StringName = &"") -> void:
	if not _one_shot or _hold or (action != &"" and action != one_shot_action):
		return
	_finish_one_shot()


func is_playing_one_shot() -> bool:
	return _one_shot


## Leaves a held pose (e.g. after a knockout respawn).
func release() -> void:
	_hold = false
	_finish_one_shot()


func _play(action: StringName, speed: float, blend: float) -> bool:
	var clip := resolve(action)
	if clip == &"":
		return false
	current_clip = clip
	animation_player.play(clip, blend, speed)
	return true


func _on_animation_finished(_clip: StringName) -> void:
	if _hold:
		return
	_finish_one_shot()


func _finish_one_shot() -> void:
	_one_shot = false
	one_shot_action = &""
	_one_shot_left = -1.0
	_play(current_loop, 1.0, 0.2)


static func _library(key: StringName) -> AnimationLibrary:
	if _libraries.has(key):
		return _libraries[key]
	var source := (load(LIBRARIES[key]) as PackedScene).instantiate()
	var player := source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var library := AnimationLibrary.new()
	for clip_name in player.get_animation_list():
		var animation := player.get_animation(clip_name).duplicate() as Animation
		if StringName("%s/%s" % [key, clip_name]) in LOOPING:
			animation.loop_mode = Animation.LOOP_LINEAR
		library.add_animation(clip_name, animation)
	source.free()
	_libraries[key] = library
	return library
