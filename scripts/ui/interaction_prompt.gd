class_name InteractionPrompt
extends CanvasLayer
## Shows "[E] Talk to X" while the player's InteractionDetector has a focus.
## Other UI (e.g. the dialogue box) can suppress it while it owns the screen. It also
## hides while any modal window (group "ui_modal": journal, quest board) is open; the
## open quest journal additionally hides the whole layer.
##
## The key in the line is drawn as a pixel-art keycap of the actual binding
## (InputPromptLabel; label.text keeps the full "[E] ..." line). A matching keycap
## (world_badge) also floats beside the focused NPC or object; it shows only while the
## line does, and hides when it would leave the screen or cover the HUD widgets in
## InputPrompt.AVOID_GROUP (tracker, wallet, minimap, toasts, package panels, dialogue).

## Text color for context prompts (e.g. "Deliver ... to ...").
const CONTEXT_COLOR := Color(1.0, 0.86, 0.4)

@export var detector: InteractionDetector
@export var action: StringName = &"interact"
@export_group("World badge")
@export var show_world_badge: bool = true
## Badge anchor above an NPC's origin (about head height).
@export_range(0.0, 5.0, 0.05, "suffix:m") var npc_badge_height: float = 1.9
## Badge anchor above any other interactable. An Interactable (or its owner) may set
## metadata "prompt_anchor_height" to override either height.
@export_range(0.0, 5.0, 0.05, "suffix:m") var object_badge_height: float = 0.9
## Screen offset of the badge's left-centre from the projected anchor.
@export var badge_offset: Vector2 = Vector2(26, 0)

@onready var panel: Control = %PromptPanel
@onready var label: Label = %PromptLabel

var _focused: Interactable = null
var _suppressed: bool = false
var _modal_open: bool = false
## Keycap beside the focused object in the world.
var world_badge: InputPrompt
## Draws label's "[E]" as a keycap.
var label_overlay: InputPromptLabel


func _ready() -> void:
	panel.visible = false
	add_to_group(QuestJournal.HIDDEN_WHILE_OPEN_GROUP)
	label_overlay = InputPromptLabel.attach(label)
	world_badge = InputPrompt.new()
	world_badge.name = "WorldBadge"
	world_badge.actions = [action]
	world_badge.visible = false
	add_child(world_badge)
	if detector != null:
		detector.focus_changed.connect(_on_focus_changed)


func _process(_delta: float) -> void:
	var width := minf(520.0, get_viewport().get_visible_rect().size.x * 0.4)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 20)
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	# Leave room above the bottom-left key guide on narrow canvases, including
	# long tool prompts that wrap onto a second line.
	(panel.get_parent() as Control).offset_top = -200.0 if get_viewport().get_visible_rect().size.x < 1100.0 else -144.0
	if not _sync_modal() and _focused != null and is_instance_valid(_focused) and get_prompt_text() != label.text:
		# Context prompts change without a focus change (package picked up, quest advanced).
		_refresh()
	_update_world_badge()


func _physics_process(_delta: float) -> void:
	# Also checked on physics ticks: several can run before the next idle frame, and a
	# modal opened in between must not leave the prompt on screen for them.
	_sync_modal()


## Groups have no change signal, and modals come from both World/UI and gameplay.
## Returns true when the modal state changed (and the prompt was refreshed).
func _sync_modal() -> bool:
	var modal_open := get_tree().get_node_count_in_group(QuestJournal.MODAL_GROUP) > 0
	if modal_open == _modal_open:
		return false
	_modal_open = modal_open
	_refresh()
	return true


## Full prompt line for the current focus, e.g. "[E] Deliver Ordinary Parcel to Merchant Mira".
func get_prompt_text() -> String:
	if _focused == null or not is_instance_valid(_focused):
		return ""
	return "[%s] %s" % [InputHints.key_for(action), _focused.get_prompt_text_for(_interactor())]


## True when the focused object shows a context prompt instead of its default one.
func is_context_prompt() -> bool:
	return _focused != null and is_instance_valid(_focused) \
			and _focused.get_prompt_text_for(_interactor()) != _focused.get_prompt_text()


func _interactor() -> Node:
	return detector.get_parent() if detector != null else null


func set_suppressed(suppressed: bool) -> void:
	_suppressed = suppressed
	_refresh()


func _on_focus_changed(interactable: Interactable) -> void:
	_focused = interactable
	_refresh()


func _refresh() -> void:
	# Re-placed (or kept hidden) on the next frame by _update_world_badge().
	if world_badge != null:
		world_badge.visible = false
	if _focused == null or not is_instance_valid(_focused):
		panel.visible = false
		return
	label.text = get_prompt_text()
	if is_context_prompt():
		label.add_theme_color_override(&"font_color", CONTEXT_COLOR)
	else:
		label.remove_theme_color_override(&"font_color")
	panel.visible = not _suppressed and not _modal_open


## World point the badge is drawn beside, for interactable.
func get_badge_anchor(interactable: Interactable) -> Vector3:
	var owner_node := interactable.get_parent() as Node3D
	# A tool target's interaction point can sit away from its origin (the pond jetty's is on
	# the bank, the node at the pond's centre), so the badge follows the interactable.
	var base := owner_node if owner_node != null and not owner_node is ToolTarget else interactable
	var height := npc_badge_height if owner_node is NPC else object_badge_height
	if interactable.has_meta(&"prompt_anchor_height"):
		height = float(interactable.get_meta(&"prompt_anchor_height"))
	elif owner_node != null and owner_node.has_meta(&"prompt_anchor_height"):
		height = float(owner_node.get_meta(&"prompt_anchor_height"))
	return base.global_position + Vector3.UP * height


## True when rect overlaps a visible HUD widget in InputPrompt.AVOID_GROUP.
func overlaps_hud(rect: Rect2) -> bool:
	for node in get_tree().get_nodes_in_group(InputPrompt.AVOID_GROUP):
		var control := node as Control
		if control != null and control.is_visible_in_tree() and rect.intersects(control.get_global_rect()):
			return true
	return false


func _update_world_badge() -> void:
	world_badge.visible = false
	if not show_world_badge or not panel.visible or _focused == null or not is_instance_valid(_focused) 			or not _focused.enabled or not _focused.is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var anchor := get_badge_anchor(_focused)
	if camera.is_position_behind(anchor):
		return
	var badge_size := world_badge.get_combined_minimum_size()
	var rect := Rect2(camera.unproject_position(anchor) + badge_offset - Vector2(0, badge_size.y * 0.5), badge_size)
	if not get_viewport().get_visible_rect().encloses(rect) or rect.intersects(panel.get_global_rect()) or overlaps_hud(rect):
		return
	world_badge.position = rect.position
	world_badge.size = badge_size
	world_badge.visible = true
