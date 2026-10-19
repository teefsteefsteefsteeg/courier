extends CanvasLayer
## Phase 4 minimap HUD: a round corner minimap docked top-right below the
## shared gameplay HUD (wallet + quest tracker), and an expanded map toggled
## with M. Both views draw one MinimapModel, so markers are registered once.
##
## Marker interface (all world positions are 3D; only X/Z are mapped):
##   set_player(node_or_position)
##   set_objective(id, node_or_position, label, color)   pinned to the rim when far
##   add_npc(node_or_position, label, id)                 returns the marker id
##   add_enemy(node_or_position, id)                      returns the marker id
##   add_marker(id, kind, node_or_position, options)      any kind, see MinimapModel
##   remove_marker(id), set_marker_state(id, state), set_route(points)
##
## Optional auto-discovery (by group / duck typing only, nothing is modified):
## the player (player_path, group `player_group`, or a node whose script class
## is PlayerController), enemies in `enemy_group`, and NPCs exposing `npc_name`.

signal expanded_changed(expanded: bool)

const Model := preload("res://scripts/phase4_integration_visual/minimap_model.gd")
const View := preload("res://scripts/phase4_integration_visual/minimap_view.gd")
const HudLayout := preload("res://scripts/phase4_integration_visual/hud_layout.gd")
## Shared UI group names (defined by the quest journal; used by name only).
const MODAL_GROUP := &"ui_modal"
const HIDDEN_BY_JOURNAL_GROUP := &"hidden_by_journal"
const HINT_HEIGHT := 18.0

@export var start_expanded := false
## Input action used when it exists in the InputMap; otherwise `toggle_key`.
@export var toggle_action: StringName = &"toggle_map"
@export var toggle_key: Key = KEY_TAB
@export var compact_size := Vector2(196, 196)
@export var compact_radius := 30.0
@export var expanded_radius := 80.0
## Stack the compact map under other top-right HUD panels.
@export var dock_top_right := true
@export var dock_sharpness := 14.0
@export var layout_interval := 0.2
## While expanded: join the shared modal group and pause player input.
@export var modal_when_expanded := true
@export var pause_player_input := true
@export var hide_with_journal := true

@export_group("Discovery")
@export var player_path: NodePath
@export var auto_discover_player := true
@export var player_group: StringName = &"player"
@export var auto_track_enemies := true
@export var enemy_group: StringName = &"enemies"
@export var auto_track_npcs := true
@export var discover_interval := 1.0

var model := Model.new()
var expanded := false
var compact_frame: Control
var compact_view: View
var hint_label: Label
var expanded_root: Control
var expanded_view: View
var expanded_title: Label

var _dock_top := -1.0
var _layout_timer := 0.0
var _discover_timer := 0.0
var _player_node: Node = null
var _player_input_was := true
var _built := false
var _auto_id := 0


func _ready() -> void:
	layer = 9
	_ensure_built()
	if hide_with_journal:
		add_to_group(HIDDEN_BY_JOURNAL_GROUP)
	if not player_path.is_empty():
		var node := get_node_or_null(player_path)
		if node is Node3D:
			set_player(node)
	_relayout(true)
	set_expanded(start_expanded)
	discover.call_deferred()


func _exit_tree() -> void:
	if expanded:
		_release_modal()


func _process(delta: float) -> void:
	model.update_player_heading()
	_discover_timer += delta
	if _discover_timer >= discover_interval:
		_discover_timer = 0.0
		discover()
	_layout_timer += delta
	if _layout_timer >= layout_interval:
		_layout_timer = 0.0
		_relayout(false)
	_ease_dock(delta)


func _unhandled_input(event: InputEvent) -> void:
	if handle_input(event):
		get_viewport().set_input_as_handled()


## Toggle on M (or `toggle_action`), close on Escape. Returns true if consumed.
func handle_input(event: InputEvent) -> bool:
	if is_toggle_event(event):
		return toggle_expanded() or expanded
	if expanded and event.is_action_pressed(&"ui_cancel"):
		set_expanded(false)
		return true
	return false


func is_toggle_event(event: InputEvent) -> bool:
	if event is InputEventKey and (event.is_echo() or not event.is_pressed()):
		return false
	if toggle_action != &"" and InputMap.has_action(toggle_action):
		return event.is_action_pressed(toggle_action)
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.physical_keycode == toggle_key or key.keycode == toggle_key
	return false


# --- expanded map ---------------------------------------------------------------

## Returns true if the state changed.
func toggle_expanded() -> bool:
	return set_expanded(not expanded)


## Returns true if the state changed. Opening is refused while another modal
## window (journal, quest board) is open.
func set_expanded(value: bool) -> bool:
	_ensure_built()
	if value == expanded:
		_apply_expanded()
		return false
	if value and _other_modal_open():
		return false
	expanded = value
	if expanded:
		_claim_modal()
	else:
		_release_modal()
	_apply_expanded()
	expanded_changed.emit(expanded)
	return true


func is_expanded() -> bool:
	return expanded


# --- marker interface -----------------------------------------------------------

func get_model() -> Model:
	return model


func set_player(target: Variant) -> void:
	_player_node = target if target is Node else null
	model.set_player(target)
	_refresh_views()


func get_player_node() -> Node:
	return _player_node if is_instance_valid(_player_node) else null


func set_objective(id: StringName, target: Variant, label := "", color := Color(0, 0, 0, 0)) -> void:
	model.set_marker(id, Model.KIND_OBJECTIVE, target, {"label": label, "color": color, "pin": true, "state": Model.STATE_NORMAL})
	_refresh_views()


func clear_objective(id: StringName) -> void:
	remove_marker(id)


func add_npc(target: Variant, label := "", id: StringName = &"") -> StringName:
	return _add(Model.KIND_NPC, target, id, {"label": label})


func add_enemy(target: Variant, id: StringName = &"") -> StringName:
	return _add(Model.KIND_ENEMY, target, id, {"state": Model.STATE_NORMAL})


func add_marker(id: StringName, kind: StringName, target: Variant, options := {}) -> void:
	model.set_marker(id, kind, target, options)
	_refresh_views()


func remove_marker(id: StringName) -> void:
	model.remove_marker(id)
	_refresh_views()


## Removes the marker that follows `node`, if any.
func remove_node_marker(node: Node) -> void:
	var id := model.find_id_for_node(node)
	if id != &"":
		remove_marker(id)


func set_marker_state(id: StringName, state: StringName) -> void:
	model.set_marker_state(id, state)


func set_node_marker_state(node: Node, state: StringName) -> void:
	var id := model.find_id_for_node(node)
	if id != &"":
		model.set_marker_state(id, state)


func set_route(world_points: PackedVector3Array) -> void:
	model.set_route(world_points)
	_refresh_views()


## Map-space point of a marker in the compact (or expanded) view; Vector2.INF
## when it is not drawn there.
func get_marker_point(id: StringName, in_expanded := false) -> Vector2:
	var view := expanded_view if in_expanded else compact_view
	view.update_view()
	return view.get_marker_point(id)


# --- discovery ------------------------------------------------------------------

## Finds the player, enemies and NPCs that are not tracked yet. Returns how many
## markers were added.
func discover() -> int:
	if not is_inside_tree():
		return 0
	var added := 0
	if auto_discover_player and get_player_node() == null and not model.has_player():
		var player := _find_player()
		if player != null:
			set_player(player)
			added += 1
	if auto_track_enemies and enemy_group != &"":
		for node in get_tree().get_nodes_in_group(enemy_group):
			if node is Node3D and model.find_id_for_node(node) == &"":
				add_enemy(node)
				added += 1
	if auto_track_npcs:
		var scene := get_tree().current_scene
		if scene != null:
			for node: Node in scene.find_children("*", "Node3D", true, false):
				if _is_npc(node) and model.find_id_for_node(node) == &"":
					add_npc(node, str(node.get(&"npc_name")))
					added += 1
	return added


# --- internals ------------------------------------------------------------------

func _add(kind: StringName, target: Variant, id: StringName, options: Dictionary) -> StringName:
	if id == &"":
		_auto_id += 1
		id = Model.id_for_node(target, String(kind)) if target is Node else StringName("%s_%d" % [kind, _auto_id])
	model.set_marker(id, kind, target, options)
	_refresh_views()
	return id


func _find_player() -> Node3D:
	if player_group != &"":
		for node in get_tree().get_nodes_in_group(player_group):
			if node is Node3D:
				return node
	var scene := get_tree().current_scene
	if scene == null:
		return null
	for node: Node in scene.find_children("*", "CharacterBody3D", true, false):
		var script := node.get_script() as Script
		if script != null and script.get_global_name() == &"PlayerController":
			return node as Node3D
	return null


func _is_npc(node: Node) -> bool:
	if not (node is Node3D) or not (&"npc_name" in node):
		return false
	var script := node.get_script() as Script
	return script != null and (script.get_global_name() == &"NPC" or &"npc_id" in node)


func _other_modal_open() -> bool:
	if not is_inside_tree():
		return false
	for node in get_tree().get_nodes_in_group(MODAL_GROUP):
		if node != self:
			return true
	return false


func _claim_modal() -> void:
	if modal_when_expanded and is_inside_tree():
		add_to_group(MODAL_GROUP)
	var player := get_player_node()
	if pause_player_input and player != null and &"input_enabled" in player:
		_player_input_was = bool(player.get(&"input_enabled"))
		player.set(&"input_enabled", false)


func _release_modal() -> void:
	if is_in_group(MODAL_GROUP):
		remove_from_group(MODAL_GROUP)
	var player := get_player_node()
	if pause_player_input and player != null and &"input_enabled" in player:
		player.set(&"input_enabled", _player_input_was)


## The compact map stays visible under the overlay so panels docked below it
## (the delivery tracker) do not jump while the expanded map is open.
func _apply_expanded() -> void:
	expanded_root.visible = expanded
	_refresh_views()


func _refresh_views() -> void:
	if not _built:
		return
	if compact_view.is_visible_in_tree() or not is_inside_tree():
		compact_view.update_view()
	if expanded_root.visible:
		expanded_view.update_view()


func _relayout(snap: bool) -> void:
	if not dock_top_right or compact_frame == null:
		return
	var target := HudLayout.reserved_top_right_bottom(compact_frame)
	if snap or _dock_top < 0.0:
		_dock_top = target
	compact_frame.set_meta(&"dock_target", target)
	HudLayout.place_top_right(compact_frame, compact_size.x, compact_size.y + HINT_HEIGHT, _dock_top)


func _ease_dock(delta: float) -> void:
	if not dock_top_right or compact_frame == null or not compact_frame.has_meta(&"dock_target"):
		return
	var target := float(compact_frame.get_meta(&"dock_target"))
	if absf(target - _dock_top) < 0.5:
		return
	_dock_top = lerpf(_dock_top, target, 1.0 - exp(-dock_sharpness * delta))
	HudLayout.place_top_right(compact_frame, compact_size.x, compact_size.y + HINT_HEIGHT, _dock_top)


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	var root := Control.new()
	root.name = "MinimapRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	compact_frame = Control.new()
	compact_frame.name = "CompactMap"
	compact_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HudLayout.set_stack_priority(compact_frame, HudLayout.PRIORITY_MINIMAP)
	HudLayout.place_top_right(compact_frame, compact_size.x, compact_size.y + HINT_HEIGHT, HudLayout.MARGIN)
	root.add_child(compact_frame)
	compact_view = View.new()
	compact_view.name = "View"
	compact_view.circular = true
	compact_view.world_radius = compact_radius
	compact_view.position = Vector2.ZERO
	compact_view.size = compact_size
	compact_view.custom_minimum_size = compact_size
	compact_view.set_model(model)
	compact_frame.add_child(compact_view)
	hint_label = _label(compact_frame, "Hint", "[M] Map", 12)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.position = Vector2(0, compact_size.y)
	hint_label.size = Vector2(compact_size.x, HINT_HEIGHT)

	expanded_root = Control.new()
	expanded_root.name = "ExpandedMap"
	expanded_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	expanded_root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(expanded_root)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.02, 0.01, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	expanded_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.12
	panel.anchor_right = 0.88
	panel.anchor_top = 0.08
	panel.anchor_bottom = 0.92
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.08, 0.06, 0.94)
	bg.border_color = Color(0.55, 1.0, 0.35, 0.7)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(10)
	bg.set_content_margin_all(14)
	panel.add_theme_stylebox_override(&"panel", bg)
	expanded_root.add_child(panel)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override(&"separation", 8)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rows)
	var header := HBoxContainer.new()
	header.name = "Header"
	rows.add_child(header)
	expanded_title = _label(header, "Title", "Map", 22)
	expanded_title.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.6))
	expanded_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(header, "CloseHint", "[M] / [Esc] Close", 14)
	expanded_view = View.new()
	expanded_view.name = "View"
	expanded_view.circular = false
	expanded_view.world_radius = expanded_radius
	expanded_view.show_labels = true
	expanded_view.marker_scale = 1.6
	expanded_view.grid_spacing = 10.0
	expanded_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	expanded_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	expanded_view.custom_minimum_size = Vector2(320, 240)
	expanded_view.set_model(model)
	rows.add_child(expanded_view)
	var legend := HBoxContainer.new()
	legend.name = "Legend"
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	legend.add_theme_constant_override(&"separation", 22)
	rows.add_child(legend)
	for entry in [[&"player", "You"], [&"objective", "Objective"], [&"npc", "Villager"], [&"enemy", "Enemy"]]:
		var item := _label(legend, "Legend_%s" % entry[0], "◆ %s" % entry[1], 14)
		item.add_theme_color_override(&"font_color", expanded_view.get_kind_color(entry[0]))
	expanded_root.visible = false


func _label(parent: Control, label_name: String, text: String, size: int) -> Label:
	var label := Label.new()
	label.name = label_name
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", Color(0.85, 0.92, 0.85))
	label.add_theme_color_override(&"font_outline_color", Color(0.02, 0.04, 0.03))
	label.add_theme_constant_override(&"outline_size", 4)
	parent.add_child(label)
	return label
