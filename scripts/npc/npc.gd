class_name NPC
extends StaticBody3D
## Phase 1 NPC: static body, colored placeholder visual, and a speech bubble
## that cycles through lines when the player interacts. A real dialogue system
## replaces the bubble in a later phase.

signal spoke(npc_name: String, line: String)

@export var npc_name: String = "Villager"
@export_multiline var lines: PackedStringArray = PackedStringArray(["Hello, courier!"])
@export var body_color: Color = Color(0.8, 0.5, 0.3)
@export_range(0.5, 10.0, 0.1, "suffix:s") var bubble_duration: float = 3.0
@export_range(1.0, 50.0, 0.5) var turn_sharpness: float = 10.0

@onready var interactable: Interactable = $Interactable
@onready var visual: Node3D = $Visual
@onready var body_mesh: MeshInstance3D = $Visual/Body
@onready var speech_label: Label3D = $SpeechLabel

var interaction_count: int = 0
var _line_index: int = 0
var _bubble_time_left: float = 0.0
var _face_yaw: float = 0.0


func _ready() -> void:
	interactable.display_name = npc_name
	interactable.interacted.connect(_on_interacted)
	var material := StandardMaterial3D.new()
	material.albedo_color = body_color
	material.roughness = 0.9
	body_mesh.material_override = material
	speech_label.visible = false
	_face_yaw = visual.rotation.y


func _process(delta: float) -> void:
	visual.rotation.y = lerp_angle(visual.rotation.y, _face_yaw, 1.0 - exp(-turn_sharpness * delta))
	if _bubble_time_left > 0.0:
		_bubble_time_left -= delta
		if _bubble_time_left <= 0.0:
			speech_label.visible = false


func _on_interacted(interactor: Node) -> void:
	interaction_count += 1
	if interactor is Node3D:
		var to_interactor: Vector3 = (interactor as Node3D).global_position - global_position
		if Vector2(to_interactor.x, to_interactor.z).length_squared() > 0.0001:
			# Visual yaw is local to this (possibly rotated) body.
			_face_yaw = FacingComponent.yaw_for_direction(to_interactor) - global_rotation.y
	if lines.is_empty():
		return
	var line := lines[_line_index % lines.size()]
	_line_index += 1
	speech_label.text = line
	speech_label.visible = true
	_bubble_time_left = bubble_duration
	spoke.emit(npc_name, line)
