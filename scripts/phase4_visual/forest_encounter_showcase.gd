extends Node3D
## Phase 4 forest encounter showcase: a low-poly forest clearing with a courier
## stand-in, two Forest Slimes, two Frost Wisps, the combat visual layer
## (effects + compact HUD + adapter) and visual-only preview triggers.
##
## When no gameplay CombatController is found the scene runs in preview mode:
## an auto demo cycles every effect, and keys trigger them manually:
##   1 magic bolt   2 dash   3 package shield   4 take a hit
##   5 enemies move/idle   R reset   P toggle auto demo
## If the adapter binds to gameplay, preview triggers are disabled and the
## gameplay signals drive the same visuals.

const Lowpoly := preload("res://scripts/phase4_visual/lowpoly.gd")
const SlimeScene := preload("res://scenes/phase4_visual/enemies/forest_slime.tscn")
const WispScene := preload("res://scenes/phase4_visual/enemies/frost_wisp.tscn")
const CombatLayerScene := preload("res://scenes/gameplay/phase4_visual/combat_visual_layer.tscn")

const PLAYER_MAX_HP := 100.0
const PREVIEW_ENEMY_HP := 3
const PREVIEW_BOLT_DAMAGE := 12.0
const PREVIEW_HIT_DAMAGE := 15.0
const SHIELD_HIT_COST := 0.34
const RESPAWN_DELAY := 2.5
const COURIER_START := Vector3(0, 0, 2.0)
const ARENA_RADIUS := 5.0
const DEMO_SEQUENCE := [&"bolt", &"move", &"bolt", &"shield", &"hurt", &"dash", &"bolt", &"hurt", &"shield", &"bolt", &"dash", &"move"]

@export var auto_demo := true
@export var demo_interval := 1.1
@export var bolt_cooldown := 0.6
@export var dash_cooldown := 0.9
@export var dash_distance := 2.5

var courier: Node3D
var courier_body: Node3D
var camera: Camera3D
var combat_layer: Node3D
var adapter: Node
var hud: CanvasLayer
var effects_root: Node3D
var help_label: Label
var enemies: Array[Node3D] = []

var player_hp := PLAYER_MAX_HP
var shield_active := false
var shield_durability := 1.0
var bolt_timer := 0.0
var dash_timer := 0.0
var enemies_moving := false
var last_action: StringName = &""

var _enemy_hp: Dictionary = {}
var _enemy_home: Dictionary = {}
var _respawn: Dictionary = {}
var _demo_timer := 0.0
var _demo_step := 0
var _time := 0.0
var _dash_side := 1.0
var _courier_flinch := 0.0
var _courier_material: StandardMaterial3D


func _ready() -> void:
	_build_environment()
	_build_forest()
	_build_courier()
	_spawn_enemies()

	combat_layer = CombatLayerScene.instantiate()
	add_child(combat_layer)
	adapter = combat_layer.get_node("CombatVisualAdapter")
	hud = combat_layer.get_node("CombatHUD")
	effects_root = combat_layer.get_node("Effects")
	adapter.set(&"actor", courier)
	adapter.set(&"bolt_cooldown_estimate", bolt_cooldown)
	adapter.set(&"dash_cooldown_estimate", dash_cooldown)
	adapter.connect(&"binding_changed", _on_binding_changed)

	_build_help()
	adapter.call(&"show_player_health", player_hp, PLAYER_MAX_HP)
	hud.call(&"set_shield_state", false, shield_durability)
	_update_help()


func _process(delta: float) -> void:
	_time += delta
	bolt_timer = maxf(0.0, bolt_timer - delta)
	dash_timer = maxf(0.0, dash_timer - delta)
	_update_respawns(delta)
	_update_enemy_motion()
	_update_courier(delta)
	if auto_demo and is_preview_mode():
		_demo_timer += delta
		if _demo_timer >= demo_interval:
			_demo_timer = 0.0
			trigger_preview(DEMO_SEQUENCE[_demo_step % DEMO_SEQUENCE.size()])
			_demo_step += 1


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var action: StringName = &""
	match key.physical_keycode:
		KEY_1: action = &"bolt"
		KEY_2: action = &"dash"
		KEY_3: action = &"shield"
		KEY_4: action = &"hurt"
		KEY_5: action = &"move"
		KEY_R: action = &"reset"
		KEY_P:
			auto_demo = not auto_demo
			_update_help()
			get_viewport().set_input_as_handled()
			return
	if action != &"":
		auto_demo = false
		trigger_preview(action)
		_update_help()
		get_viewport().set_input_as_handled()


# --- preview API ---------------------------------------------------------------

func is_preview_mode() -> bool:
	return adapter != null and bool(adapter.call(&"is_preview_mode"))


## Runs one visual-only preview action. Returns false when gameplay is driving
## the visuals, the action is on cooldown, or it is unknown.
func trigger_preview(action: StringName) -> bool:
	if not is_preview_mode():
		return false
	var ok := false
	match action:
		&"bolt": ok = _preview_bolt()
		&"dash": ok = _preview_dash()
		&"shield": ok = _preview_shield()
		&"hurt": ok = _preview_hurt()
		&"move": ok = _preview_toggle_move()
		&"reset": ok = _preview_reset()
	if ok:
		last_action = action
	return ok


func get_living_enemies() -> Array[Node3D]:
	var living: Array[Node3D] = []
	for e in enemies:
		if not bool(e.call(&"is_dead")):
			living.append(e)
	return living


func get_enemy_hp(enemy: Node3D) -> int:
	return int(_enemy_hp.get(enemy, 0))


func _preview_bolt() -> bool:
	if bolt_timer > 0.0:
		return false
	var target := _nearest_living_enemy()
	var origin := courier.global_position + Vector3(0, 1.0, 0) + _courier_forward() * 0.4
	var aim := origin + _courier_forward() * 8.0
	if target != null:
		aim = _aim_point(target)
		_face_courier(aim)
		origin = courier.global_position + Vector3(0, 1.0, 0) + _courier_forward() * 0.4
	var to_aim := aim - origin
	var bolt: Node3D = adapter.call(&"show_magic_bolt", origin, to_aim.normalized(), to_aim.length())
	if bolt == null:
		return false
	if target != null:
		bolt.connect(&"impacted", _on_preview_bolt_impact.bind(target))
	bolt_timer = bolt_cooldown
	return true


func _preview_dash() -> bool:
	if dash_timer > 0.0:
		return false
	var right := _courier_forward().cross(Vector3.UP).normalized()
	var start := courier.global_position
	var end := start + right * _dash_side * dash_distance
	var flat := Vector2(end.x, end.z)
	if flat.length() > ARENA_RADIUS or end.z < -1.0:
		_dash_side = -_dash_side
		end = start + right * _dash_side * dash_distance
	_dash_side = -_dash_side
	adapter.call(&"show_dash_start", start)
	courier.global_position = end
	adapter.call(&"show_dash_finish", end)
	dash_timer = dash_cooldown
	return true


func _preview_shield() -> bool:
	shield_active = not shield_active
	if shield_active and shield_durability <= 0.0:
		shield_durability = 1.0
	adapter.call(&"show_shield", shield_active, shield_durability)
	return true


func _preview_hurt() -> bool:
	var head := courier.global_position + Vector3(0, 1.6, 0)
	if shield_active:
		shield_durability = maxf(0.0, shield_durability - SHIELD_HIT_COST)
		if shield_durability <= 0.0:
			shield_active = false
		adapter.call(&"show_shield", shield_active, shield_durability)
		adapter.call(&"spawn_damage_number", head, 0.0, Color(0.5, 1.0, 0.9))
	else:
		player_hp = maxf(0.0, player_hp - PREVIEW_HIT_DAMAGE)
		adapter.call(&"show_player_health", player_hp, PLAYER_MAX_HP)
		adapter.call(&"spawn_damage_number", head, PREVIEW_HIT_DAMAGE, Color(1.0, 0.35, 0.35))
		_courier_flinch = 1.0
		if player_hp <= 0.0:
			player_hp = PLAYER_MAX_HP  # preview revive so the demo keeps looping
			adapter.call(&"show_player_health", player_hp, PLAYER_MAX_HP)
	return true


func _preview_toggle_move() -> bool:
	enemies_moving = not enemies_moving
	for e in get_living_enemies():
		e.call(&"play_move" if enemies_moving else &"play_idle")
	return true


func _preview_reset() -> bool:
	player_hp = PLAYER_MAX_HP
	shield_active = false
	shield_durability = 1.0
	bolt_timer = 0.0
	dash_timer = 0.0
	enemies_moving = false
	_respawn.clear()
	courier.global_position = COURIER_START
	courier.rotation.y = 0.0
	for e in enemies:
		_enemy_hp[e] = PREVIEW_ENEMY_HP
		e.position = _enemy_home[e]
		e.call(&"reset_visual")
	adapter.call(&"show_player_health", player_hp, PLAYER_MAX_HP)
	adapter.call(&"show_shield", false, shield_durability)
	hud.call(&"set_bolt_cooldown", 0.0, bolt_cooldown)
	hud.call(&"set_dash_state", true)
	return true


func _on_preview_bolt_impact(world_position: Vector3, enemy: Node3D) -> void:
	if not is_instance_valid(enemy) or bool(enemy.call(&"is_dead")):
		return
	var hp := get_enemy_hp(enemy) - 1
	_enemy_hp[enemy] = hp
	adapter.call(&"spawn_damage_number", world_position, PREVIEW_BOLT_DAMAGE)
	if hp <= 0:
		enemy.call(&"play_death")
		_respawn[enemy] = RESPAWN_DELAY
	else:
		enemy.call(&"play_hit", courier.global_position)


func _on_binding_changed(preview: bool) -> void:
	if not preview:
		auto_demo = false
	_update_help()


# --- per-frame -----------------------------------------------------------------

func _update_respawns(delta: float) -> void:
	for e in _respawn.keys():
		var left: float = _respawn[e] - delta
		if left > 0.0:
			_respawn[e] = left
			continue
		_respawn.erase(e)
		_enemy_hp[e] = PREVIEW_ENEMY_HP
		e.position = _enemy_home[e]
		e.call(&"reset_visual")
		if enemies_moving:
			e.call(&"play_move")


func _update_enemy_motion() -> void:
	for i in enemies.size():
		var e := enemies[i]
		if int(e.get(&"state")) != 1:  # EnemyVisual.State.MOVE
			continue
		var home: Vector3 = _enemy_home[e]
		var phase := _time * 0.8 + float(i) * 1.7
		var next := home + Vector3(cos(phase) * 1.1, 0.0, sin(phase) * 0.7)
		var vel := next - e.position
		if vel.length_squared() > 0.000001:
			e.rotation.y = atan2(vel.x, vel.z)
		e.position = next


func _update_courier(delta: float) -> void:
	_courier_flinch = maxf(0.0, _courier_flinch - delta * 4.0)
	courier_body.position.y = sin(_time * 2.5) * 0.03
	courier_body.rotation.x = -0.25 * _courier_flinch
	if _courier_material != null:
		_courier_material.albedo_color = Color(0.22, 0.35, 0.62).lerp(Color(1.0, 0.4, 0.4), _courier_flinch * 0.7)


# --- helpers -------------------------------------------------------------------

func _nearest_living_enemy() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for e in get_living_enemies():
		var d := e.global_position.distance_squared_to(courier.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _aim_point(enemy: Node3D) -> Vector3:
	var b: Variant = enemy.get(&"body")
	if b is Node3D:
		return (b as Node3D).global_position + Vector3(0, 0.3, 0)
	return enemy.global_position + Vector3(0, 0.6, 0)


func _courier_forward() -> Vector3:
	return -courier.global_basis.z


func _face_courier(point: Vector3) -> void:
	var d := point - courier.global_position
	d.y = 0.0
	if d.length_squared() > 0.0001:
		courier.rotation.y = atan2(-d.x, -d.z)


# --- scene construction --------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.5, 0.48)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.72, 0.68)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	camera = Camera3D.new()
	camera.name = "ShowcaseCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.0
	camera.rotation_degrees = Vector3(-35, 45, 0)
	camera.position = Vector3(0, 0, -1.0) + camera.basis.z * 24.0
	camera.near = 0.1
	camera.far = 100.0
	add_child(camera)
	camera.current = true


func _build_forest() -> void:
	var forest := Node3D.new()
	forest.name = "Forest"
	add_child(forest)
	var ground_mat := Lowpoly.load_material("forest_ground.tres", Color(0.29, 0.45, 0.22))
	Lowpoly.add_part(forest, "Ground", Lowpoly.plane(Vector2(30, 30)), ground_mat)
	var clearing_mat := Lowpoly.make_material(Color(0.42, 0.58, 0.3))
	Lowpoly.add_part(forest, "Clearing", Lowpoly.cone(5.5, 5.5, 0.02, 10), clearing_mat, Vector3(0, 0.01, -1.0))

	var bark := Lowpoly.load_material("tree_bark.tres", Color(0.4, 0.27, 0.17))
	var leaves := Lowpoly.load_material("tree_leaves.tres", Color(0.16, 0.38, 0.2))
	var rock_mat := Lowpoly.load_material("forest_rock.tres", Color(0.5, 0.52, 0.55))
	var cap_mat := Lowpoly.make_material(Color(0.78, 0.2, 0.18))
	var stem_mat := Lowpoly.make_material(Color(0.92, 0.88, 0.78))
	var trunk_mesh := Lowpoly.cone(0.2, 0.13, 1.0, 5)
	var crown_low := Lowpoly.cone(1.0, 0.0, 1.6, 6)
	var crown_high := Lowpoly.cone(0.72, 0.0, 1.3, 6)
	var rock_mesh := Lowpoly.sphere(0.45, 0.6, 5, 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var trees := Node3D.new()
	trees.name = "Trees"
	forest.add_child(trees)
	for i in 22:
		var angle := TAU * float(i) / 22.0 + rng.randf_range(-0.12, 0.12)
		var dist := rng.randf_range(7.5, 12.0)
		var tree := Node3D.new()
		tree.name = "Pine%d" % i
		tree.position = Vector3(cos(angle) * dist, 0, sin(angle) * dist - 1.0)
		tree.rotation.y = rng.randf() * TAU
		tree.scale = Vector3.ONE * rng.randf_range(0.85, 1.35)
		trees.add_child(tree)
		Lowpoly.add_part(tree, "Trunk", trunk_mesh, bark, Vector3(0, 0.5, 0))
		Lowpoly.add_part(tree, "CrownLow", crown_low, leaves, Vector3(0, 1.6, 0))
		Lowpoly.add_part(tree, "CrownHigh", crown_high, leaves, Vector3(0, 2.45, 0))

	var props := Node3D.new()
	props.name = "Props"
	forest.add_child(props)
	for i in 7:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(5.0, 7.0)
		var rock := Lowpoly.add_part(props, "Rock%d" % i, rock_mesh, rock_mat, Vector3(cos(angle) * dist, 0.15, sin(angle) * dist - 1.0))
		rock.scale = Vector3(rng.randf_range(0.7, 1.6), rng.randf_range(0.6, 1.0), rng.randf_range(0.7, 1.4))
		rock.rotation.y = rng.randf() * TAU
	for i in 5:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(4.0, 6.5)
		var shroom := Node3D.new()
		shroom.name = "Mushroom%d" % i
		shroom.position = Vector3(cos(angle) * dist, 0, sin(angle) * dist - 1.0)
		props.add_child(shroom)
		Lowpoly.add_part(shroom, "Stem", Lowpoly.cone(0.05, 0.04, 0.2, 5), stem_mat, Vector3(0, 0.1, 0))
		Lowpoly.add_part(shroom, "Cap", Lowpoly.cone(0.18, 0.0, 0.14, 6), cap_mat, Vector3(0, 0.25, 0))


func _build_courier() -> void:
	courier = Node3D.new()
	courier.name = "CourierStandIn"
	courier.position = COURIER_START
	add_child(courier)
	courier_body = Node3D.new()
	courier_body.name = "Body"
	courier.add_child(courier_body)
	_courier_material = Lowpoly.make_material(Color(0.22, 0.35, 0.62))
	var skin := Lowpoly.make_material(Color(0.95, 0.8, 0.66))
	var hat := Lowpoly.make_material(Color(0.36, 0.2, 0.5))
	var parcel := Lowpoly.make_material(Color(0.66, 0.48, 0.28))
	Lowpoly.add_part(courier_body, "Cloak", Lowpoly.capsule(0.3, 1.2, 6, 2), _courier_material, Vector3(0, 0.6, 0))
	Lowpoly.add_part(courier_body, "Head", Lowpoly.sphere(0.2, 0.4, 6, 3), skin, Vector3(0, 1.38, 0))
	Lowpoly.add_part(courier_body, "Hat", Lowpoly.cone(0.3, 0.0, 0.45, 6), hat, Vector3(0, 1.7, 0))
	Lowpoly.add_part(courier_body, "Package", Lowpoly.box(Vector3(0.45, 0.35, 0.35)), parcel, Vector3(0, 0.85, 0.32))
	var shadow := Lowpoly.make_material(Color(0, 0, 0, 0.3), 0.0, true)
	Lowpoly.add_part(courier, "Shadow", Lowpoly.cone(0.4, 0.4, 0.02, 8), shadow, Vector3(0, 0.01, 0), false)


func _spawn_enemies() -> void:
	var group := Node3D.new()
	group.name = "Enemies"
	add_child(group)
	var layout := [
		[SlimeScene, "ForestSlimeA", Vector3(-2.2, 0, -2.4)],
		[SlimeScene, "ForestSlimeB", Vector3(2.4, 0, -3.2)],
		[WispScene, "FrostWispA", Vector3(0.5, 0, -4.4)],
		[WispScene, "FrostWispB", Vector3(-3.6, 0, -5.0)],
	]
	for entry in layout:
		var scene: PackedScene = entry[0]
		var enemy: Node3D = scene.instantiate()
		enemy.name = entry[1]
		enemy.position = entry[2]
		group.add_child(enemy)
		enemies.append(enemy)
		_enemy_hp[enemy] = PREVIEW_ENEMY_HP
		_enemy_home[enemy] = enemy.position


func _build_help() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ShowcaseHelp"
	layer.layer = 7
	add_child(layer)
	help_label = Label.new()
	help_label.name = "HelpLabel"
	help_label.position = Vector2(16, 12)
	help_label.add_theme_font_size_override(&"font_size", 15)
	help_label.add_theme_color_override(&"font_color", Color(0.95, 0.97, 0.95))
	help_label.add_theme_color_override(&"font_outline_color", Color(0.05, 0.08, 0.06))
	help_label.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(help_label)


func _update_help() -> void:
	if help_label == null:
		return
	var mode := "Preview (gameplay not detected)" if is_preview_mode() else "Gameplay linked - preview keys disabled"
	help_label.text = "Mystic Courier - Forest Encounter (Phase 4 visual showcase)\nMode: %s   Auto demo: %s\n[1] Magic bolt  [2] Dash  [3] Package shield  [4] Take hit  [5] Enemies move/idle  [R] Reset  [P] Auto demo" % [mode, "on" if auto_demo else "off"]
