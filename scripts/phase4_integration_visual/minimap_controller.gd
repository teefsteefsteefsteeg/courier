extends CanvasLayer
const Model = preload("res://scripts/phase4_integration_visual/minimap_model.gd")
const View = preload("res://scripts/phase4_integration_visual/minimap_view.gd")
var model = Model.new()
var compact: Control
var expanded: Control
func _ready():
	compact = View.new(); compact.custom_minimum_size = Vector2(180,180); compact.set_model(model); add_child(compact)
	compact.anchor_left=1.0; compact.anchor_right=1.0; compact.offset_left=-196; compact.offset_right=-16; compact.offset_top=70; compact.offset_bottom=250
	expanded = View.new(); expanded.circular=false; expanded.custom_minimum_size=Vector2(620,620); expanded.set_model(model); add_child(expanded)
	expanded.anchor_left=.5; expanded.anchor_right=.5; expanded.anchor_top=.5; expanded.anchor_bottom=.5; expanded.offset_left=-310; expanded.offset_right=310; expanded.offset_top=-310; expanded.offset_bottom=310; expanded.visible=false
	var p=get_tree().get_first_node_in_group(&"combat_player"); if p: model.set_player(p)
	for n in get_tree().get_nodes_in_group(&"npcs"): model.set_marker(Model.id_for_node(n,"npc"),Model.KIND_NPC,n,{"label":n.name})
	for n in get_tree().get_nodes_in_group(&"enemies"): model.set_marker(Model.id_for_node(n,"enemy"),Model.KIND_ENEMY,n)
func _process(_d):
	model.update_player_heading()
	var i=get_tree().get_first_node_in_group(&"phase4_delivery_integration")
	if i and i.get_route_target(): model.set_marker(&"objective",Model.KIND_OBJECTIVE,i.get_route_target(),{"label":i.get_objective_text()})
	else: model.remove_marker(&"objective")
	for n in get_tree().get_nodes_in_group(&"phase4_encounter_enemy"): model.set_marker(Model.id_for_node(n,"enemy"),Model.KIND_ENEMY,n)
func _unhandled_input(e):
	if e.is_action_pressed(&"toggle_map"):
		expanded.visible=!expanded.visible; get_viewport().set_input_as_handled()
