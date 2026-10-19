extends Node
## Persistent-session scene transitions. Only the level scene changes. The single
## Player, CombatHealth, services, quest instances, inventory, carrier and HUD stay alive.
signal region_changed(region_id: StringName)
const OUTDOOR := "res://scenes/phase6/runewood_outdoors.tscn"
const DUNGEON := "res://scenes/phase6/sentinel_dungeon.tscn"
const MapModel := preload("res://scripts/phase4_integration_visual/minimap_model.gd")
const REGION_TOOL_SITES := {"runewood": "res://scenes/world/tools/runewood_tool_sites.tscn"}
## Phase 8 interiors: enterable buildings of the village (HouseDoor -> region id). Each is a
## region of its own (the village is paused while the courier is inside), and leaving puts
## the courier back at the door it came in by.
const INTERIORS := {
	"interior_armory": "res://scenes/interiors/armory_forge.tscn",
	"interior_guild_hall": "res://scenes/interiors/guild_hall.tscn",
	"interior_rose_cottage": "res://scenes/interiors/rose_cottage.tscn",
}
var region_id: StringName = &"village"
var active_level: Node3D
var crossing := false
var _village_states: Array[Dictionary] = []
var _level_cache: Dictionary = {}
var _outside_env: Environment
var _map_states: Array[Dictionary] = []
var _map_model := MapModel.new()
var _player: PlayerController
var _village_spawn := Vector3(33,.1,-30.5)
## Where the courier comes back out (the door of the building it entered); INF = the gateway.
var _village_return := Vector3.INF
var _recovering := false
var _village_respawn_enabled := true


func _ready() -> void:
	add_to_group(&"phase6_router")
	_bind.call_deferred()


func _bind() -> void:
	# World/UI previews intentionally omit GameplayServices and cannot travel.
	var exploration := ExplorationService.find(get_tree())
	if exploration == null:
		return
	_player = get_parent().get_node("Player") as PlayerController
	get_parent().get_node("Phase6Gateway/Entrance/Interactable").interacted.connect(func(p: Node) -> void: travel(&"runewood",&"Arrival",p))
	CombatHealth.find_on(_player).died.connect(_on_knockout)
	# A session always starts in the village; retain each saved region's fog grid.
	exploration.set_region(&"village")
	_clear_gateway_trail()


static func find(tree: SceneTree) -> Node:
	return tree.get_first_node_in_group(&"phase6_router")


func _process(_delta: float) -> void:
	if region_id != &"village":
		_map_model.update_player_heading()


## Goes to region next at its spawn marker. return_point (Phase 8 house doors) is where the
## courier reappears when it later comes back to the village.
func travel(next: StringName, spawn: StringName, interactor: Node = null, return_point: Vector3 = Vector3.INF) -> bool:
	if crossing or (interactor != null and interactor != _player) or not _player.input_enabled:
		return false
	if next not in [&"village",&"runewood",&"sentinel_vault"] and not INTERIORS.has(String(next)):
		return false
	if region_id == &"village" and next != &"village":
		_village_return = return_point
	crossing = true
	_cross.call_deferred(next,spawn)
	return true


func _cross(next: StringName, spawn: StringName) -> void:
	var previous_interior := is_interior(region_id)
	_player.input_enabled = false
	var combat := CombatController.find_on(_player)
	combat.cancel_dash()
	combat.cancel_melee()
	var camera := get_viewport().get_camera_3d()
	if region_id == &"village":
		_outside_env = camera.environment if camera.environment != null else get_parent().get_node("WorldEnvironment").environment
		get_parent().get_node("WorldEnvironment").environment=null
		_pause_village()
	if active_level != null:
		var container := active_level.get_parent()
		container.remove_child(active_level)
		_level_cache[String(region_id)] = active_level
		active_level = null
	region_id = next
	var exploration := ExplorationService.find(get_tree())
	# Interiors keep the village's fog of war and map (they are part of the village).
	if not is_interior(next):
		exploration.set_region(next)
	if next == &"village":
		_resume_village()
		get_parent().get_node("WorldEnvironment").environment=_outside_env
		_player.teleport_to(_village_return if _village_return.is_finite() else _village_spawn)
		_village_return = Vector3.INF
		camera.environment = _outside_env
		_restore_map()
	else:
		if _level_cache.has(String(next)):
			active_level = _level_cache[String(next)]
			_level_cache.erase(String(next))
		else:
			active_level = (load(_scene_for(next)) as PackedScene).instantiate() as Node3D
			# Phase 8: tool sites (trees, ore, soil, fishing water) of a generated region come
			# from their own scene and snap onto its terrain (GroundSnap).
			if REGION_TOOL_SITES.has(String(next)):
				active_level.add_child((load(REGION_TOOL_SITES[String(next)]) as PackedScene).instantiate())
		get_parent().add_child(active_level)
		active_level.set_meta(&"router",self)
		var marker := active_level.get_node("Spawns/"+String(spawn)) as Marker3D
		_player.teleport_to(marker.global_position)
		camera.environment = active_level.get_node("WorldEnvironment").environment
		_setup_map()
	for rig: IsoCameraRig in get_parent().find_children("*","IsoCameraRig",true,false):
		rig.snap_to_target()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_player.input_enabled = true
	crossing = false
	region_changed.emit(region_id)
	var notice := get_parent().get_node_or_null("GameplayHUD/QuestNotification") as QuestNotification
	if notice != null:
		var text := "Returned to Willowmere."
		if next == &"runewood":
			text = "Runewood Highlands — follow the ochre road to the northern crypt."
		elif next == &"sentinel_vault":
			text = "The Sentinel Vault — the stairs behind you lead out."
		elif is_interior(next):
			var place := String(active_level.get(&"display_name"))
			text = "%s — the door behind you leads out." % (place.left(1).to_upper() + place.substr(1))
		elif previous_interior:
			text = ""
		if not text.is_empty():
			notice.push_message(text,QuestNotification.KIND_INFO)


func _pause_village() -> void:
	for child in get_parent().get_children():
		if child == self or child.name in ["GameplayServices","Player","IsoCameraRig"] or child is CanvasLayer:
			continue
		var state := {"node":child,"mode":child.process_mode,"shapes":[],"canvases":[]}
		if child is Node3D:
			state["visible"] = child.visible
			child.visible = false
		child.process_mode = Node.PROCESS_MODE_DISABLED
		# Persistent combat HUDs can live below a paused world integration node.
		# Keep their cooldowns and transient damage notices advancing while away.
		for canvas: CanvasLayer in child.find_children("*","CanvasLayer",true,false):
			state["canvases"].append([canvas,canvas.process_mode])
			canvas.process_mode = Node.PROCESS_MODE_PAUSABLE
		for shape: CollisionShape3D in child.find_children("*","CollisionShape3D",true,false):
			state["shapes"].append([shape,shape.disabled])
			shape.set_deferred(&"disabled",true)
		_village_states.append(state)
	var integration := get_parent().get_node("Phase4DeliveryIntegration")
	_village_respawn_enabled = integration.respawn_on_knockout
	integration.respawn_on_knockout = false


func _resume_village() -> void:
	for state in _village_states:
		var node: Node = state["node"]
		node.process_mode = state["mode"]
		if node is Node3D:
			node.visible = state["visible"]
		for pair: Array in state["canvases"]:
			if is_instance_valid(pair[0]):
				pair[0].process_mode = pair[1]
		for pair: Array in state["shapes"]:
			if is_instance_valid(pair[0]):
				pair[0].set_deferred(&"disabled",pair[1])
	_village_states.clear()
	get_parent().get_node("Phase4DeliveryIntegration").respawn_on_knockout = _village_respawn_enabled


func is_interior(id: StringName) -> bool:
	return INTERIORS.has(String(id))


func _scene_for(id: StringName) -> String:
	if INTERIORS.has(String(id)):
		return INTERIORS[String(id)]
	return OUTDOOR if id == &"runewood" else DUNGEON


func _setup_map() -> void:
	var controller := get_parent().get_node("GameplayHUD/Minimap")
	if is_interior(region_id):
		# Indoors: no minimap and no world map (the village map stays as it was).
		controller.compact.visible = false
		controller.set_process_input(false)
		return
	if _map_states.is_empty():
		for view: Control in [controller.compact,controller.expanded]:
			var state := {"view":view}
			for key in ["map_texture","map_world_rect","world_radius","fixed_center"]:
				state[key] = view.get(key)
			_map_states.append(state)
	_map_model.clear_markers()
	_map_model.set_player(_player)
	for enemy in active_level.find_children("*","Enemy",true,false):
		_map_model.set_marker(MapModel.id_for_node(enemy,"enemy"),MapModel.KIND_ENEMY,enemy)
	for view: Control in [controller.compact,controller.expanded]:
		view.set_model(_map_model)
		view.map_texture = load("res://assets/generated/phase6/"+("runewood_map.png" if region_id==&"runewood" else "vault_map.png"))
		view.map_world_rect = ExplorationService.WORLD_RECT
		view.exploration = ExplorationService.find(get_tree())
	controller.compact.world_radius = 17.0
	controller.expanded.world_radius = 60.0 if region_id==&"runewood" else 29.0
	controller.expanded.fixed_center = Vector2.ZERO if region_id==&"runewood" else Vector2(-8,-7)
	controller.expanded_hint.text = ("Runewood Highlands" if region_id==&"runewood" else "Sentinel Vault")+"    [%s] / [%s] Close"%[InputHints.key_for(&"toggle_map"),InputHints.key_for(&"ui_cancel")]
	controller.legend.visible = region_id==&"runewood"


func _restore_map() -> void:
	var controller := get_parent().get_node("GameplayHUD/Minimap")
	controller.compact.visible = true
	controller.set_process_input(true)
	for state in _map_states:
		var view: Control = state["view"]
		view.set_model(controller.model)
		for key in ["map_texture","map_world_rect","world_radius","fixed_center"]:
			view.set(key,state[key])
	_map_states.clear()
	controller.legend.visible = true
	controller.expanded_hint.text = "Map    [%s] / [%s] Close"%[InputHints.key_for(&"toggle_map"),InputHints.key_for(&"ui_cancel")]


func claim_victory() -> bool:
	var save := SaveGame.find(get_tree())
	if save.world_progress.get("sentinel_defeated",false):
		return false
	save.world_progress["sentinel_defeated"] = true
	var wallet := CourierWallet.find(get_tree())
	wallet.add_gold(300)
	wallet.add_reputation(25)
	save.request_save()
	get_parent().get_node("GameplayHUD/QuestNotification").push_message("Sentinel defeated! +300 gold, +25 reputation. The vault is yours to explore.",QuestNotification.KIND_SUCCESS)
	return true


func _on_knockout() -> void:
	if region_id == &"village" or _recovering:
		return
	_recovering = true
	await get_tree().create_timer(1.0).timeout
	var health := CombatHealth.find_on(_player)
	health.reset()
	_player.input_enabled = true
	# Knocked out indoors: back out of the door; elsewhere: the Runewood arrival.
	if is_interior(region_id):
		travel(&"village",&"",_player)
	else:
		travel(&"runewood",&"Arrival",_player)
	_recovering = false


func _clear_gateway_trail() -> void:
	for path in ["VillageDressing/Trees","VillageDressing/Details","ForestEntrance/Trees","Props"]:
		var holder := get_parent().get_node_or_null(path)
		if holder == null: continue
		for node in holder.get_children():
			if not node is Node3D or (path=="Props" and not node.name.begins_with("Rock")): continue
			var p := Vector2(node.global_position.x,node.global_position.z)
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p,Vector2(18,-22),Vector2(33,-32))) < 2.5 or Rect2(27,-37,12,8).has_point(p):
				node.visible = false
				for s: CollisionShape3D in node.find_children("*","CollisionShape3D",true,false): s.set_deferred(&"disabled",true)


func _exit_tree() -> void:
	for node in _level_cache.values():
		if is_instance_valid(node): node.free()
	_level_cache.clear()
