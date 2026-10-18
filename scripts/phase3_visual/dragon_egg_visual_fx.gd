class_name DragonEggVisualFX
extends PackageVisualFX
## Dragon egg: shell emission, glow shell, light and embers follow temperature.
## Warm idle glow when unbound or safe, dim frost-blue with falling frost when
## cold, white-hot with a fast pulse and dense embers when overheating.

const COLD_COLOR := Color(0.35, 0.65, 1.0)
const WARM_COLOR := Color(1.0, 0.45, 0.15)
const HOT_COLOR := Color(1.0, 0.86, 0.55)

@export var base_glow := 0.35
@export var max_glow := 2.4

@onready var _egg: MeshInstance3D = $Egg
@onready var _glow_shell: MeshInstance3D = $GlowShell
@onready var _light: OmniLight3D = $GlowLight
@onready var _embers: CPUParticles3D = $Embers
@onready var _frost: CPUParticles3D = $Frost

var _egg_material: StandardMaterial3D
var _shell_material: StandardMaterial3D
var _glow_level := 0.0
var _glow_color := WARM_COLOR


func _ready() -> void:
	_egg_material = _egg.get_surface_override_material(0) as StandardMaterial3D
	_shell_material = _glow_shell.get_surface_override_material(0) as StandardMaterial3D
	super._ready()


## Steady glow strength before pulsing (for tests/tuning).
func get_glow_level() -> float:
	return _glow_level


func get_glow_color() -> Color:
	return _glow_color


func _update_effects(_delta: float) -> void:
	var bias := probe.get_temperature_bias()
	var heat := maxf(bias, 0.0)
	var cold := maxf(-bias, 0.0)
	_glow_color = WARM_COLOR.lerp(HOT_COLOR, heat) if bias >= 0.0 else WARM_COLOR.lerp(COLD_COLOR, cold)
	_glow_level = base_glow * (1.0 - 0.7 * cold) + heat * (max_glow - base_glow)
	var pulse := 0.5 + 0.5 * sin(_time * lerpf(1.6, 9.0, absf(bias)))
	var energy := _glow_level * (0.75 + 0.5 * pulse)
	if _egg_material != null:
		_egg_material.emission = _glow_color
		_egg_material.emission_energy_multiplier = energy
	if _shell_material != null:
		var shell := _glow_color
		shell.a = clampf(0.06 + 0.12 * energy, 0.0, 0.5)
		_shell_material.albedo_color = shell
	_light.light_color = _glow_color
	_light.light_energy = 0.2 + energy * 0.6
	_set_emitting(_embers, bias > -0.25)
	_embers.speed_scale = lerpf(0.7, 2.2, heat)
	_set_emitting(_frost, bias < -0.2)
