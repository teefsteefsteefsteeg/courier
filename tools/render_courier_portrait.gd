extends SceneTree
## Renders the courier's HUD portrait: the player's KayKit Ranger, idle pose, head and
## shoulders, three-quarter view, on a transparent background. Writes
## res://assets/ui/hud/courier_portrait.png (256x256). Needs a GPU window (not --headless):
##   godot --path . --script res://tools/render_courier_portrait.gd

const OUT := "res://assets/ui/hud/courier_portrait.png"
const MODEL := "res://assets/characters/kaykit_adventurers/Ranger.glb"
const SIZE := 256


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.82, 0.9)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.92, 0.8)
	key.light_energy = 1.3
	key.rotation_degrees = Vector3(-30, 35, 0)
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.6, 0.7, 1.0)
	rim.light_energy = 0.6
	rim.rotation_degrees = Vector3(-10, 200, 0)
	viewport.add_child(rim)
	var character := KayKitCharacter.new()
	character.model = load(MODEL) as PackedScene
	viewport.add_child(character)
	for i in 20:
		await process_frame
	# Freeze the idle pose and frame the head (KayKit rigs name it "head").
	character.animation_player.seek(0.35, true)
	character.animation_player.pause()
	var skeleton := character.skeleton
	var head := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("head"))
	var focus := head.origin + Vector3(0, 0.16, 0)
	var camera := Camera3D.new()
	camera.fov = 26.0
	viewport.add_child(camera)
	# The model faces -Z (KayKitCharacter turns it); look at it from the front-right.
	camera.look_at_from_position(focus + Vector3(0.75, 0.12, -2.05).normalized() * 3.5, focus, Vector3.UP)
	camera.current = true
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	print("portrait saved err=", image.save_png(ProjectSettings.globalize_path(OUT)))
	quit()
