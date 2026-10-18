extends CanvasLayer
## Village HUD minimap: a compact corner map (GameplayHUD docks it under the wallet)
## and an expanded map toggled with M. Both views draw one MinimapModel.
##
## Phase 5F:
## - The expanded map is a modal window like the journal and quest board: it will not
##   open over another one, joins "ui_modal" while open, pauses the courier's input,
##   and closes on M or Escape. The whole layer hides while the journal is open.
## - NPCs (group "npcs") are labelled with their display names.
## - The objective marker follows any contract in progress (QuestWaypoint); the Phase 4
##   Dragon Egg integration's route target still takes precedence when it has one.

signal expanded_changed(is_expanded: bool)

const Model = preload("res://scripts/phase4_integration_visual/minimap_model.gd")
const View = preload("res://scripts/phase4_integration_visual/minimap_view.gd")
const MODAL_GROUP := &"ui_modal"
const HIDDEN_BY_JOURNAL_GROUP := &"hidden_by_journal"
const OBJECTIVE_ID := &"objective"
const REFRESH_INTERVAL := 0.2
const NPC_SCAN_INTERVAL := 1.0

var model = Model.new()
var compact: Control
var expanded: Control
var expanded_hint: Label

var _player: Node = null
var _player_input_was: bool = true
var _refresh_left: float = 0.0
var _npc_scan_left: float = 0.0
## NPC marker id -> its display-name label.
var _npc_labels: Dictionary[StringName, String] = {}
## NPC marker currently hidden under the objective marker, &"" for none.
var _objective_npc: StringName = &""


func _ready():
	add_to_group(HIDDEN_BY_JOURNAL_GROUP)
	compact = View.new(); compact.custom_minimum_size = Vector2(180,180); compact.set_model(model); add_child(compact)
	compact.anchor_left=1.0; compact.anchor_right=1.0; compact.offset_left=-196; compact.offset_right=-16; compact.offset_top=70; compact.offset_bottom=250
	expanded = View.new(); expanded.circular=false; expanded.show_labels=true; expanded.custom_minimum_size=Vector2(620,620); expanded.set_model(model); add_child(expanded)
	expanded.anchor_left=.5; expanded.anchor_right=.5; expanded.anchor_top=.5; expanded.anchor_bottom=.5; expanded.offset_left=-310; expanded.offset_right=310; expanded.offset_top=-310; expanded.offset_bottom=310; expanded.visible=false
	expanded_hint = Label.new()
	expanded_hint.text = "Map    [%s] / [%s] Close" % [InputHints.key_for(&"toggle_map"), InputHints.key_for(&"ui_cancel")]
	expanded_hint.add_theme_font_size_override(&"font_size", 16)
	expanded_hint.add_theme_color_override(&"font_outline_color", Color(0.03, 0.04, 0.06))
	expanded_hint.add_theme_constant_override(&"outline_size", 6)
	expanded_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	expanded_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	expanded_hint.offset_top = 8
	expanded_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	expanded.add_child(expanded_hint)
	InputPromptLabel.attach(expanded_hint)
	compact.add_to_group(InputPrompt.AVOID_GROUP)
	expanded.add_to_group(InputPrompt.AVOID_GROUP)
	var p=get_tree().get_first_node_in_group(&"combat_player"); if p: model.set_player(p)
	_scan_npcs()
	for n in get_tree().get_nodes_in_group(&"enemies"): model.set_marker(Model.id_for_node(n,"enemy"),Model.KIND_ENEMY,n)


func _process(delta):
	model.update_player_heading()
	_npc_scan_left -= delta
	if _npc_scan_left <= 0.0:
		_npc_scan_left = NPC_SCAN_INTERVAL
		_scan_npcs()
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_INTERVAL
		refresh_objective()
	for n in get_tree().get_nodes_in_group(&"phase4_encounter_enemy"): model.set_marker(Model.id_for_node(n,"enemy"),Model.KIND_ENEMY,n)


func _unhandled_input(e):
	if e.is_action_pressed(&"toggle_map"):
		if toggle_expanded() or is_expanded():
			get_viewport().set_input_as_handled()
	elif is_expanded() and e.is_action_pressed(&"ui_cancel"):
		set_expanded(false)
		get_viewport().set_input_as_handled()


func is_expanded() -> bool:
	return expanded.visible


func toggle_expanded() -> bool:
	return set_expanded(not is_expanded())


## Returns true when the state changed. Opening is refused while another modal
## window (journal, quest board) is open.
func set_expanded(value: bool) -> bool:
	if value == is_expanded():
		return false
	if value and _other_modal_open():
		return false
	expanded.visible = value
	if value:
		add_to_group(MODAL_GROUP)
		_player = get_tree().get_first_node_in_group(&"combat_player")
		if _player != null and &"input_enabled" in _player:
			_player_input_was = bool(_player.get(&"input_enabled"))
			_player.set(&"input_enabled", false)
	else:
		if is_in_group(MODAL_GROUP):
			remove_from_group(MODAL_GROUP)
		if _player != null and is_instance_valid(_player) and &"input_enabled" in _player:
			# Deferred so the key that closed the map cannot also act on the courier this frame.
			_player.set_deferred(&"input_enabled", _player_input_was)
		_player = null
	expanded_changed.emit(value)
	return true


## Re-reads the objective marker now (also runs every REFRESH_INTERVAL).
func refresh_objective() -> void:
	var target: Node3D = null
	var label := ""
	var i=get_tree().get_first_node_in_group(&"phase4_delivery_integration")
	if i and i.get_route_target():
		target = i.get_route_target()
		label = i.get_objective_text()
	else:
		var manager := QuestManager.find(get_tree())
		var carrier: PackageCarrier = null
		var p=get_tree().get_first_node_in_group(&"combat_player")
		if p: carrier = PackageCarrier.find_on(p)
		target = QuestWaypoint.target_for(get_tree(), manager, carrier)
		if target != null:
			label = QuestWaypoint.label_for(get_tree(), manager, carrier)
	if target != null and target.is_inside_tree():
		model.set_marker(OBJECTIVE_ID,Model.KIND_OBJECTIVE,target,{"label":label})
	elif model.has_marker(OBJECTIVE_ID):
		model.remove_marker(OBJECTIVE_ID)
	# An NPC under the objective marker drops its own label so the two do not overprint.
	var objective_npc: StringName = Model.id_for_node(target,"npc") if target is NPC and target.is_inside_tree() else &""
	if objective_npc != _objective_npc:
		if model.has_marker(_objective_npc):
			model.set_marker_label(_objective_npc, _npc_labels.get(_objective_npc, ""))
		if model.has_marker(objective_npc):
			model.set_marker_label(objective_npc, "")
		_objective_npc = objective_npc


func _scan_npcs() -> void:
	for n in get_tree().get_nodes_in_group(NPC.GROUP):
		var id: StringName = Model.id_for_node(n,"npc")
		if not model.has_marker(id):
			var label: String = n.npc_name if n is NPC else String(n.name)
			_npc_labels[id] = label
			model.set_marker(id,Model.KIND_NPC,n,{"label":"" if id == _objective_npc else label})


func _other_modal_open() -> bool:
	for node in get_tree().get_nodes_in_group(MODAL_GROUP):
		if node != self:
			return true
	return false
