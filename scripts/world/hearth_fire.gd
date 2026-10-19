class_name HearthFire
extends Node3D
## A fire in a hearth or forge (Phase 8 interiors): Gigapack flame flipbooks and a warm,
## flickering OmniLight, built at runtime so the generated scenes stay small.

@export_range(0.1, 3.0, 0.05, "suffix:m") var size: float = 0.6
@export var light_energy: float = 2.2
@export var light_range: float = 6.0

var light: OmniLight3D
var _time := 0.0


func _ready() -> void:
	for i in 2:
		var flame := VfxStrip.create(&"flame" if i == 0 else &"flame_b", size * (1.0 - 0.25 * i), Color.WHITE, true, i * 2)
		flame.position = Vector3(0.12 * i - 0.06, size * 0.45, 0.0)
		add_child(flame)
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.3)
	light.light_energy = light_energy
	light.omni_range = light_range
	light.position = Vector3(0, size * 0.6, 0)
	add_child(light)


func _process(delta: float) -> void:
	_time += delta
	light.light_energy = light_energy * (0.85 + 0.15 * sin(_time * 17.0) * sin(_time * 5.3))
