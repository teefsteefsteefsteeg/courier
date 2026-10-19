class_name ToolTarget
extends Node3D
## A world object the courier works with one kind of tool (Phase 5H): a fishing spot, a
## harvestable tree, a mineable rock, a dig spot or a repairable structure. Needs an
## Interactable child (layer 4): the prompt reads "[E] Chop Oak Tree", or says what is
## missing ("needs a Woodcutting axe", "regrows in 2:10"), and interacting asks the
## courier's ToolUser to start. The primary action (Space) with the tool in hand does the
## same for the target in front. ToolUser validates tool, distance and state, plays the
## tool clip `strokes` times and calls on_stroke() at each clip's impact moment, then
## complete() once: subclasses pay out there and record it in the GatheringService.
##
## target_id is the save key: unique and stable, never rename a placed one.

const GROUP := &"tool_targets"

@export var target_id: StringName
@export var display_name: String = "Something"
@export var required_tool: ItemDefinition.ToolType = ItemDefinition.ToolType.HAMMER
## Prompt verb ("Chop", "Mine", "Repair", "Fish at").
@export var verb: String = "Use"
## KayKitCharacter action played for each stroke (tool_chop, tool_hammer, ...).
@export var action: StringName = &"tool_hammer"
## Tool strokes to finish the job.
@export_range(1, 20) var strokes: int = 3
## Playback speed of the stroke clip.
@export_range(0.3, 4.0, 0.05) var stroke_speed: float = 1.3
## Furthest the courier may stand from the target's centre (XZ), metres.
@export_range(0.5, 6.0, 0.1, "suffix:m") var reach: float = 2.8
## Colour of the chips that fly on each stroke (alpha 0 = none).
@export var chip_color: Color = Color(0.55, 0.38, 0.22)
## Wobbles on each stroke (the standing tree, the rock, the damaged fence).
@export var shake_node: Node3D

var interactable: Interactable
var _shake_tween: Tween


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	for child in get_children():
		if child is Interactable:
			interactable = child
	if interactable == null:
		push_warning("ToolTarget %s has no Interactable" % name)
		return
	interactable.prompt_verb = verb
	interactable.display_name = display_name
	interactable.interacted.connect(_on_interacted)
	var service := get_service()
	if service != null:
		service.respawned.connect(func(id: StringName) -> void:
			if id == target_id:
				refresh())
		service.changed.connect(refresh)
	refresh.call_deferred()


func get_service() -> GatheringService:
	return GatheringService.find(get_tree()) if is_inside_tree() else null


## Prompt for the courier (Interactable.get_prompt_text_for asks the parent).
func get_interaction_prompt(interactor: Node) -> String:
	if not is_available():
		return "%s · %s" % [display_name, get_unavailable_text()]
	var user := ToolUser.find_on(interactor)
	var tool := user.get_equipped_tool() if user != null else null
	if tool == null or tool.tool_type != required_tool:
		return "%s %s · needs a %s" % [verb, display_name, ItemDefinition.tool_type_name(required_tool)]
	var missing := check_requirements(user)
	if not missing.is_empty():
		return "%s %s · %s" % [verb, display_name, missing]
	return "%s %s" % [verb, display_name]


## Where the courier works it (its facing target).
func get_work_point() -> Vector3:
	return global_position


## Where reach is measured from: the interaction point (a jetty's is on the bank, while
## the node sits at the pond's centre).
func get_reach_point() -> Vector3:
	return interactable.global_position if interactable != null else global_position


## Whether it can be worked at all right now (not depleted, not already repaired).
func is_available() -> bool:
	return true


## Why it is not available ("regrows in 2:10", "already repaired").
func get_unavailable_text() -> String:
	return ""


## Anything besides the tool the job needs, as a reason ("" when ready), e.g. materials.
func check_requirements(_user: ToolUser) -> String:
	return ""


## Feedback for stroke index (0-based), at the clip's impact moment.
func on_stroke(_user: ToolUser, _index: int) -> void:
	shake()
	burst_chips()


## Pays out once the last stroke lands. Returns the message to show ("+3 Wood").
func complete(_user: ToolUser) -> String:
	return ""


## Re-reads availability (visuals, prompt).
func refresh() -> void:
	if interactable != null:
		interactable.enabled = true


func shake() -> void:
	if shake_node == null:
		return
	if _shake_tween != null:
		_shake_tween.kill()
	shake_node.rotation = Vector3.ZERO
	_shake_tween = create_tween()
	var tilt := deg_to_rad(4.0)
	_shake_tween.tween_property(shake_node, ^"rotation:z", tilt, 0.05)
	_shake_tween.tween_property(shake_node, ^"rotation:z", -tilt * 0.6, 0.08)
	_shake_tween.tween_property(shake_node, ^"rotation:z", 0.0, 0.1)


## A short burst of chips (wood, stone, soil) at the work point.
func burst_chips(height: float = 0.7) -> void:
	if chip_color.a <= 0.0 or not is_inside_tree():
		return
	var chips := CPUParticles3D.new()
	chips.name = "Chips"
	chips.one_shot = true
	chips.emitting = false
	chips.amount = 14
	chips.lifetime = 0.6
	chips.explosiveness = 0.95
	chips.direction = Vector3.UP
	chips.spread = 70.0
	chips.initial_velocity_min = 2.0
	chips.initial_velocity_max = 3.5
	chips.gravity = Vector3(0, -9.8, 0)
	chips.scale_amount_min = 0.6
	chips.scale_amount_max = 1.2
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.07
	var material := StandardMaterial3D.new()
	material.albedo_color = chip_color
	mesh.material = material
	chips.mesh = mesh
	add_child(chips)
	chips.global_position = get_work_point() + Vector3.UP * height
	chips.emitting = true
	chips.finished.connect(chips.queue_free)


func _on_interacted(interactor: Node) -> void:
	var user := ToolUser.find_on(interactor)
	if user != null:
		user.begin(self)


## Shows or hides a visual and switches every collider in it on or off with it (a hidden
## tree must not keep blocking the courier).
static func set_active(node: Node3D, active: bool) -> void:
	if node == null:
		return
	node.visible = active
	var mode := Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if node is CollisionObject3D:
		node.process_mode = mode
	for body in node.find_children("*", "CollisionObject3D", true, false):
		if not body is Interactable:
			body.process_mode = mode


static func format_time(seconds: float) -> String:
	var total := ceili(seconds)
	return "%d:%02d" % [total / 60, total % 60]
