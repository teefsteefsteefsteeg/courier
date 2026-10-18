extends Node3D
## Manual preview: cycles a stand-in package through safe, hot, freezing and
## volatile states so the package visuals and status HUD can be eyeballed.
## Not referenced by gameplay.

class PreviewPackage extends RefCounted:
	signal temperature_changed(new_value: float, old_value: float)
	signal instability_changed(new_value: float, old_value: float)

	var temperature := 50.0
	var instability := 0.0

	func get_display_name() -> String:
		return "Preview Cargo"

	func set_status(new_temperature: float, new_instability: float) -> void:
		var old_temperature := temperature
		var old_instability := instability
		temperature = new_temperature
		instability = clampf(new_instability, 0.0, 1.0)
		temperature_changed.emit(temperature, old_temperature)
		instability_changed.emit(instability, old_instability)


@export var cycle_seconds := 12.0

@onready var _parcel: PackageVisualFX = $Parcel
@onready var _egg: DragonEggVisualFX = $DragonEgg
@onready var _crate: PotionCrateVisualFX = $PotionCrate
@onready var _hud: PackageStatusHUD = $HUDLayer/PackageStatusHUD

var _package := PreviewPackage.new()
var _time := 0.0
var _next_jolt := 3.0


func _ready() -> void:
	_egg.bind_package(_package)
	_crate.bind_package(_package)
	_hud.bind_package(_package)


func _process(delta: float) -> void:
	_time += delta
	var phase := fmod(_time / cycle_seconds, 1.0) * TAU
	_package.set_status(50.0 + 48.0 * sin(phase), 0.5 + 0.5 * sin(phase * 2.0 + 1.0))
	if _time >= _next_jolt:
		_next_jolt += 3.0
		_parcel.play_impact()
