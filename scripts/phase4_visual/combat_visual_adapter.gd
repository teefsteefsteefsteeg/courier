extends Node
## Bridges gameplay combat signals to Phase 4 visuals without a hard dependency.
## Every connection is made by signal name only if the node exposes it, so the
## visual slice boots and previews on its own when gameplay is absent.
##
## CombatController (any node exposing these signals):
##   magic_bolt_fired(origin, direction)  -> bolt projectile VFX, HUD cooldown
##   dash_started()                       -> HUD "Dashing", remember start point
##   dash_finished()                      -> afterimage trail VFX, HUD cooldown
##   shield_changed(active, durability)   -> package shield bubble, HUD shield row
##   target_hit(target, amount)           -> impact burst, damage number, enemy hit
## CombatHealth (player): health_changed(current, max), damaged(amount, source_position)
## CombatHealth (enemy, via bind_enemy): damaged -> play_hit, died -> play_death
##
## Optional polling (used when present, never required):
##   controller.get_bolt_cooldown_remaining() / get_bolt_cooldown()
##   controller.get_dash_cooldown_remaining() / get_dash_cooldown()

signal binding_changed(preview_mode: bool)
signal effect_spawned(kind: StringName, effect: Node)

const MagicBolt := preload("res://scripts/phase4_visual/magic_bolt_vfx.gd")
const DashVfx := preload("res://scripts/phase4_visual/dash_vfx.gd")
const ShieldVfx := preload("res://scripts/phase4_visual/package_shield_vfx.gd")
const DamageNumber := preload("res://scripts/phase4_visual/damage_number_vfx.gd")

const CONTROLLER_SIGNALS := [&"magic_bolt_fired", &"dash_started", &"dash_finished", &"shield_changed", &"target_hit"]

@export var combat_controller_path: NodePath
@export var player_health_path: NodePath
@export var hud_path: NodePath
@export var effects_root_path: NodePath
@export var actor_path: NodePath
## Search the running scene for a CombatController / CombatHealth when paths are empty.
@export var auto_discover := true
@export var discovery_interval := 1.0
@export var max_discovery_attempts := 10
@export var bolt_cooldown_estimate := 0.6
@export var dash_cooldown_estimate := 0.9
@export var bolt_range := 12.0

var controller: Node
var player_health: Node
var hud: Node
var effects_root: Node3D
var actor: Node3D
var shield_vfx: Node3D
var preview_mode := true
var enemy_links: Dictionary = {}  ## health/target node -> enemy visual
var live_bolts: Array[Node3D] = []

var _dash_start := Vector3.ZERO
var _last_bolt_origin := Vector3.INF
var _discovery_timer := 0.0
var _discovery_attempts := 0


func _ready() -> void:
	hud = get_node_or_null(hud_path) if not hud_path.is_empty() else hud
	var fx: Node = get_node_or_null(effects_root_path) if not effects_root_path.is_empty() else null
	if fx is Node3D:
		effects_root = fx
	var a: Node = get_node_or_null(actor_path) if not actor_path.is_empty() else null
	if a is Node3D:
		actor = a
	if not combat_controller_path.is_empty():
		bind_controller(get_node_or_null(combat_controller_path))
	if not player_health_path.is_empty():
		bind_player_health(get_node_or_null(player_health_path))
	if controller == null and auto_discover:
		_try_discover.call_deferred()


func _process(delta: float) -> void:
	if controller == null and auto_discover and _discovery_attempts < max_discovery_attempts:
		_discovery_timer += delta
		if _discovery_timer >= discovery_interval:
			_discovery_timer = 0.0
			_try_discover()
	_poll_cooldowns()
	_prune_bolts()


# --- binding -------------------------------------------------------------------

func bind_controller(node: Node) -> bool:
	unbind_controller()
	if node == null:
		return false
	var connected := 0
	for sig in CONTROLLER_SIGNALS:
		if node.has_signal(sig):
			node.connect(sig, Callable(self, "_on_" + String(sig)))
			connected += 1
	if connected == 0:
		return false
	controller = node
	if actor == null and node.get_parent() is Node3D:
		actor = node.get_parent()
	if player_health == null and node.get_parent() != null:
		for sibling in node.get_parent().get_children():
			if sibling != node and sibling.has_signal(&"health_changed"):
				bind_player_health(sibling)
				break
	_set_preview_mode(false)
	return true


func unbind_controller() -> void:
	if controller != null and is_instance_valid(controller):
		for sig in CONTROLLER_SIGNALS:
			var cb := Callable(self, "_on_" + String(sig))
			if controller.has_signal(sig) and controller.is_connected(sig, cb):
				controller.disconnect(sig, cb)
	controller = null
	_set_preview_mode(player_health == null)


func bind_player_health(node: Node) -> bool:
	unbind_player_health()
	if node == null:
		return false
	var bound := false
	if node.has_signal(&"health_changed"):
		node.connect(&"health_changed", _on_player_health_changed)
		bound = true
	if node.has_signal(&"damaged"):
		node.connect(&"damaged", _on_player_damaged)
		bound = true
	if not bound:
		return false
	player_health = node
	_set_preview_mode(false)
	return true


func unbind_player_health() -> void:
	if player_health != null and is_instance_valid(player_health):
		if player_health.is_connected(&"health_changed", _on_player_health_changed):
			player_health.disconnect(&"health_changed", _on_player_health_changed)
		if player_health.is_connected(&"damaged", _on_player_damaged):
			player_health.disconnect(&"damaged", _on_player_damaged)
	player_health = null
	_set_preview_mode(controller == null)


## Links an enemy CombatHealth (or the enemy body that target_hit reports) to a
## visual. The visual is hit/killed by the health signals when available.
func bind_enemy(health_or_target: Node, visual: Node) -> bool:
	if health_or_target == null or visual == null:
		return false
	enemy_links[health_or_target] = visual
	if visual.has_method(&"bind_health") and health_or_target.has_signal(&"damaged"):
		return visual.call(&"bind_health", health_or_target)
	return true


func is_preview_mode() -> bool:
	return preview_mode


# --- visual entry points (used by signals and by the showcase preview) ----------

func show_magic_bolt(origin: Vector3, direction: Vector3, distance := -1.0) -> Node3D:
	var root := _effects()
	if root == null:
		return null
	var bolt: Node3D = MagicBolt.new()
	bolt.name = "MagicBolt"
	root.add_child(bolt)
	bolt.call(&"configure", _to_local(origin), direction, distance if distance > 0.0 else bolt_range)
	live_bolts.append(bolt)
	_last_bolt_origin = origin
	if hud != null and hud.has_method(&"start_bolt_cooldown") and not _controller_has(&"get_bolt_cooldown_remaining"):
		hud.call(&"start_bolt_cooldown", bolt_cooldown_estimate)
	effect_spawned.emit(&"magic_bolt", bolt)
	return bolt


func show_dash_start(from_position := Vector3.INF) -> void:
	_dash_start = from_position if from_position.is_finite() else _actor_position()
	if hud != null and hud.has_method(&"set_dash_state"):
		hud.call(&"set_dash_state", false, true)


func show_dash_finish(to_position := Vector3.INF) -> Node3D:
	var end := to_position if to_position.is_finite() else _actor_position()
	var root := _effects()
	var dash: Node3D = null
	if root != null:
		dash = DashVfx.new()
		dash.name = "DashTrail"
		root.add_child(dash)
		dash.call(&"configure", _to_local(_dash_start), _to_local(end))
		effect_spawned.emit(&"dash", dash)
	if hud != null and hud.has_method(&"start_dash_cooldown") and not _controller_has(&"get_dash_cooldown_remaining"):
		hud.call(&"start_dash_cooldown", dash_cooldown_estimate)
	return dash


func show_shield(active: bool, durability: float) -> Node3D:
	var root := _effects()
	if shield_vfx == null or not is_instance_valid(shield_vfx):
		shield_vfx = null
		if root != null:
			shield_vfx = ShieldVfx.new()
			shield_vfx.name = "PackageShield"
			root.add_child(shield_vfx)
			effect_spawned.emit(&"shield", shield_vfx)
	if shield_vfx != null:
		shield_vfx.set(&"follow_target", actor)
		if actor == null or not actor.is_inside_tree():
			shield_vfx.position = _to_local(_actor_position()) + Vector3(0, 0.9, 0)
		shield_vfx.call(&"set_shield", active, durability)
	if hud != null and hud.has_method(&"set_shield_state"):
		hud.call(&"set_shield_state", active, durability)
	return shield_vfx


func show_target_hit(target: Node, amount: float, source_position := Vector3.INF) -> void:
	var visual := find_enemy_visual(target)
	var source := source_position if source_position.is_finite() else _last_bolt_origin
	if not source.is_finite():
		source = _actor_position()
	var at := Vector3.INF
	if target is Node3D and (target as Node3D).is_inside_tree():
		at = (target as Node3D).global_position + Vector3(0, 0.8, 0)
	elif visual is Node3D and (visual as Node3D).is_inside_tree():
		at = (visual as Node3D).global_position + Vector3(0, 0.8, 0)
	_finish_nearest_bolt(at)
	# A bound health node drives play_hit itself; avoid double hits.
	if visual != null and visual.has_method(&"play_hit"):
		var driven := visual.has_method(&"get_bound_health") and visual.call(&"get_bound_health") != null
		if not driven:
			visual.call(&"play_hit", source)
	if at.is_finite():
		spawn_damage_number(at, amount)


func show_player_health(current: float, maximum: float) -> void:
	if hud != null and hud.has_method(&"set_health"):
		hud.call(&"set_health", current, maximum)


func spawn_damage_number(world_position: Vector3, amount: float, tint := Color(1.0, 0.9, 0.5)) -> Node:
	var root := _effects()
	if root == null:
		return null
	var label: Label3D = DamageNumber.new()
	label.name = "DamageNumber"
	root.add_child(label)
	label.call(&"configure", _to_local(world_position), amount, tint)
	effect_spawned.emit(&"damage_number", label)
	return label


func find_enemy_visual(target: Node) -> Node:
	if target == null:
		return null
	if enemy_links.has(target):
		var linked: Node = enemy_links[target]
		if is_instance_valid(linked):
			return linked
	if target.has_method(&"play_hit"):
		return target
	for child in target.get_children():
		if child.has_method(&"play_hit"):
			return child
	return null


# --- signal handlers -----------------------------------------------------------

func _on_magic_bolt_fired(origin, direction) -> void:
	var o: Vector3 = origin if origin is Vector3 else _actor_position()
	var d: Vector3 = direction if direction is Vector3 else Vector3.FORWARD
	show_magic_bolt(o, d)


func _on_dash_started() -> void:
	show_dash_start()


func _on_dash_finished() -> void:
	show_dash_finish()


func _on_shield_changed(active, durability) -> void:
	show_shield(bool(active), float(durability))


func _on_target_hit(target, amount) -> void:
	show_target_hit(target as Node, float(amount))


func _on_player_health_changed(current, maximum) -> void:
	show_player_health(float(current), float(maximum))


func _on_player_damaged(amount, _source_position) -> void:
	if actor != null and actor.is_inside_tree():
		spawn_damage_number(actor.global_position + Vector3(0, 1.6, 0), float(amount), Color(1.0, 0.35, 0.35))


# --- internals -----------------------------------------------------------------

func _try_discover() -> void:
	if controller != null or not is_inside_tree():
		return
	_discovery_attempts += 1
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root
	var found := _find_with_signal(scene_root, &"magic_bolt_fired")
	if found != null:
		bind_controller(found)


func _find_with_signal(node: Node, sig: StringName) -> Node:
	if node.has_signal(sig):
		return node
	for child in node.get_children():
		var hit := _find_with_signal(child, sig)
		if hit != null:
			return hit
	return null


func _poll_cooldowns() -> void:
	if controller == null or hud == null or not is_instance_valid(controller):
		return
	if controller.has_method(&"get_bolt_cooldown_remaining") and hud.has_method(&"set_bolt_cooldown"):
		var total := float(controller.call(&"get_bolt_cooldown")) if controller.has_method(&"get_bolt_cooldown") else bolt_cooldown_estimate
		hud.call(&"set_bolt_cooldown", float(controller.call(&"get_bolt_cooldown_remaining")), total)
	if controller.has_method(&"get_dash_cooldown_remaining") and hud.has_method(&"set_dash_state"):
		var dash_total := float(controller.call(&"get_dash_cooldown")) if controller.has_method(&"get_dash_cooldown") else dash_cooldown_estimate
		var remaining := float(controller.call(&"get_dash_cooldown_remaining"))
		var is_dashing := bool(hud.get(&"dashing"))
		hud.call(&"set_dash_state", remaining <= 0.0, is_dashing, remaining, dash_total)


func _controller_has(method: StringName) -> bool:
	return controller != null and is_instance_valid(controller) and controller.has_method(method)


func _finish_nearest_bolt(world_position: Vector3) -> void:
	_prune_bolts()
	if live_bolts.is_empty():
		return
	var best: Node3D = live_bolts[0]
	if world_position.is_finite():
		var best_d := INF
		for bolt in live_bolts:
			var head_position: Vector3 = bolt.call(&"get_head_world_position")
			var d := head_position.distance_to(world_position)
			if d < best_d:
				best_d = d
				best = bolt
		best.call(&"impact", _to_local(world_position))
	else:
		best.call(&"impact")
	live_bolts.erase(best)


func _prune_bolts() -> void:
	var alive: Array[Node3D] = []
	for bolt in live_bolts:
		if is_instance_valid(bolt) and not bolt.is_queued_for_deletion() and not bool(bolt.get(&"has_impacted")):
			alive.append(bolt)
	live_bolts = alive


func _effects() -> Node3D:
	if effects_root != null and is_instance_valid(effects_root):
		return effects_root
	effects_root = null
	var parent := get_parent()
	if parent is Node3D:
		return parent
	return null


func _actor_position() -> Vector3:
	if actor != null and is_instance_valid(actor):
		return actor.global_position if actor.is_inside_tree() else actor.position
	return Vector3.ZERO


func _to_local(world_position: Vector3) -> Vector3:
	var root := _effects()
	if root != null and root.is_inside_tree():
		return root.to_local(world_position)
	return world_position


func _set_preview_mode(value: bool) -> void:
	if preview_mode == value:
		return
	preview_mode = value
	binding_changed.emit(preview_mode)
