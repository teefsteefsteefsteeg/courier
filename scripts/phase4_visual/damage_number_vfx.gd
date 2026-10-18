extends Label3D
## Floating combat number: pops, rises and fades, then frees itself.

signal finished

@export var auto_animate := true
@export var duration := 0.8
@export var rise := 0.9

var elapsed := 0.0
var _start := Vector3.ZERO


func _process(delta: float) -> void:
	if auto_animate:
		advance(delta)


func configure(local_position: Vector3, amount: float, tint := Color(1.0, 0.9, 0.5)) -> void:
	_start = local_position
	position = local_position
	text = "-%d" % roundi(amount) if amount > 0.0 else "Blocked"
	modulate = tint
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	font_size = 48
	outline_size = 10
	pixel_size = 0.006
	elapsed = 0.0


func advance(delta: float) -> void:
	if is_queued_for_deletion():
		return
	elapsed += delta
	var k := clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
	position = _start + Vector3(0, rise * (1.0 - (1.0 - k) * (1.0 - k)), 0)
	var c := modulate
	c.a = 1.0 - k * k
	modulate = c
	scale = Vector3.ONE * (1.0 + 0.4 * maxf(0.0, 1.0 - k * 6.0))
	if k >= 1.0:
		finished.emit()
		queue_free()
