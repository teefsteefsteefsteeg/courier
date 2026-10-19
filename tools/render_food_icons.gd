extends SceneTree
## Renders inventory icons for the consumables made from Food & Market models (Avramania,
## CC0, vendored in assets/models/food_market/) into assets/ui/item_icons/ (64x64 RGBA).
## Needs a GPU window (not --headless):
##   Godot_v4.7.2-stable_win64.exe --path . --script res://tools/render_food_icons.gd
## Each model is framed from the game's iso angle on a transparent background with a key
## and a rim light, then given the same dark outline as the other pixel icons.

const MODELS := "res://assets/models/food_market/mdvl_food_%s.glb"
const OUT := "res://assets/ui/item_icons/%s.png"
## icon name: [model, yaw degrees]
const ICONS := {
	"cheese_wheel": ["cheese_wheel_01", 20.0],
	"roast_ham": ["ham_01", -30.0],
	"sweet_grapes": ["grapes_01", 0.0],
	"warriors_ale": ["ale_mug_01", -40.0],
	"berserker_draught": ["potion_01", 15.0],
	"ironbark_stew": ["bowl_01", 0.0],
}
const SIZE := 256


func _initialize() -> void:
	_render.call_deferred()


func _render() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.75, 0.72, 0.68)
	environment.environment.ambient_light_energy = 0.7
	world.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, 30, 0)
	key.light_energy = 1.3
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 210, 0)
	rim.light_energy = 0.6
	world.add_child(rim)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(camera)
	for icon_name in ICONS:
		var spec: Array = ICONS[icon_name]
		var model := (load(MODELS % spec[0]) as PackedScene).instantiate() as Node3D
		world.add_child(model)
		model.rotation_degrees.y = spec[1]
		await process_frame
		var box := EnhancementGlow.local_bounds(model)
		var centre := model.global_transform * box.get_center()
		var radius := box.size.length() * 0.5
		camera.size = radius * 2.15
		camera.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-32), deg_to_rad(45), 0)), centre)
		camera.global_position = centre + camera.global_basis.z * 10.0
		camera.near = 0.01
		camera.far = 30.0
		for i in 4:
			await process_frame
		var image := viewport.get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		image.resize(64, 64, Image.INTERPOLATE_LANCZOS)
		_outline(image)
		image.save_png(ProjectSettings.globalize_path(OUT % icon_name))
		print("wrote ", OUT % icon_name)
		model.queue_free()
		await process_frame
	quit(0)


## A 1 px dark outline round the opaque shape (matches the cropped and drawn icons).
func _outline(image: Image) -> void:
	var source := image.duplicate() as Image
	for y in image.get_height():
		for x in image.get_width():
			if source.get_pixel(x, y).a > 0.35:
				continue
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := Vector2i(x, y) + offset
				if q.x >= 0 and q.y >= 0 and q.x < image.get_width() and q.y < image.get_height() and source.get_pixelv(q).a > 0.6:
					image.set_pixel(x, y, Color(0.1, 0.07, 0.06, 1.0))
					break
