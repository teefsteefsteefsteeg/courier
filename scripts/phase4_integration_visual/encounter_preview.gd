extends Node3D
## Standalone fallback preview for the Phase 4 integration encounter
## presentation. Builds a small colourful forest clearing, a courier stand-in
## and four enemies (2 Forest Slimes, 2 Frost Wisps), then drives the real
## presentation scene through preview-only stand-ins that expose the gameplay
## contract signal names (CombatController / CombatHealth / package). Nothing
## here is used by gameplay; it only proves the layer works by itself.
##   [1] Magic Bolt  [2] Dash  [3] Shield  [4] Take hit  [5] Heat package
##   [6] Advance route  [7] Reset  [F] Toggle auto demo

const PRESENTATION_SCENE := preload("res://scenes/gameplay/phase4_integration_visual/encounter_presentation.tscn")
const PreviewController := preload("res://scripts/phase4_integration_visual/preview_combat_controller.gd")
const PreviewHealth := preload("res://scripts/phase4_integration_visual/preview_combat_health.gd")
const PreviewPackage := preload("res://scripts/phase4_integration_visual/preview_package.gd")
const Lowpoly := preload("res://scripts/phase4_visual/lowpoly.gd")

const ENEMY_LAYOUT := [
	[&"forest_slime", Vector3(2.8, 0, -3.5)],
	[&"frost_wisp", Vector3(-2.8, 0, -6.0)],
	[&"forest_slime", Vector3(-0.6, 0, -9.5)],
	[&"frost_wisp", Vector3(3.6, 0, -11.5)],
]
const ROUTE := [
	Vector3(0, 0, 4), Vector3(0, 0, -1), Vector3(2.0, 0, -5), Vector3(-1.0, 0, -10), Vector3(1.5, 0, -15),
]
const TREE_LAYOUT := [
	[Vector3(-5.5, 0, 3), 0], [Vector3(5, 0, 2), 1], [Vector3(-6, 0, -2), 2], [Vector3(6.5, 0, -3), 3],
	[Vector3(-7, 0, -7), 4], [Vector3(7.5, 0, -8), 0], [Vector3(-5.5, 0, -12), 5], [Vector3(6, 0, -14), 2],
	[Vector3(-4, 0, -17), 1], [Vector3(4.5, 0, -18), 4], [Vector3(-8.5, 0, 0), 3], [Vector3(9, 0, -11), 5],
	[Vector3(-3.5, 0, 6), 0], [Vector3(3.8, 0, 6.5), 2],
]
const LEAF_COLORS := [
	Color(0.2, 0.5, 0.22), Color(0.55, 0.85, 0.3), Color(1.0, 0.55, 0.25),
	Color(1.0, 0.6, 0.78), Color(0.3, 0.7, 0.65), Color(1.0, 0.82, 0.3),
]
const DEMO_ACTIONS := [
	&"bolt", &"bolt", &"dash", &"shield", &"hurt", &"advance", &"bolt",
	&"heat", &"hurt", &"shield", &"advance", &"hurt", &"advance", &"advance", &"reset",
]
const CAMERA_OFFSET := Vector3(9.0, 11.0, 9.0)

@export var auto_demo := true
@export var demo_interval := 1.4
@export var bolt_damage := 10.0
@export var bolt_speed := 16.0  ## matches the Phase 4 magic bolt VFX speed
@export var dash_distance := 2.5
@export var hurt_damage := 15.0
@export var respawn_delay := 3.0

var presentation: Node3D
var controller: Node
var player_health: Node
var package: Node
var courier: Node3D
var camera: Camera3D
var help_label: Label
var enemies: Array[Node3D] = []
var shield_on := false
var shield_durability := 1.0
var last_action: StringName = &""

var _demo_timer := 0.0
var _demo_step := 0
var _route_index := 0
var _dash_sign := 1.0
var _pending_hits: Array = []  ## {time, enemy, amount, origin}
var _respawns: Array = []  ## {time, health}


func _ready() -> void:
	_build_world()
	_build_courier()
	_build_enemies()
	presentation = PRESENTATION_SCENE.instantiate() as Node3D
	presentation.set(&"auto_discover", false)  # bind the stand-ins explicitly
	add_child(presentation)
	presentation.call(&"bind_controller", controller)
	presentation.call(&"bind_package", package)
	var route_points := PackedVector3Array()
	for p in ROUTE:
		route_points.append(p)
	presentation.call(&"set_route", route_points)
	presentation.call(&"set_destination", ROUTE[ROUTE.size() - 1], "Moonwell Shrine")
	presentation.call(&"set_quest", "Moonpetal Delivery", "Carry the tonic through Whisperwood to the Moonwell Shrine.")
	presentation.call(&"add_quest_marker", &"herbalist", Vector3(-3.0, 0, 3.0), "Herbalist", Color(0.75, 0.55, 1.0))
	player_health.call(&"revive")
	_build_help()
	_update_camera()


func _process(delta: float) -> void:
	_update_pending_hits(delta)
	_update_respawns(delta)
	if auto_demo:
		_demo_timer += delta
		if _demo_timer >= demo_interval:
			_demo_timer = 0.0
			trigger_preview(DEMO_ACTIONS[_demo_step % DEMO_ACTIONS.size()])
			_demo_step += 1
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1: trigger_preview(&"bolt")
		KEY_2: trigger_preview(&"dash")
		KEY_3: trigger_preview(&"shield")
		KEY_4: trigger_preview(&"hurt")
		KEY_5: trigger_preview(&"heat")
		KEY_6: trigger_preview(&"advance")
		KEY_7: trigger_preview(&"reset")
		KEY_F:
			auto_demo = not auto_demo
			_update_help()


## Runs one preview action through the stand-in gameplay nodes. Returns true
## if the action did something.
func trigger_preview(action: StringName) -> bool:
	var done := false
	match action:
		&"bolt": done = _preview_bolt()
		&"dash": done = _preview_dash()
		&"shield": done = _preview_shield()
		&"hurt": done = _preview_hurt()
		&"heat": done = _preview_heat()
		&"advance": done = _preview_advance()
		&"reset": done = _preview_reset()
	if done:
		last_action = action
	return done


func get_living_enemies() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for enemy in enemies:
		if not bool(_health_of(enemy).call(&"is_dead")):
			out.append(enemy)
	return out


func get_enemy_hp(enemy: Node3D) -> float:
	return float(_health_of(enemy).get(&"current_health"))


# --- actions -------------------------------------------------------------------

func _preview_bolt() -> bool:
	var target := _nearest_living_enemy()
	if target == null:
		return false
	var origin := courier.global_position + Vector3(0, 1.0, 0)
	var aim := target.global_position + Vector3(0, 0.8, 0)
	if not bool(controller.call(&"fire", origin, aim - origin)):
		return false
	_pending_hits.append({"time": origin.distance_to(aim) / maxf(bolt_speed, 0.1), "enemy": target, "amount": bolt_damage, "origin": origin})
	return true


func _preview_dash() -> bool:
	if not bool(controller.call(&"begin_dash")):
		return false
	courier.position += Vector3(_dash_sign * dash_distance, 0, 0)
	_dash_sign = -_dash_sign
	controller.call(&"end_dash")
	return true


func _preview_shield() -> bool:
	shield_on = not shield_on
	if shield_on and shield_durability <= 0.0:
		shield_durability = 1.0
	controller.call(&"set_shield", shield_on, shield_durability)
	return true


func _preview_hurt() -> bool:
	var source := courier.global_position + Vector3(1, 0, -1)
	if shield_on:
		player_health.call(&"apply_damage", 0.0, source)
		shield_durability = maxf(0.0, shield_durability - 0.34)
		if shield_durability <= 0.0:
			shield_on = false
		controller.call(&"set_shield", shield_on, shield_durability)
	else:
		player_health.call(&"apply_damage", hurt_damage, source)
		package.call(&"apply_damage", hurt_damage * 1.4)
	return true


func _preview_heat() -> bool:
	var t := float(package.get(&"temperature")) + 16.0
	package.call(&"set_temperature", t if t <= 98.0 else 50.0)
	package.call(&"set_instability", fposmod(float(package.get(&"instability")) + 0.3, 1.2))
	return true


func _preview_advance() -> bool:
	if _route_index >= ROUTE.size() - 1:
		return false
	_route_index += 1
	courier.position = ROUTE[_route_index]
	if _route_index == ROUTE.size() - 1:
		presentation.call(&"set_quest_state", &"complete")
	return true


func _preview_reset() -> bool:
	_pending_hits.clear()
	_respawns.clear()
	for enemy in enemies:
		_health_of(enemy).call(&"revive")
	player_health.call(&"revive")
	package.call(&"reset")
	shield_on = false
	shield_durability = 1.0
	controller.call(&"set_shield", false, 1.0)
	controller.call(&"reset")
	_route_index = 0
	_dash_sign = 1.0
	courier.position = ROUTE[0]
	presentation.call(&"set_quest_state", &"active")
	return true


# --- simulation ----------------------------------------------------------------

func _update_pending_hits(delta: float) -> void:
	var still: Array = []
	for hit: Dictionary in _pending_hits:
		hit["time"] = float(hit["time"]) - delta
		if float(hit["time"]) > 0.0:
			still.append(hit)
			continue
		var enemy: Node3D = hit["enemy"]
		if not is_instance_valid(enemy):
			continue
		var health := _health_of(enemy)
		if bool(health.call(&"is_dead")):
			continue
		# Gameplay order: health reacts first, then the controller reports the hit.
		health.call(&"apply_damage", float(hit["amount"]), hit["origin"])
		controller.call(&"report_hit", enemy, float(hit["amount"]))
		if bool(health.call(&"is_dead")):
			_respawns.append({"time": respawn_delay, "health": health})
	_pending_hits = still


func _update_respawns(delta: float) -> void:
	var still: Array = []
	for entry: Dictionary in _respawns:
		entry["time"] = float(entry["time"]) - delta
		if float(entry["time"]) > 0.0:
			still.append(entry)
		elif is_instance_valid(entry["health"]):
			entry["health"].call(&"revive")
	_respawns = still


func _nearest_living_enemy() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for enemy in get_living_enemies():
		var d := enemy.global_position.distance_to(courier.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best


func _health_of(enemy: Node3D) -> Node:
	return enemy.get_node(^"CombatHealth")


# --- world ---------------------------------------------------------------------

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.78, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.85, 0.8)
	env.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	camera = Camera3D.new()
	camera.name = "PreviewCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17.0
	camera.current = true
	add_child(camera)

	var forest := Node3D.new()
	forest.name = "Forest"
	add_child(forest)
	var ground_mat := Lowpoly.load_material("forest_ground.tres", Color(0.29, 0.45, 0.22))
	Lowpoly.add_part(forest, "Ground", Lowpoly.plane(Vector2(40, 40)), ground_mat, Vector3(0, 0, -6))
	var trees := Node3D.new()
	trees.name = "Trees"
	forest.add_child(trees)
	var bark := Lowpoly.load_material("tree_bark.tres", Color(0.4, 0.27, 0.16))
	var leaf_base := Lowpoly.load_material("tree_leaves.tres", Color(0.2, 0.5, 0.22))
	var leaves: Array[StandardMaterial3D] = []
	for c in LEAF_COLORS:
		var mat := leaf_base.duplicate() as StandardMaterial3D
		mat.albedo_color = c
		leaves.append(mat)
	for i in TREE_LAYOUT.size():
		var entry: Array = TREE_LAYOUT[i]
		_add_tree(trees, "Tree%d" % i, entry[0], bark, leaves[int(entry[1]) % leaves.size()], 0.85 + 0.1 * float(i % 4))


func _add_tree(parent: Node3D, tree_name: String, at: Vector3, bark: Material, leaf: Material, size: float) -> void:
	var tree := Node3D.new()
	tree.name = tree_name
	tree.position = at
	tree.scale = Vector3.ONE * size
	tree.rotation.y = at.x * 0.7
	parent.add_child(tree)
	Lowpoly.add_part(tree, "Trunk", Lowpoly.cone(0.2, 0.15, 0.9, 5), bark, Vector3(0, 0.45, 0))
	Lowpoly.add_part(tree, "CanopyLow", Lowpoly.cone(1.0, 0.0, 1.4, 6), leaf, Vector3(0, 1.5, 0))
	Lowpoly.add_part(tree, "CanopyHigh", Lowpoly.cone(0.7, 0.0, 1.1, 6), leaf, Vector3(0, 2.25, 0))


func _build_courier() -> void:
	courier = Node3D.new()
	courier.name = "Courier"
	courier.position = ROUTE[0]
	add_child(courier)
	var body := Node3D.new()
	body.name = "Body"
	courier.add_child(body)
	Lowpoly.add_part(body, "Torso", Lowpoly.capsule(0.3, 1.2, 6, 2), Lowpoly.make_material(Color(0.25, 0.4, 0.75)), Vector3(0, 0.6, 0))
	Lowpoly.add_part(body, "Hood", Lowpoly.cone(0.28, 0.0, 0.4, 6), Lowpoly.make_material(Color(0.85, 0.3, 0.3)), Vector3(0, 1.35, 0))
	Lowpoly.add_part(body, "Package", Lowpoly.box(Vector3(0.45, 0.35, 0.3)), Lowpoly.make_material(Color(0.8, 0.6, 0.3)), Vector3(0, 0.85, 0.32))

	controller = PreviewController.new()
	controller.name = "CombatController"
	courier.add_child(controller)
	player_health = PreviewHealth.new()
	player_health.name = "CombatHealth"
	player_health.set(&"max_health", 100.0)
	courier.add_child(player_health)
	package = PreviewPackage.new()
	package.name = "Package"
	courier.add_child(package)


func _build_enemies() -> void:
	var root := Node3D.new()
	root.name = "Enemies"
	add_child(root)
	var counts := {}
	for entry: Array in ENEMY_LAYOUT:
		var kind: StringName = entry[0]
		counts[kind] = int(counts.get(kind, 0)) + 1
		var enemy := Node3D.new()
		enemy.name = "%s%d" % [String(kind).to_pascal_case(), counts[kind]]
		enemy.position = entry[1]
		enemy.set_meta(&"enemy_kind", kind)
		enemy.add_to_group(&"enemies")
		var health := PreviewHealth.new()
		health.name = "CombatHealth"
		health.set(&"max_health", 30.0)
		enemy.add_child(health)
		root.add_child(enemy)
		enemies.append(enemy)


func _build_help() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "PreviewHelp"
	canvas.layer = 8
	add_child(canvas)
	help_label = Label.new()
	help_label.name = "Help"
	help_label.position = Vector2(16, 16)
	help_label.add_theme_font_size_override(&"font_size", 14)
	help_label.add_theme_color_override(&"font_color", Color(1.0, 0.97, 0.88))
	help_label.add_theme_color_override(&"font_outline_color", Color(0.05, 0.08, 0.05))
	help_label.add_theme_constant_override(&"outline_size", 4)
	canvas.add_child(help_label)
	_update_help()


func _update_help() -> void:
	if help_label == null:
		return
	help_label.text = "Phase 4 integration preview (stand-in gameplay)\n" \
		+ "[1] Magic Bolt  [2] Dash  [3] Shield  [4] Take hit\n" \
		+ "[5] Heat package  [6] Advance route  [7] Reset\n" \
		+ "[F] Auto demo: %s" % ("on" if auto_demo else "off")


func _update_camera() -> void:
	if camera == null or courier == null or not camera.is_inside_tree():
		return
	var focus := courier.global_position + Vector3(0, 0, -3)
	camera.look_at_from_position(focus + CAMERA_OFFSET, focus, Vector3.UP)
