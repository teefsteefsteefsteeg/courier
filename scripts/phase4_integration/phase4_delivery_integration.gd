class_name Phase4DeliveryIntegration
extends Node3D
## Phase 4 playable delivery: wires the existing Dragon Egg contract (Q002) to Phase 4
## combat without owning any core system. QuestManager still owns quest state and
## rewards, PackageCarrier owns the egg, the player's Combat child owns Magic Bolt /
## Dash / Package Shield and package impact, and ForestSlime / FrostWisp own their AI.
## This node only decides *when and where* enemies exist and what the courier is told:
##
## - The village is always safe. Encounters run only while Q002 is ACCEPTED/ACTIVE, the
##   egg has been picked up, and the courier is inside the forest bounds (the existing
##   ForestZone shape, with exit_margin hysteresis). Leaving the forest, delivering,
##   failing, or being knocked out frees every encounter enemy and projectile.
## - Each Phase4EncounterSpawnPoint child holds one enemy. Defeated or leashed enemies
##   respawn after the point's respawn_delay, never closer than min_respawn_distance to
##   the courier (the first wave of an encounter ignores that distance).
## - Damage that reaches the courier while carrying the egg is turned into package impact
##   by CombatController; this node only reports it (package_impacted, package_hits).
## - Objective text and a world route marker follow the current Q002 objective
##   (pickup -> Forest Clearing -> Mage Elowen, or a dropped egg).
## - A knocked-out courier wakes at knockout_respawn with full health; the egg takes
##   knockout_package_impact.
##
## Timers only advance in advance(delta), called each physics frame while simulate is on,
## so tests can drive the integration with exact deltas.

signal run_state_changed(new_state: RunState, old_state: RunState)
signal encounter_started
## reason: &"left_forest", &"delivered", &"quest_failed", &"quest_inactive",
## &"knocked_out" or &"village_safe".
signal encounter_cleared(reason: StringName)
signal enemy_spawned(enemy: Enemy, spawn_point: Phase4EncounterSpawnPoint)
signal enemy_defeated(enemy: Enemy, spawn_point: Phase4EncounterSpawnPoint)
## A Magic Bolt damaged an encounter enemy.
signal enemy_hit(enemy: Enemy, amount: float)
## Damage reached the courier while carrying the quest package; force is the impact
## CombatController applied to it.
signal package_impacted(package: PackageInstance, force: float)
signal objective_changed(text: String)
## null when there is nothing to point at.
signal route_target_changed(target: Node3D)
signal courier_knocked_out
signal delivery_completed(quest_id: StringName, reward: QuestReward)
signal delivery_failed(quest_id: StringName, reason: String)

## IDLE: no armed Dragon Egg run. ARMED: run in progress, courier outside the forest
## (village safe). IN_FOREST: encounter running. DELIVERED / FAILED: run finished.
enum RunState { IDLE, ARMED, IN_FOREST, DELIVERED, FAILED }

const GROUP := &"phase4_delivery_integration"
## Every enemy spawned by the integration joins this group.
const ENEMY_GROUP := &"phase4_encounter_enemy"
## Phase 4 visual layer, instanced at runtime when present (owned by the visual work).
const VISUAL_LAYER_PATH := "res://scenes/gameplay/phase4_integration_visual/encounter_presentation.tscn"
const VISUAL_LAYER_NAME := &"Phase4EncounterPresentation"

@export var quest_id: StringName = &"q002_dragon_egg"
## Defaults to QuestManager.find().
@export var quest_manager: QuestManager
## Defaults to the first body in CombatController.PLAYER_GROUP.
@export var player: CharacterBody3D
## Forest area whose first BoxShape3D child defines the encounter bounds.
@export var forest_zone: Area3D
## XZ bounds used when forest_zone is not set (x, z, width, depth).
@export var forest_bounds := Rect2(-2.0, -44.0, 32.0, 24.0)
## Once inside, the courier counts as in the forest until this far outside the bounds.
@export_range(0.0, 10.0, 0.1, "suffix:m") var exit_margin: float = 1.5
## Encounter enemies further than this outside the bounds are removed (and respawn).
@export_range(0.0, 20.0, 0.1, "suffix:m") var enemy_leash_margin: float = 3.0
## Encounters start only after the package pickup objective is done.
@export var require_package_picked_up: bool = true
@export_range(0.0, 50.0, 0.1, "suffix:m") var min_respawn_distance: float = 8.0
@export var simulate: bool = true
## Passed to each spawned Enemy.simulate (tests turn it off).
@export var simulate_enemies: bool = true

@export_group("Route")
@export var show_route_marker: bool = true
## Route target while the package still has to be picked up.
@export var pickup_target: Node3D
## Route target for the REACH_DESTINATION objective.
@export var destination_target: Node3D
## Route target for the DELIVER_PACKAGE objective.
@export var recipient_target: Node3D

@export_group("Knockout")
@export var respawn_on_knockout: bool = true
@export var knockout_respawn: Node3D
## Impact force applied to the carried quest package when the courier is knocked out.
@export var knockout_package_impact: float = 5.0

@export_group("Visual Layer")
@export var instance_visual_layer: bool = true

var enemies_defeated: int = 0
var bolt_hits: int = 0
var package_hits: int = 0
var package_impact_total: float = 0.0
var knockouts: int = 0

var _run_state: RunState = RunState.IDLE
var _player_in_forest: bool = false
var _encounter_live: bool = false
var _spawn_points: Array[Phase4EncounterSpawnPoint] = []
var _combat: CombatController = null
var _health: CombatHealth = null
var _carrier: PackageCarrier = null
var _objective_text: String = ""
var _route_target: Node3D = null
var _last_reward: QuestReward = null
var _visual_layer: Node = null

@onready var _enemy_root: Node3D = $Enemies
@onready var _spawn_root: Node3D = $SpawnPoints
@onready var _route_marker: Node3D = $RouteMarker
@onready var _route_label: Label3D = $RouteMarker/Label


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	for child in _spawn_root.get_children():
		if child is Phase4EncounterSpawnPoint:
			_spawn_points.append(child)
	if quest_manager == null:
		quest_manager = QuestManager.find(get_tree())
	if player == null:
		player = get_tree().get_first_node_in_group(CombatController.PLAYER_GROUP) as CharacterBody3D
	_connect_quest_manager()
	_connect_player()
	_route_marker.visible = false
	_attach_visual_layer()
	_sync_state()
	_refresh_objective()
	_update_route_marker()


func _physics_process(delta: float) -> void:
	if simulate:
		advance(delta)


static func find(tree: SceneTree) -> Phase4DeliveryIntegration:
	return tree.get_first_node_in_group(GROUP) as Phase4DeliveryIntegration


## Updates forest presence, run state, spawns/respawns, objective and route marker.
func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	_update_forest_presence()
	_sync_state()
	if _run_state == RunState.IN_FOREST:
		_leash_enemies()
		_step_spawns(delta)
	elif get_live_enemy_count() > 0:
		clear_encounter(&"village_safe")
	_refresh_objective()
	_update_route_marker()


# --- queries ---------------------------------------------------------------------

func get_run_state() -> RunState:
	return _run_state


func get_run_state_name() -> String:
	return RunState.keys()[_run_state]


func is_encounter_active() -> bool:
	return _run_state == RunState.IN_FOREST


func is_player_in_forest() -> bool:
	return _player_in_forest


## True while Q002 is in progress and (when required) its package was picked up.
func is_run_armed() -> bool:
	if quest_manager == null:
		return false
	var state := quest_manager.get_state(quest_id)
	if state == null or not state.is_in_progress():
		return false
	if not require_package_picked_up:
		return true
	var objective := quest_manager.get_current_objective(quest_id)
	return objective != null and objective.type != QuestObjective.Type.PICK_UP_PACKAGE


## XZ rectangle of the forest (from forest_zone when set, else forest_bounds).
func get_forest_rect() -> Rect2:
	if forest_zone != null and is_instance_valid(forest_zone):
		for child in forest_zone.get_children():
			var shape_node := child as CollisionShape3D
			if shape_node != null and shape_node.shape is BoxShape3D:
				var size := (shape_node.shape as BoxShape3D).size
				var xform := shape_node.global_transform if shape_node.is_inside_tree() else forest_zone.transform * shape_node.transform
				var box := xform * AABB(-size * 0.5, size)
				return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
	return forest_bounds


func is_in_forest(world_position: Vector3, margin: float = 0.0) -> bool:
	return get_forest_rect().grow(margin).has_point(Vector2(world_position.x, world_position.z))


func get_spawn_points() -> Array[Phase4EncounterSpawnPoint]:
	return _spawn_points.duplicate()


func get_live_enemies() -> Array[Enemy]:
	var result: Array[Enemy] = []
	if _enemy_root == null:
		return result
	for child in _enemy_root.get_children():
		var enemy := child as Enemy
		if enemy != null and not enemy.is_queued_for_deletion() and not enemy.is_dead():
			result.append(enemy)
	return result


func get_live_enemy_count() -> int:
	return get_live_enemies().size()


func get_objective_text() -> String:
	if quest_manager == null:
		return ""
	var definition := quest_manager.get_definition(quest_id)
	if definition == null:
		return ""
	match quest_manager.get_status(quest_id):
		QuestState.Status.COMPLETED, QuestState.Status.REWARDED:
			if _last_reward != null:
				return "%s delivered to %s (+%d gold, +%d reputation)" % [_package_name(definition), definition.recipient_name, _last_reward.gold, _last_reward.reputation]
			return "%s delivered to %s" % [_package_name(definition), definition.recipient_name]
		QuestState.Status.FAILED:
			var reason := quest_manager.get_state(quest_id).fail_reason
			return "Delivery failed: %s" % reason if not reason.is_empty() else "Delivery failed"
	var objective := quest_manager.get_current_objective(quest_id)
	if objective == null:
		return ""
	var text := objective.description
	if is_package_dropped():
		text = "Recover the dropped %s" % _package_name(definition)
	var hostiles := get_live_enemy_count()
	if _run_state == RunState.IN_FOREST and hostiles > 0:
		text += " - %d %s nearby" % [hostiles, "hostile" if hostiles == 1 else "hostiles"]
	return text


## Node the route marker points at for the current objective, or null.
func get_route_target() -> Node3D:
	if quest_manager == null:
		return null
	var objective := quest_manager.get_current_objective(quest_id)
	if objective == null:
		return null
	if objective.type == QuestObjective.Type.PICK_UP_PACKAGE:
		return _valid_target(pickup_target)
	if not is_carrying_quest_package():
		var dropped := find_dropped_package_pickup()
		if dropped != null:
			return dropped
	match objective.type:
		QuestObjective.Type.REACH_DESTINATION:
			return _valid_target(destination_target)
		QuestObjective.Type.DELIVER_PACKAGE:
			return _valid_target(recipient_target)
	return null


func is_carrying_quest_package() -> bool:
	return _carrier != null and _carrier.is_carrying() and _carrier.get_package().get_quest_id() == quest_id


## True when the run is past pickup but the courier is not holding the package.
func is_package_dropped() -> bool:
	if quest_manager == null or is_carrying_quest_package():
		return false
	var objective := quest_manager.get_current_objective(quest_id)
	return objective != null and objective.type != QuestObjective.Type.PICK_UP_PACKAGE


## The PackagePickup PackageCarrier spawned when the quest package was dropped.
func find_dropped_package_pickup() -> PackagePickup:
	if not is_inside_tree():
		return null
	var scene_root: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	for child in scene_root.get_children():
		var pickup := child as PackagePickup
		if pickup != null and not pickup.is_queued_for_deletion() and pickup.package_instance != null and pickup.package_instance.get_quest_id() == quest_id:
			return pickup
	return null


func get_visual_layer() -> Node:
	return _visual_layer if is_instance_valid(_visual_layer) else null


func get_run_stats() -> Dictionary:
	return {
		"enemies_defeated": enemies_defeated,
		"bolt_hits": bolt_hits,
		"package_hits": package_hits,
		"package_impact_total": package_impact_total,
		"knockouts": knockouts,
	}


# --- encounter -------------------------------------------------------------------

## Spawns point's enemy now. Returns null if the point has no valid enemy scene.
func spawn_enemy(point: Phase4EncounterSpawnPoint) -> Enemy:
	if point == null or point.enemy_scene == null:
		return null
	var enemy := point.enemy_scene.instantiate() as Enemy
	if enemy == null:
		push_warning("Phase4DeliveryIntegration: %s does not spawn an Enemy" % point.name)
		return null
	enemy.simulate = simulate_enemies
	if is_instance_valid(player):
		enemy.target = player
	enemy.add_to_group(ENEMY_GROUP)
	_enemy_root.add_child(enemy)
	enemy.global_position = point.global_position
	enemy.reset_physics_interpolation()
	enemy.defeated.connect(_on_enemy_defeated.bind(point))
	point.enemy = enemy
	point.respawn_left = 0.0
	point.initial_spawn_pending = false
	point.spawn_count += 1
	enemy_spawned.emit(enemy, point)
	if is_instance_valid(_visual_layer) and _visual_layer.has_method(&"register_enemy"):
		_visual_layer.call(&"register_enemy", enemy, &"frost_wisp" if enemy is FrostWisp else &"forest_slime")
	return enemy


## Frees every encounter enemy and projectile and resets the spawn slots.
func clear_encounter(reason: StringName) -> void:
	var removed := 0
	if _enemy_root != null:
		for child in _enemy_root.get_children():
			if child.is_queued_for_deletion():
				continue
			if child is Enemy and not (child as Enemy).is_dead():
				removed += 1
			child.queue_free()
	for point in _spawn_points:
		point.reset_runtime()
	var was_live := _encounter_live
	_encounter_live = false
	if was_live or removed > 0:
		encounter_cleared.emit(reason)


func _begin_encounter() -> void:
	for point in _spawn_points:
		point.reset_runtime()
	_encounter_live = true
	encounter_started.emit()


func _step_spawns(delta: float) -> void:
	for point in _spawn_points:
		if point.has_live_enemy():
			continue
		point.enemy = null
		if point.respawn_left > 0.0:
			point.respawn_left = maxf(point.respawn_left - delta, 0.0)
			if point.respawn_left > 0.0:
				continue
		if not point.initial_spawn_pending and _player_distance_to(point.global_position) < min_respawn_distance:
			continue
		spawn_enemy(point)


func _leash_enemies() -> void:
	for point in _spawn_points:
		if point.has_live_enemy() and not is_in_forest(point.enemy.global_position, enemy_leash_margin):
			point.enemy.queue_free()
			point.enemy = null
			point.respawn_left = point.respawn_delay


func _on_enemy_defeated(enemy: Enemy, point: Phase4EncounterSpawnPoint) -> void:
	enemies_defeated += 1
	if point.enemy == enemy:
		point.enemy = null
		point.respawn_left = point.respawn_delay
	enemy_defeated.emit(enemy, point)
	_refresh_objective()


# --- run state -------------------------------------------------------------------

func _compute_run_state() -> RunState:
	if quest_manager == null:
		return RunState.IDLE
	match quest_manager.get_status(quest_id):
		QuestState.Status.COMPLETED, QuestState.Status.REWARDED:
			return RunState.DELIVERED
		QuestState.Status.FAILED:
			return RunState.FAILED
	if not is_run_armed():
		return RunState.IDLE
	return RunState.IN_FOREST if _player_in_forest else RunState.ARMED


func _sync_state() -> void:
	var new_state := _compute_run_state()
	if new_state == _run_state:
		return
	var old := _run_state
	_run_state = new_state
	if old == RunState.IN_FOREST:
		clear_encounter(_exit_reason(new_state))
	if new_state == RunState.IN_FOREST:
		_begin_encounter()
	run_state_changed.emit(new_state, old)


static func _exit_reason(new_state: RunState) -> StringName:
	match new_state:
		RunState.ARMED: return &"left_forest"
		RunState.DELIVERED: return &"delivered"
		RunState.FAILED: return &"quest_failed"
	return &"quest_inactive"


func _update_forest_presence() -> void:
	if not is_instance_valid(player) or not player.is_inside_tree():
		_player_in_forest = false
		return
	_player_in_forest = is_in_forest(player.global_position, exit_margin if _player_in_forest else 0.0)


# --- objective & route -----------------------------------------------------------

func _refresh_objective() -> void:
	var text := get_objective_text()
	if text == _objective_text:
		return
	_objective_text = text
	objective_changed.emit(text)


func _update_route_marker() -> void:
	var target := get_route_target()
	if target != _route_target:
		_route_target = target
		route_target_changed.emit(target)
	if _route_marker == null:
		return
	var show := show_route_marker and target != null and target.is_inside_tree() and is_inside_tree()
	_route_marker.visible = show
	if show:
		_route_marker.global_position = target.global_position
		_route_label.text = _route_label_text(target)


func _route_label_text(target: Node3D) -> String:
	var definition := quest_manager.get_definition(quest_id) if quest_manager != null else null
	if definition == null:
		return ""
	if target is PackagePickup:
		return _package_name(definition)
	if target == destination_target:
		return definition.destination_name
	if target == recipient_target:
		return definition.recipient_name
	return ""


static func _valid_target(node: Node3D) -> Node3D:
	return node if is_instance_valid(node) and not node.is_queued_for_deletion() else null


static func _package_name(definition: QuestDefinition) -> String:
	return definition.package.package_name if definition.package != null else "package"


# --- wiring ----------------------------------------------------------------------

func _connect_quest_manager() -> void:
	if quest_manager == null:
		push_warning("Phase4DeliveryIntegration: no QuestManager; encounters stay disabled")
		return
	quest_manager.quest_state_changed.connect(_on_quest_state_changed)
	quest_manager.objective_completed.connect(_on_objective_completed)
	quest_manager.quest_rewarded.connect(_on_quest_rewarded)
	quest_manager.quest_failed.connect(_on_quest_failed)


func _connect_player() -> void:
	if not is_instance_valid(player):
		push_warning("Phase4DeliveryIntegration: no player; encounters stay disabled")
		return
	_combat = CombatController.find_on(player)
	_carrier = PackageCarrier.find_on(player)
	_health = _combat.health if _combat != null and _combat.health != null else CombatHealth.find_on(player)
	if _combat != null:
		_combat.target_hit.connect(_on_bolt_target_hit)
	if _health != null:
		_health.damaged.connect(_on_player_damaged)
		_health.died.connect(_on_player_died)
	if _carrier != null:
		_carrier.carried_package_changed.connect(_on_carried_package_changed)
	_sync_presentation()


func _attach_visual_layer() -> void:
	if not instance_visual_layer:
		return
	var existing := get_parent().get_node_or_null(NodePath(VISUAL_LAYER_NAME)) if get_parent() != null else null
	if existing != null:
		_visual_layer = existing
	elif ResourceLoader.exists(VISUAL_LAYER_PATH):
		var scene := load(VISUAL_LAYER_PATH) as PackedScene
		if scene == null:
			return
		_visual_layer = scene.instantiate()
		_visual_layer.name = VISUAL_LAYER_NAME
		add_child(_visual_layer)
	else:
		return
	if _visual_layer.has_method(&"bind_integration"):
		_visual_layer.call(&"bind_integration", self)
	_sync_presentation()


## The visual presentation is optional until the visual work is integrated.
## Bind it only through its documented public methods.
func _sync_presentation() -> void:
	if not is_instance_valid(_visual_layer):
		return
	if _visual_layer.has_method(&"set_actor") and is_instance_valid(player):
		_visual_layer.call(&"set_actor", player)
	if _visual_layer.has_method(&"bind_controller") and _combat != null:
		_visual_layer.call(&"bind_controller", _combat)
	if _visual_layer.has_method(&"bind_player_health") and _health != null:
		_visual_layer.call(&"bind_player_health", _health)
	if _visual_layer.has_method(&"bind_package") and is_carrying_quest_package():
		_visual_layer.call(&"bind_package", _carrier.get_package())
	elif _visual_layer.has_method(&"unbind_package"):
		_visual_layer.call(&"unbind_package")
	if _visual_layer.has_method(&"set_quest"):
		_visual_layer.call(&"set_quest", "Dragon Egg Delivery", get_objective_text())
	if _visual_layer.has_method(&"set_quest_state"):
		var state := &"active" if is_run_armed() else &"available"
		if _run_state == RunState.DELIVERED:
			state = &"complete"
		elif _run_state == RunState.FAILED:
			state = &"failed"
		_visual_layer.call(&"set_quest_state", state)
	if _visual_layer.has_method(&"set_destination") and _route_target != null:
		_visual_layer.call(&"set_destination", _route_target.global_position, _route_label_text(_route_target))


func _on_quest_state_changed(changed_id: StringName, _new_status: QuestState.Status, _old_status: QuestState.Status) -> void:
	if changed_id == quest_id:
		_on_quest_changed()


func _on_objective_completed(changed_id: StringName, _objective_index: int) -> void:
	if changed_id == quest_id:
		_on_quest_changed()


func _on_quest_changed() -> void:
	_sync_state()
	_refresh_objective()
	_update_route_marker()
	_sync_presentation()


func _on_quest_rewarded(rewarded_id: StringName, reward: QuestReward) -> void:
	if rewarded_id != quest_id:
		return
	_last_reward = reward
	_on_quest_changed()
	delivery_completed.emit(rewarded_id, reward)


func _on_quest_failed(failed_id: StringName, reason: String) -> void:
	if failed_id != quest_id:
		return
	_on_quest_changed()
	delivery_failed.emit(failed_id, reason)


func _on_carried_package_changed(_package: PackageInstance) -> void:
	_refresh_objective()
	_update_route_marker()
	_sync_presentation()


func _on_bolt_target_hit(target: Node, amount: float) -> void:
	if target is Enemy and target.is_in_group(ENEMY_GROUP):
		bolt_hits += 1
		enemy_hit.emit(target, amount)


## CombatController (connected first) already applied the impact; this only reports it.
func _on_player_damaged(amount: float, _source_position: Vector3) -> void:
	if _combat == null or _combat.package_impact_per_damage <= 0.0 or not is_carrying_quest_package():
		return
	var force := amount * _combat.package_impact_per_damage
	package_hits += 1
	package_impact_total += force
	package_impacted.emit(_carrier.get_package(), force)


func _on_player_died() -> void:
	if not respawn_on_knockout:
		return
	knockouts += 1
	courier_knocked_out.emit()
	# Deferred: died is emitted from inside an enemy's strike.
	_recover_courier.call_deferred()


func _recover_courier() -> void:
	clear_encounter(&"knocked_out")
	if is_carrying_quest_package() and knockout_package_impact > 0.0:
		_carrier.get_package().apply_impact(knockout_package_impact)
	if is_instance_valid(player) and is_instance_valid(knockout_respawn):
		if player is PlayerController:
			(player as PlayerController).teleport_to(knockout_respawn.global_position)
		else:
			player.global_position = knockout_respawn.global_position
	if _health != null:
		_health.reset()
	_player_in_forest = false
	_on_quest_changed()


func _player_distance_to(world_position: Vector3) -> float:
	if not is_instance_valid(player):
		return INF
	var offset := player.global_position - world_position
	return Vector2(offset.x, offset.z).length()
