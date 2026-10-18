extends Node3D
## Phase 4 integration: live encounter presentation layer. Gameplay instances
## res://scenes/gameplay/phase4_integration_visual/encounter_presentation.tscn
## into a level (or an encounter root) and either sets the NodePath exports or
## calls bind_controller / bind_player_health / bind_package / register_enemy.
## Every connection is made by signal or method name only, so the layer boots
## on its own (preview mode) when gameplay combat code is absent.
##
## Reuses the Phase 4 visual slice unchanged:
##   CombatVisualLayer (CombatVisualAdapter + CombatHUD + Effects) for Magic
##   Bolt / Dash / Package Shield VFX, damage numbers and the combat HUD;
##   forest_slime.tscn / frost_wisp.tscn for enemy models and animations.
## Adds: floating enemy health bars, defeat bursts, package damage warnings,
## the colourful forest route + quest beacon and a quest tracker.
##
## Contract (all optional, detected by name):
##   CombatController  magic_bolt_fired(origin, direction), dash_started(),
##                     dash_finished(), shield_changed(active, durability),
##                     target_hit(target, amount)
##   CombatHealth      health_changed(current, maximum), damaged(amount,
##                     source_position), died()
##                     initial values via get_health()/get_current_health() or
##                     current_health|health|hp, and get_max_health() or
##                     max_health|max_hp
##   Enemy             any node in group `enemy_group`, or register_enemy().
##                     Kind from meta/property enemy_kind|enemy_type|kind or the
##                     node name ("slime" / "wisp" / "frost"). Its CombatHealth
##                     is the enemy itself or a child exposing damaged /
##                     health_changed. An existing Phase 4 enemy visual child is
##                     reused; otherwise one is instanced under the enemy.
##   Package           anything PackageStatusProbe understands (temperature,
##                     instability, integrity) plus an optional damaged(...)
##                     signal. Auto-discovered from actor/controller
##                     get_carried_package() / get_package() / carried_package.

signal binding_changed(preview_mode: bool)
signal enemy_registered(enemy: Node, visual: Node)
signal enemy_unregistered(enemy: Node)
signal enemy_defeated(enemy: Node)
signal package_warning_changed(level: int)

const Assets := preload("res://scripts/phase4_integration_visual/integration_assets.gd")
const HealthBar := preload("res://scripts/phase4_integration_visual/enemy_health_bar.gd")
const DefeatBurst := preload("res://scripts/phase4_integration_visual/defeat_burst_vfx.gd")
const EnemyVisual := preload("res://scripts/phase4_visual/enemy_visual.gd")
const KIND_SCENES := {
	&"forest_slime": "res://scenes/phase4_visual/enemies/forest_slime.tscn",
	&"frost_wisp": "res://scenes/phase4_visual/enemies/frost_wisp.tscn",
}
const KIND_BAR_HEIGHT := {&"forest_slime": 1.25, &"frost_wisp": 2.05}
const KIND_TINT := {&"forest_slime": Color(0.55, 1.0, 0.35), &"frost_wisp": Color(0.5, 0.85, 1.0)}
const KIND_PROPERTIES := [&"enemy_kind", &"enemy_type", &"kind"]
const OWNED_META := &"phase4_integration_owned"

@export var combat_controller_path: NodePath
@export var player_health_path: NodePath
@export var actor_path: NodePath
@export var package_path: NodePath
## Search the running scene for a CombatController when no path is set.
@export var auto_discover := true
## Periodically register nodes in `enemy_group`.
@export var auto_register_enemies := true
@export var enemy_group: StringName = &"enemies"
@export var default_enemy_kind: StringName = &"forest_slime"
@export var scan_interval := 0.5
## Courier hits raise package alerts even when no package object is bound
## (the courier always carries one during a delivery).
@export var warn_without_package := true
@export var low_shield_ratio := 0.3

@onready var layer: Node3D = $CombatVisualLayer
@onready var adapter: Node = $CombatVisualLayer/CombatVisualAdapter
@onready var combat_hud: CanvasLayer = $CombatVisualLayer/CombatHUD
@onready var effects_root: Node3D = $CombatVisualLayer/Effects
@onready var route: Node3D = $RouteIndicator
@onready var delivery_hud: CanvasLayer = $DeliveryHUD
@onready var bars_root: Node3D = $EnemyBars

## enemy -> {kind, health, visual, bar, owned, dead, tracks_health, connections}
var enemies: Dictionary = {}
var package = null
var shield_active := false
var shield_durability := 0.0
var defeated_count := 0

var _controller = null  ## controller we listen to for target_hit / shield_changed
var _player_health = null
var _scan_timer := 0.0
var _hit_frames: Dictionary = {}  ## enemy -> process frame of its last target_hit


func _enter_tree() -> void:
	var a := get_node_or_null(^"CombatVisualLayer/CombatVisualAdapter")
	if a != null:
		a.set(&"auto_discover", auto_discover)


func _ready() -> void:
	adapter.connect(&"binding_changed", _on_adapter_binding_changed)
	delivery_hud.connect(&"warning_level_changed", _on_warning_level_changed)
	var actor_node := _node_at(actor_path)
	if actor_node is Node3D:
		set_actor(actor_node as Node3D)
	if not combat_controller_path.is_empty():
		bind_controller(_node_at(combat_controller_path))
	if not player_health_path.is_empty():
		bind_player_health(_node_at(player_health_path))
	if not package_path.is_empty():
		bind_package(_node_at(package_path))
	_sync_links()
	delivery_hud.call(&"set_quest_state", route.get(&"quest_state"))
	if auto_register_enemies:
		scan_enemies.call_deferred()


func _process(delta: float) -> void:
	_sync_links()
	if auto_register_enemies:
		_scan_timer += delta
		if _scan_timer >= scan_interval:
			_scan_timer = 0.0
			scan_enemies()
	_prune_enemies()
	_update_route_progress()


# --- gameplay binding ----------------------------------------------------------

func bind_controller(node: Node) -> bool:
	var ok := bool(adapter.call(&"bind_controller", node))
	_sync_links()
	return ok


func bind_player_health(node: Node) -> bool:
	var ok := bool(adapter.call(&"bind_player_health", node))
	_sync_links()
	return ok


func set_actor(node: Node3D) -> void:
	adapter.set(&"actor", node)
	_sync_links()


func get_actor() -> Node3D:
	var a = adapter.get(&"actor")
	return a if is_instance_valid(a) else null


func bind_package(target: Object) -> void:
	package = target
	delivery_hud.call(&"bind_package", target)


func unbind_package() -> void:
	package = null
	delivery_hud.call(&"unbind_package")


func is_preview_mode() -> bool:
	return bool(adapter.call(&"is_preview_mode"))


# --- route / quest -------------------------------------------------------------

func set_route(world_points: PackedVector3Array) -> void:
	route.call(&"set_route", world_points)
	_update_route_progress()


func set_destination(world_position: Vector3, label := "Drop-off") -> void:
	route.call(&"set_destination", world_position, label)
	_update_route_progress()


func set_quest(title: String, objective: String) -> void:
	delivery_hud.call(&"set_quest", title, objective)


## &"available", &"active", &"complete", &"failed" or &"hidden".
func set_quest_state(state: StringName) -> void:
	route.call(&"set_quest_state", state)
	delivery_hud.call(&"set_quest_state", state)


func add_quest_marker(id: StringName, world_position: Vector3, text := "", color := Color(0.4, 0.85, 1.0)) -> Node3D:
	return route.call(&"add_marker", id, world_position, text, color)


func remove_quest_marker(id: StringName) -> void:
	route.call(&"remove_marker", id)


# --- enemies -------------------------------------------------------------------

## Attaches a Phase 4 enemy visual + health bar to a gameplay enemy and links
## its CombatHealth. Returns the visual (existing or instanced), or null.
func register_enemy(enemy: Node, kind: StringName = &"") -> Node:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
		return null
	if enemies.has(enemy):
		return enemies[enemy]["visual"]
	var k: StringName = kind if kind != &"" else detect_enemy_kind(enemy)
	var health := find_enemy_health(enemy)
	var visual := find_existing_visual(enemy)
	var owned := false
	if visual == null:
		visual = _instance_visual(k)
		if visual == null:
			return null
		owned = true
		visual.name = "Phase4Visual"
		visual.set_meta(OWNED_META, true)
		var host: Node = enemy if enemy is Node3D else bars_root
		if host.is_node_ready():
			host.add_child(visual)
		else:
			host.add_child.call_deferred(visual)

	if health != null and health != enemy:
		adapter.call(&"bind_enemy", enemy, visual)  # target_hit(enemy body) -> visual
	adapter.call(&"bind_enemy", health if health != null else enemy, visual)

	var bar: Node3D = HealthBar.new()
	bar.name = "HealthBar_%s" % String(enemy.name)
	bar.set(&"follow_target", enemy if enemy is Node3D else visual)
	bar.set(&"follow_offset", Vector3(0, float(KIND_BAR_HEIGHT.get(k, 1.4)), 0))
	bar.set(&"accent", KIND_TINT.get(k, Color(0.6, 1.0, 0.5)))
	bars_root.add_child(bar)
	var hp := read_health(health)
	bar.call(&"set_health", hp.x, hp.y)

	var record := {
		"kind": k, "health": health, "visual": visual, "bar": bar, "owned": owned,
		"dead": hp.x <= 0.0 and health != null, "tracks_health": false, "connections": [],
	}
	enemies[enemy] = record
	if health != null:
		_connect_enemy_health(enemy, health, record)
	if record["dead"]:
		bar.call(&"play_death")
	enemy_registered.emit(enemy, visual)
	return visual


func unregister_enemy(enemy: Node) -> void:
	_drop_enemy(enemy)


## Registers every node in `enemy_group` not yet known. Returns how many.
func scan_enemies() -> int:
	if not is_inside_tree() or enemy_group == &"":
		return 0
	var added := 0
	for node in get_tree().get_nodes_in_group(enemy_group):
		if not enemies.has(node) and register_enemy(node) != null:
			added += 1
	_update_threats()
	return added


func get_registered_enemies() -> Array:
	var out := []
	for enemy in enemies:
		if is_instance_valid(enemy):
			out.append(enemy)
	return out


func get_living_enemy_count() -> int:
	var count := 0
	for enemy in enemies:
		if is_instance_valid(enemy) and not bool(enemies[enemy]["dead"]):
			count += 1
	return count


func get_enemy_visual(enemy: Node) -> Node:
	return enemies[enemy]["visual"] if enemies.has(enemy) else null


func get_enemy_bar(enemy: Node) -> Node3D:
	return enemies[enemy]["bar"] if enemies.has(enemy) else null


func get_enemy_kind(enemy: Node) -> StringName:
	return enemies[enemy]["kind"] if enemies.has(enemy) else &""


func detect_enemy_kind(enemy: Node) -> StringName:
	for key in KIND_PROPERTIES:
		if enemy.has_meta(key):
			return _normalize_kind(str(enemy.get_meta(key)))
		if String(key) in enemy:
			var value = enemy.get(key)
			if (value is String or value is StringName) and String(value) != "":
				return _normalize_kind(String(value))
	return _normalize_kind(String(enemy.name))


func find_enemy_health(enemy: Node) -> Node:
	if _is_health(enemy):
		return enemy
	var named := enemy.get_node_or_null(^"CombatHealth")
	if named != null and _is_health(named):
		return named
	for child in enemy.get_children():
		if not _is_enemy_visual(child) and _is_health(child):
			return child
	return null


func find_existing_visual(enemy: Node) -> Node:
	if _is_enemy_visual(enemy):
		return enemy
	for child in enemy.get_children():
		if _is_enemy_visual(child):
			return child
	return null


## (current, maximum) from a CombatHealth-like node; (1, 1) when unknown.
func read_health(health: Node) -> Vector2:
	if health == null:
		return Vector2.ONE
	var cur = _first_value(health, [&"get_health", &"get_current_health"], [&"current_health", &"health", &"hp"])
	var mx = _first_value(health, [&"get_max_health"], [&"max_health", &"max_hp"])
	var maximum := float(mx) if _is_number(mx) and float(mx) > 0.0 else (float(cur) if _is_number(cur) and float(cur) > 0.0 else 1.0)
	var current := float(cur) if _is_number(cur) else maximum
	return Vector2(current, maximum)


# --- signal handlers -----------------------------------------------------------

func _on_adapter_binding_changed(preview: bool) -> void:
	_sync_links()
	binding_changed.emit(preview)


func _on_warning_level_changed(level: int) -> void:
	package_warning_changed.emit(level)


func _on_target_hit(target, amount) -> void:
	if typeof(target) != TYPE_OBJECT or not is_instance_valid(target) or not (target is Node):
		return
	var enemy = _resolve_enemy(target)
	if enemy == null:
		return
	_hit_frames[enemy] = Engine.get_process_frames()
	var record: Dictionary = enemies[enemy]
	if record["health"] == null and not bool(record["dead"]):
		# No CombatHealth to listen to: drive the bar from the hit report.
		var bar: Node3D = record["bar"]
		bar.call(&"play_hit")
		bar.call(&"apply_damage", float(amount))


func _on_shield_changed(active, durability) -> void:
	var ratio := float(durability)
	if ratio > 1.0:
		ratio /= 100.0
	ratio = clampf(ratio, 0.0, 1.0)
	var was_active := shield_active
	var was_ratio := shield_durability
	shield_active = bool(active)
	shield_durability = ratio
	if was_active and not shield_active and ratio <= 0.0:
		delivery_hud.call(&"show_alert", "Shield broken!", 2)
	elif shield_active and was_active and ratio < low_shield_ratio and was_ratio >= low_shield_ratio:
		delivery_hud.call(&"show_alert", "Shield cracking", 1)


func _on_player_damaged(amount, _source_position) -> void:
	if not warn_without_package and not is_instance_valid(package):
		return
	delivery_hud.call(&"notify_package_hit", float(amount), shield_active)


func _on_enemy_health_changed(current, maximum, enemy) -> void:
	if not enemies.has(enemy):
		return
	var record: Dictionary = enemies[enemy]
	var bar: Node3D = record["bar"]
	var cur := float(current)
	if bool(record["dead"]) and cur > 0.0:
		_revive(enemy, record)
	bar.call(&"set_health", cur, float(maximum))


func _on_enemy_damaged(amount, _source_position, enemy) -> void:
	if not enemies.has(enemy):
		return
	var record: Dictionary = enemies[enemy]
	if bool(record["dead"]):
		return
	var bar: Node3D = record["bar"]
	bar.call(&"play_hit")
	if not bool(record["tracks_health"]):
		bar.call(&"apply_damage", float(amount))
	_check_damage_number.call_deferred(enemy, float(amount), Engine.get_process_frames())


func _on_enemy_died(enemy) -> void:
	if not enemies.has(enemy):
		return
	var record: Dictionary = enemies[enemy]
	if bool(record["dead"]):
		return
	record["dead"] = true
	(record["bar"] as Node3D).call(&"play_death")
	var visual = record["visual"]
	if is_instance_valid(visual) and (visual as Node).has_method(&"get_bound_health") and visual.call(&"get_bound_health") == null:
		visual.call(&"play_death")
	_spawn_defeat_burst(enemy, record)
	defeated_count += 1
	_update_threats()
	enemy_defeated.emit(enemy)


# --- internals -----------------------------------------------------------------

func _sync_links() -> void:
	if adapter == null:
		return
	var c = adapter.get(&"controller")
	if not is_instance_valid(c):
		c = null
	if not is_instance_valid(_controller):
		_controller = null
	if c != _controller:
		_disconnect_controller()
		_controller = c
		if c != null:
			if c.has_signal(&"target_hit"):
				c.connect(&"target_hit", _on_target_hit)
			if c.has_signal(&"shield_changed"):
				c.connect(&"shield_changed", _on_shield_changed)
	var h = adapter.get(&"player_health")
	if not is_instance_valid(h):
		h = null
	if not is_instance_valid(_player_health):
		_player_health = null
	if h != _player_health:
		if _player_health != null and _player_health.is_connected(&"damaged", _on_player_damaged):
			_player_health.disconnect(&"damaged", _on_player_damaged)
		_player_health = h
		if h != null and h.has_signal(&"damaged"):
			h.connect(&"damaged", _on_player_damaged)
	if not is_instance_valid(package):
		package = null
		_try_discover_package()


func _disconnect_controller() -> void:
	if _controller == null:
		return
	if _controller.is_connected(&"target_hit", _on_target_hit):
		_controller.disconnect(&"target_hit", _on_target_hit)
	if _controller.is_connected(&"shield_changed", _on_shield_changed):
		_controller.disconnect(&"shield_changed", _on_shield_changed)
	_controller = null


func _try_discover_package() -> void:
	for source in [adapter.get(&"actor"), _controller]:
		if not is_instance_valid(source):
			continue
		var found = null
		for method in [&"get_carried_package", &"get_package"]:
			if source.has_method(method):
				found = source.call(method)
				break
		if found == null and "carried_package" in source:
			found = source.get(&"carried_package")
		if found is Object and is_instance_valid(found):
			bind_package(found)
			return


func _connect_enemy_health(enemy: Node, health: Node, record: Dictionary) -> void:
	var connections: Array = record["connections"]
	var pairs := [
		[&"health_changed", _on_enemy_health_changed.bind(enemy)],
		[&"damaged", _on_enemy_damaged.bind(enemy)],
		[&"died", _on_enemy_died.bind(enemy)],
	]
	for pair in pairs:
		if health.has_signal(pair[0]):
			health.connect(pair[0], pair[1])
			connections.append(pair)
	record["tracks_health"] = health.has_signal(&"health_changed")


func _drop_enemy(enemy) -> void:
	if not enemies.has(enemy):
		return
	var record: Dictionary = enemies[enemy]
	var health = record["health"]
	if is_instance_valid(health):
		for pair in record["connections"]:
			if health.is_connected(pair[0], pair[1]):
				health.disconnect(pair[0], pair[1])
	var bar = record["bar"]
	if is_instance_valid(bar):
		(bar as Node).queue_free()
	var visual = record["visual"]
	if bool(record["owned"]) and is_instance_valid(visual):
		if (visual as Node).has_method(&"unbind_health"):
			visual.call(&"unbind_health")
		(visual as Node).queue_free()
	var links: Dictionary = adapter.get(&"enemy_links")
	for key in links.keys():
		if links[key] == visual or key == enemy:
			links.erase(key)
	enemies.erase(enemy)
	_hit_frames.erase(enemy)
	if is_instance_valid(enemy):
		enemy_unregistered.emit(enemy)
	_update_threats()


func _prune_enemies() -> void:
	var gone := []
	for enemy in enemies:
		if not is_instance_valid(enemy) or (enemy as Node).is_queued_for_deletion():
			gone.append(enemy)
	for enemy in gone:
		_drop_enemy(enemy)


func _revive(enemy, record: Dictionary) -> void:
	record["dead"] = false
	(record["bar"] as Node3D).call(&"reset_bar")
	var visual = record["visual"]
	if is_instance_valid(visual) and bool(visual.call(&"is_dead")):
		visual.call(&"reset_visual")
	_update_threats()


## Damage numbers come from the adapter on target_hit; spawn one here only when
## the hit was not reported through target_hit in the same frame.
func _check_damage_number(enemy, amount: float, frame: int) -> void:
	if not enemies.has(enemy) or not is_instance_valid(enemy):
		return
	if int(_hit_frames.get(enemy, -1)) == frame:
		return
	var at := _enemy_world_position(enemy)
	if at.is_finite():
		adapter.call(&"spawn_damage_number", at + Vector3(0, float(KIND_BAR_HEIGHT.get(enemies[enemy]["kind"], 1.4)) - 0.4, 0), amount)


func _spawn_defeat_burst(enemy, record: Dictionary) -> void:
	if effects_root == null or not effects_root.is_inside_tree():
		return
	var at := _enemy_world_position(enemy)
	if not at.is_finite():
		return
	var burst: Node3D = DefeatBurst.new()
	burst.name = "DefeatBurst"
	effects_root.add_child(burst)
	burst.call(&"configure", effects_root.to_local(at), KIND_TINT.get(record["kind"], Color(0.6, 1.0, 0.4)))


func _update_route_progress() -> void:
	if route == null or not bool(route.call(&"has_destination")):
		return
	var actor := get_actor()
	if actor == null or not actor.is_inside_tree():
		return
	var at := actor.global_position
	route.call(&"update_progress", at)
	delivery_hud.call(&"set_distance", float(route.call(&"get_distance_to_destination", at)), float(route.call(&"get_route_length")))


func _update_threats() -> void:
	if delivery_hud != null:
		delivery_hud.call(&"set_threats", get_living_enemy_count())


func _resolve_enemy(target: Node):
	var node := target
	for i in 4:
		if node == null:
			break
		if enemies.has(node):
			return node
		node = node.get_parent()
	for enemy in enemies:
		var record: Dictionary = enemies[enemy]
		if record["health"] == target or record["visual"] == target:
			return enemy
	return null


func _enemy_world_position(enemy) -> Vector3:
	if enemy is Node3D and (enemy as Node3D).is_inside_tree():
		return (enemy as Node3D).global_position
	var visual = enemies[enemy]["visual"] if enemies.has(enemy) else null
	if is_instance_valid(visual) and visual is Node3D and (visual as Node3D).is_inside_tree():
		return (visual as Node3D).global_position
	return Vector3.INF


func _instance_visual(kind: StringName) -> Node3D:
	var path: String = KIND_SCENES.get(kind, KIND_SCENES[default_enemy_kind] if KIND_SCENES.has(default_enemy_kind) else "")
	if path == "" or not ResourceLoader.exists(path):
		push_warning("Phase 4 integration visual: no enemy visual for kind %s" % kind)
		return null
	var scene := load(path) as PackedScene
	return scene.instantiate() as Node3D if scene != null else null


func _normalize_kind(text: String) -> StringName:
	var t := text.to_lower()
	if t.contains("wisp") or t.contains("frost"):
		return &"frost_wisp"
	if t.contains("slime"):
		return &"forest_slime"
	return default_enemy_kind


func _node_at(path: NodePath) -> Node:
	return get_node_or_null(path) if not path.is_empty() else null


static func _is_health(node: Node) -> bool:
	return node.has_signal(&"damaged") or node.has_signal(&"health_changed")


static func _is_enemy_visual(node: Node) -> bool:
	var script: Script = node.get_script() as Script
	while script != null:
		if script == EnemyVisual:
			return true
		script = script.get_base_script()
	return false


static func _first_value(node: Node, methods: Array, properties: Array) -> Variant:
	for m in methods:
		if node.has_method(m):
			return node.call(m)
	for p in properties:
		if String(p) in node:
			return node.get(p)
	return null


static func _is_number(value: Variant) -> bool:
	return value is float or value is int
