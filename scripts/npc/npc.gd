class_name NPC
extends StaticBody3D
## Phase 1 NPC: static body, colored placeholder visual, and a speech bubble
## that cycles through lines when the player interacts. A real dialogue system
## replaces the bubble in a later phase.

signal spoke(npc_name: String, line: String)

## Every NPC joins this group (minimap markers, quest waypoints).
const GROUP := &"npcs"

## Unique, stable identifier used by quests and deliveries (e.g. &"village_merchant").
@export var npc_id: StringName
@export var npc_name: String = "Villager"
@export_multiline var lines: PackedStringArray = PackedStringArray(["Hello, courier!"])
@export var body_color: Color = Color(0.8, 0.5, 0.3)
@export_range(0.5, 10.0, 0.1, "suffix:s") var bubble_duration: float = 3.0
## How quickly the NPC turns (exponential smoothing; 5 is about half a second to face someone).
@export_range(1.0, 50.0, 0.5) var turn_sharpness: float = 5.0
## Seconds an interaction keeps the NPC facing the courier (longer while a dialogue line or a
## window such as the shop is open); afterwards it turns back to its own facing.
@export_range(0.0, 30.0, 0.5, "suffix:s") var attention_seconds: float = 6.0
## The courier must stay this close for the NPC to keep turning towards them.
@export_range(0.5, 20.0, 0.5, "suffix:m") var attention_range: float = 4.5

@onready var interactable: Interactable = $Interactable
@onready var visual: Node3D = $Visual
@onready var body_mesh: MeshInstance3D = $Visual/Body
@onready var speech_label: Label3D = $SpeechLabel

var interaction_count: int = 0
var _line_index: int = 0
var _bubble_time_left: float = 0.0
var _face_yaw: float = 0.0
## The facing the NPC was placed with (visual yaw), restored after a conversation.
var _home_yaw: float = 0.0
## Who the NPC is talking to, and for how much longer it pays attention.
var _attention_target: Node3D = null
var _attention_left: float = 0.0


func _enter_tree() -> void:
	add_to_group(GROUP)


## The NPC with npc_id in the tree, or null.
static func find_by_id(tree: SceneTree, id: StringName) -> NPC:
	if id == &"":
		return null
	for node in tree.get_nodes_in_group(GROUP):
		var npc := node as NPC
		if npc != null and npc.npc_id == id:
			return npc
	return null


func _ready() -> void:
	interactable.display_name = npc_name
	interactable.interacted.connect(_on_interacted)
	var material := StandardMaterial3D.new()
	material.albedo_color = body_color
	material.roughness = 0.9
	body_mesh.material_override = material
	speech_label.visible = false
	_face_yaw = visual.rotation.y
	_home_yaw = _face_yaw


func _process(delta: float) -> void:
	_update_attention(delta)
	visual.rotation.y = lerp_angle(visual.rotation.y, _face_yaw, 1.0 - exp(-turn_sharpness * delta))
	if _bubble_time_left > 0.0:
		_bubble_time_left -= delta
		if _bubble_time_left <= 0.0:
			speech_label.visible = false


## True while the NPC is turned towards someone it is talking to.
func is_attending() -> bool:
	return _attention_target != null


## The NPC's resting facing (visual yaw, local to the body).
func get_home_yaw() -> float:
	return _home_yaw


## Turns (smoothly, about the vertical axis only) towards whoever the NPC is talking to, for
## attention_seconds or as long as a dialogue line or a window is open, while they stay within
## attention_range; then back to the home facing. NPCs never track passers-by.
func _update_attention(delta: float) -> void:
	if _attention_target == null:
		return
	if not is_instance_valid(_attention_target) or not _attention_target.is_inside_tree():
		_end_attention()
		return
	var tree := get_tree()
	var talking := tree.get_node_count_in_group(QuestJournal.MODAL_GROUP) > 0 or tree.get_node_count_in_group(DialogueBox.OPEN_GROUP) > 0
	_attention_left -= delta
	var to_target := _attention_target.global_position - global_position
	var flat := Vector2(to_target.x, to_target.z)
	if (_attention_left <= 0.0 and not talking) or flat.length() > attention_range:
		_end_attention()
		return
	if flat.length_squared() > 0.0001:
		# Visual yaw is local to this (possibly rotated) body.
		_face_yaw = FacingComponent.yaw_for_direction(to_target) - global_rotation.y


func _end_attention() -> void:
	_attention_target = null
	_attention_left = 0.0
	_face_yaw = _home_yaw


func _on_interacted(interactor: Node) -> void:
	interaction_count += 1
	if interactor is Node3D:
		_attention_target = interactor as Node3D
		_attention_left = attention_seconds
		_update_attention(0.0)
	# Child behaviours (e.g. QuestNPCBehaviour) may supply a context line first.
	var line := _line_from_behaviours(interactor)
	if line.is_empty():
		if lines.is_empty():
			return
		line = lines[_line_index % lines.size()]
		_line_index += 1
	say(line)


## Shows a speech bubble line above the NPC.
func say(line: String) -> void:
	speech_label.text = line
	speech_label.visible = true
	_bubble_time_left = bubble_duration
	spoke.emit(npc_name, line)


## Context prompt for the interaction prompt (see Interactable.get_prompt_text_for).
## Child behaviours may return a verb phrase from get_prompt_verb(npc, interactor).
func get_interaction_prompt(interactor: Node) -> String:
	for child in get_children():
		if child.has_method(&"get_prompt_verb"):
			var verb: String = child.get_prompt_verb(self, interactor)
			if not verb.is_empty():
				return "%s %s" % [verb, npc_name]
	return ""


func _line_from_behaviours(interactor: Node) -> String:
	for child in get_children():
		if child.has_method(&"get_interaction_line"):
			var line: String = child.get_interaction_line(self, interactor)
			if not line.is_empty():
				return line
	return ""
