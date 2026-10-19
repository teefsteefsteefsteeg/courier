extends Node3D
## Same-world passage keeps quest, inventory, NPC, combat and portal services alive.
## Geometry comes exclusively from the Blender kit. Dungeon is a roofless cutaway at
## y=-40, below the overworld and its camera; existing overworld collision stays intact.

var _in_crypt := false
var _crossing := false
var _camera: Camera3D
var _outside_environment: Environment
var _crypt_environment: Environment
var _chest_open := false
const MapModel := preload("res://scripts/phase4_integration_visual/minimap_model.gd")
const CRYPT_MAP_RECT := Rect2(-10,-34,20,54)
var _local_map := MapModel.new()
var _map_states: Array[Dictionary] = []
var _surface_legend_visible := true


func _ready() -> void:
	$Exterior/Entrance/Interactable.interacted.connect(enter_crypt)
	$Dungeon/ReturnLanding/Interactable.interacted.connect(leave_crypt)
	$Dungeon/TreasureChest/Interactable.interacted.connect(_inspect_chest)
	_crypt_environment = Environment.new()
	_crypt_environment.background_mode = Environment.BG_COLOR
	_crypt_environment.background_color = Color(.025,.035,.065)
	_crypt_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_crypt_environment.ambient_light_color = Color(.38,.48,.65)
	_crypt_environment.ambient_light_energy = .65
	_crypt_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_crypt_environment.glow_enabled = true
	_crypt_environment.glow_intensity = .45
	_clear_trail.call_deferred()


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group(CombatController.PLAYER_GROUP) as PlayerController
	if player == null:
		return
	var inside := player.global_position.y < -20
	# Also restores lighting after an existing knockout/fast-travel returns to the surface.
	if inside != _in_crypt or _camera == null:
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return
		if not _in_crypt:
			_outside_environment = _camera.environment
		_in_crypt = inside
		_camera.environment = _crypt_environment if inside else _outside_environment
		_set_local_map(inside,player)
	if inside:
		_local_map.update_player_heading()


func _set_local_map(inside: bool, player: PlayerController) -> void:
	var level := get_parent()
	if level == null:
		return
	var controller := level.get_node_or_null("GameplayHUD/Minimap")
	if controller == null:
		return
	if not inside:
		for state in _map_states:
			var view: Control = state["view"]
			view.set_model(controller.model)
			for key in ["map_texture","map_world_rect","exploration","world_radius","fixed_center"]:
				view.set(key,state[key])
		_map_states.clear()
		controller.legend.visible = _surface_legend_visible
		controller.expanded_hint.text = "Map    [%s] / [%s] Close" % [InputHints.key_for(&"toggle_map"),InputHints.key_for(&"ui_cancel")]
		return
	_local_map.set_player(player)
	_surface_legend_visible = controller.legend.visible
	controller.legend.visible = false
	_local_map.set_marker(&"exit",MapModel.KIND_POI,$Markers/CryptArrival,{"label":"Surface stairs"})
	_local_map.set_marker(&"altar",MapModel.KIND_POI,$Dungeon/HeartAltar,{"label":"Heart altar"})
	_local_map.set_marker(&"chest",MapModel.KIND_POI,$Dungeon/TreasureChest,{"label":"Old chest"})
	# Simple architectural plan in the same world XZ coordinates as the physical rooms.
	var image := Image.create(160,432,false,Image.FORMAT_RGB8)
	image.fill(Color(.04,.06,.10))
	for y in 432:
		for x in 160:
			var p := CRYPT_MAP_RECT.position + Vector2(x+.5,y+.5)/8.0
			var in_hall := Rect2(-8,-8,16,16).has_point(p)
			var corridor := Rect2(-2,-16,4,8).has_point(p)
			var stairs := Rect2(-1.8,8,3.6,10).has_point(p)
			var arena := p.distance_to(Vector2(0,-23.5)) < 7.7
			if in_hall or corridor or stairs or arena:
				var color := Color(.35,.43,.51)
				if stairs and y % 5 < 2:
					color = color.lightened(.3)
				if arena and absf(p.distance_to(Vector2(0,-23.5))-6.4)<.12:
					color = Color(.25,.8,.7)
				image.set_pixel(x,y,color)
	var texture := ImageTexture.create_from_image(image)
	for view: Control in [controller.compact,controller.expanded]:
		var state := {"view":view}
		for key in ["map_texture","map_world_rect","exploration","world_radius","fixed_center"]:
			state[key] = view.get(key)
		_map_states.append(state)
		view.set_model(_local_map)
		view.map_texture = texture
		view.map_world_rect = CRYPT_MAP_RECT
		view.exploration = null
	controller.compact.world_radius = 13.0
	controller.expanded.fixed_center = Vector2(0,-7)
	controller.expanded.world_radius = 28.0
	controller.expanded_hint.text = "Sentinel Vault    [%s] / [%s] Close" % [InputHints.key_for(&"toggle_map"),InputHints.key_for(&"ui_cancel")]


func enter_crypt(interactor: Node) -> void:
	_cross(interactor, $Markers/CryptArrival)


func leave_crypt(interactor: Node) -> void:
	_cross(interactor, $Markers/SurfaceArrival)


func _cross(interactor: Node, destination: Marker3D) -> void:
	var player := interactor as PlayerController
	if player == null or not player.input_enabled or _crossing:
		return
	_crossing = true
	player.input_enabled = false
	var combat := CombatController.find_on(player)
	if combat != null:
		combat.cancel_dash()
		combat.cancel_melee()
	player.teleport_to(destination.global_position)
	for rig in get_parent().find_children("*", "IsoCameraRig", true, false):
		(rig as IsoCameraRig).snap_to_target()
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.input_enabled = true
	_crossing = false


func _inspect_chest(_interactor: Node) -> void:
	var hinges := $Dungeon/TreasureChest.find_children("LidHinge", "Node3D", true, false)
	if hinges.is_empty():
		return
	_chest_open = not _chest_open
	var tween := create_tween()
	tween.tween_property(hinges[0], ^"rotation_degrees:x", -100.0 if _chest_open else 0.0, .45)
	var notifier := get_parent().get_node_or_null("GameplayHUD/QuestNotification") as QuestNotification
	if notifier != null and _chest_open:
		notifier.push_message("The old chest is empty. The vault's guardian has long since gone.", QuestNotification.KIND_INFO)


func _clear_trail() -> void:
	# Clear only decorative scatter in the new trail / entrance footprint. Saved terrain,
	# buildings, authored landmarks, NPCs, quests, tools and forest delivery props stay intact.
	var level := get_parent()
	if level == null:
		return
	for path in ["VillageDressing/Trees", "VillageDressing/Details", "ForestEntrance/Trees", "Trees", "Props"]:
		var holder := level.get_node_or_null(path)
		if holder == null:
			continue
		for child in holder.get_children():
			if not child is Node3D:
				continue
			if path == "Props" and not child.name.begins_with("Rock"):
				continue
			var point := Vector2(child.global_position.x, child.global_position.z)
			var nearest := Geometry2D.get_closest_point_to_segment(point,Vector2(18,-22),Vector2(33,-32))
			var in_gate := Rect2(-35.4,5,4.8,6).has_point(point)
			if point.distance_to(nearest) < 2.4 or Rect2(27.5,-37,11,8).has_point(point) or in_gate:
				child.visible = false
				child.process_mode = Node.PROCESS_MODE_DISABLED
				for collider in child.find_children("*","CollisionShape3D",true,false):
					(collider as CollisionShape3D).set_deferred(&"disabled",true)
