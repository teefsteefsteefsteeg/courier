class_name VfxStrip
extends Sprite3D
## A flipbook effect from one of the horizontal strips in assets/vfx/enhancement/ (made by
## tools/prep_enhancement_vfx.py from the Super Pixel Effects Gigapack; frame counts in
## frames.json), drawn as an additive, unshaded billboard tinted with `tint`. The strips
## are white, so the tint is the colour. Loops, plays once (then emits finished and frees
## itself when free_on_finish), or replays every repeat_every seconds.
##   var spark := VfxStrip.create(&"sparkle", 0.3, Color.GOLD)

signal finished

const DIR := "res://assets/vfx/enhancement/"

static var _frames: Dictionary = {}

var strip: StringName
var fps: float = 15.0
var loop: bool = true
## Seconds between the starts of a non-looping strip's replays (0 = play once).
var repeat_every: float = 0.0
var free_on_finish: bool = false
var _time: float = 0.0
var _frame_count: int = 1


## A strip (&"sparkle", &"aura", &"burst" or &"impact") size_m metres across.
## start_frame staggers several copies of the same loop.
static func create(strip_name: StringName, size_m: float, tint: Color, looping: bool = true, start_frame: int = 0) -> VfxStrip:
	var info := strip_info(strip_name)
	var sprite := VfxStrip.new()
	sprite.name = "Vfx_" + String(strip_name)
	sprite.strip = strip_name
	sprite.loop = looping
	sprite._frame_count = maxi(int(info.get("frames", 1)), 1)
	sprite.fps = float(info.get("fps", 15))
	sprite.texture = load(DIR + String(strip_name) + ".png") as Texture2D
	sprite.hframes = sprite._frame_count
	sprite.pixel_size = size_m / float(info.get("frame_width", 96))
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Tinted (white) sheets glow additively; full-colour flames and blasts keep their colours.
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if is_tinted(strip_name) else BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = sprite.texture
	material.albedo_color = tint if is_tinted(strip_name) else Color(1, 1, 1, tint.a)
	sprite.material_override = material
	sprite._time = float(start_frame % sprite._frame_count) / sprite.fps
	sprite.frame = start_frame % sprite._frame_count
	return sprite


## {"frame_width", "frame_height", "frames", "fps"} of a strip, from frames.json.
static func strip_info(strip_name: StringName) -> Dictionary:
	if _frames.is_empty():
		var file := FileAccess.open(DIR + "frames.json", FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_frames = parsed
	return _frames.get(String(strip_name), {})


## Seconds one pass of the strip takes.
func get_duration() -> float:
	return _frame_count / fps


func set_tint(tint: Color) -> void:
	(material_override as StandardMaterial3D).albedo_color = tint


func get_tint() -> Color:
	return (material_override as StandardMaterial3D).albedo_color


## Starts the strip again from its first frame.
func restart() -> void:
	_time = 0.0
	frame = 0
	visible = true


## Holds a non-looping strip hidden for seconds before it first plays (staggers copies).
func delay(seconds: float) -> void:
	_time = -seconds
	visible = false


## False for sheets that keep the pack's own colours (frames.json "tinted": false); those
## take a white tint so only the alpha changes.
static func is_tinted(strip_name: StringName) -> bool:
	return bool(strip_info(strip_name).get("tinted", true))


func _process(delta: float) -> void:
	_time += delta
	if _time < 0.0:
		return
	var index := int(_time * fps)
	if loop:
		frame = index % _frame_count
		return
	if index < _frame_count:
		frame = index
		visible = true
		return
	if visible:
		visible = false
		finished.emit()
		if free_on_finish:
			queue_free()
			return
	if repeat_every > 0.0 and _time >= repeat_every:
		restart()
