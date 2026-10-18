class_name PotionCrateVisualFX
extends PackageVisualFX
## Volatile potion crate: bottle glow shifts green -> amber -> red and flickers,
## bubbles speed up, bottles rattle and corks pop as instability rises; vapor
## vents once the crate is unstable. Unbound crates idle with a gentle simmer.

const CALM_COLOR := Color(0.3, 1.0, 0.45)
const AGITATED_COLOR := Color(1.0, 0.85, 0.2)
const VOLATILE_COLOR := Color(1.0, 0.25, 0.15)

@export var idle_instability := 0.12
@export var max_rattle := 0.22
@export var cork_pop_height := 0.03

@onready var _bottles: Array[Node3D] = [$BottleA, $BottleB, $BottleC]
@onready var _corks: Array[Node3D] = [$BottleA/Cork, $BottleB/Cork, $BottleC/Cork]
@onready var _bubbles: CPUParticles3D = $Bubbles
@onready var _vapor: CPUParticles3D = $Vapor
@onready var _light: OmniLight3D = $HazardLight

var _potion_material: StandardMaterial3D
var _cork_rest: Array[float] = []
var _agitation := 0.0
var _rattle := 0.0
var _potion_color := CALM_COLOR


func _ready() -> void:
	_potion_material = (_bottles[0] as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
	for cork in _corks:
		_cork_rest.append(cork.position.y)
	super._ready()


## Instability driving the effects, 0..1 (idle value when unbound).
func get_agitation() -> float:
	return _agitation


func get_rattle_amount() -> float:
	return _rattle


func get_potion_color() -> Color:
	return _potion_color


func _update_effects(_delta: float) -> void:
	_agitation = probe.get_instability_ratio() if probe.has_instability() else idle_instability
	var r := _agitation
	if r < 0.5:
		_potion_color = CALM_COLOR.lerp(AGITATED_COLOR, r / 0.5)
	else:
		_potion_color = AGITATED_COLOR.lerp(VOLATILE_COLOR, (r - 0.5) / 0.5)
	var flicker := 1.0 + r * 0.5 * sin(_time * 31.0) * sin(_time * 17.0)
	var energy := lerpf(0.8, 2.5, r) * flicker
	if _potion_material != null:
		_potion_material.albedo_color = _potion_color.lightened(0.15)
		_potion_material.emission = _potion_color
		_potion_material.emission_energy_multiplier = energy

	_rattle = max_rattle * r * r
	for i in _bottles.size():
		var phase := i * 2.3
		_bottles[i].rotation = Vector3(
			sin(_time * 23.0 + phase) * _rattle, 0.0, cos(_time * 19.0 + phase) * _rattle)
	var popping := r >= PackageStatusProbe.CRITICAL_INSTABILITY
	for i in _corks.size():
		var lift := 0.0
		if popping:
			lift = cork_pop_height * (0.6 + 0.4 * absf(sin(_time * 20.0 + i * 1.9)))
		_corks[i].position.y = _cork_rest[i] + lift

	_bubbles.color = _potion_color
	_bubbles.speed_scale = lerpf(0.6, 3.0, r)
	_vapor.color = _potion_color.lerp(Color.WHITE, 0.4)
	_set_emitting(_vapor, r >= PackageStatusProbe.CAUTION_INSTABILITY)
	_light.light_color = _potion_color
	_light.light_energy = 0.15 + energy * 0.35
