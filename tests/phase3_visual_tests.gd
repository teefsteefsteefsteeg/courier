extends SceneTree
## Phase 3 visual tests. Run headless from the project root:
##   godot --headless --path . -s res://tests/phase3_visual_tests.gd
## Exit code is 0 when every check passes, 1 otherwise.

const PARCEL_SCENE := "res://scenes/gameplay/packages/visuals/parcel_visual.tscn"
const EGG_SCENE := "res://scenes/gameplay/packages/visuals/dragon_egg_visual.tscn"
const CRATE_SCENE := "res://scenes/gameplay/packages/visuals/potion_crate_visual.tscn"
const HUD_SCENE := "res://scenes/gameplay/phase3_visual/package_status_hud.tscn"

const NONE := PackageStatusProbe.WarningLevel.NONE
const CAUTION := PackageStatusProbe.WarningLevel.CAUTION
const CRITICAL := PackageStatusProbe.WarningLevel.CRITICAL


## Full Phase 3 interface with signals of differing arity.
class SignalPackage extends RefCounted:
	signal temperature_changed(new_value: float, old_value: float)
	signal instability_changed(new_value: float)

	var temperature := 50.0
	var instability := 0.0

	func get_temperature() -> float:
		return temperature

	func get_temperature_limits() -> Vector2:
		return Vector2(0.0, 100.0)

	func get_safe_temperature_range() -> Vector2:
		return Vector2(40.0, 60.0)

	func get_instability() -> float:
		return instability

	func get_max_instability() -> float:
		return 10.0

	func get_package_id() -> StringName:
		return &"mock_egg"

	func set_temperature(value: float) -> void:
		var old := temperature
		temperature = value
		temperature_changed.emit(temperature, old)

	func set_instability(value: float) -> void:
		instability = value
		instability_changed.emit(instability)


## Plain properties, no signals: must be picked up by polling.
class PolledPackage extends RefCounted:
	var temperature := 50.0
	var instability := 0.0


## Exposes getters but opts out via the uses_* gates.
class GatedPackage extends RefCounted:
	func uses_temperature() -> bool:
		return false

	func uses_instability() -> bool:
		return true

	func get_temperature() -> float:
		return 999.0

	func get_instability() -> float:
		return 0.2


var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_visual_scenes_keep_paths_and_names()
	_test_probe_feature_detection()
	_test_probe_thresholds()
	await _test_dragon_egg_tracks_temperature()
	await _test_egg_materials_are_per_instance()
	await _test_potion_crate_tracks_instability()
	await _test_impact_on_integrity_loss()
	await _test_meta_auto_binding()
	await _test_hud_signal_binding_and_warnings()
	await _test_hud_polling_and_gates()
	print("phase3_visual_tests: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: ", label)


func _spawn(path: String) -> Node:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate()
	root.add_child(node)
	return node


func _make_package_instance() -> PackageInstance:
	var definition := PackageDefinition.new()
	definition.integrity = 100.0
	return PackageInstance.new(definition)


func _test_visual_scenes_keep_paths_and_names() -> void:
	var expectations := {
		PARCEL_SCENE: ["ParcelVisual", ["Box", "StringA", "StringB", "Knot", "Seal"]],
		EGG_SCENE: ["DragonEggVisual", ["Egg", "SpotA", "SpotB", "GlowShell", "Nest", "GlowLight", "Embers", "Frost"]],
		CRATE_SCENE: ["PotionCrateVisual", ["Crate", "BottleA", "BottleB", "BottleC", "BottleA/Cork",
			"HazardLight", "Bubbles", "Vapor"]],
	}
	for path: String in expectations:
		var node := _spawn(path)
		_check(node != null, "scene loads: " + path)
		if node == null:
			continue
		_check(node is Node3D, "root is Node3D: " + path)
		_check(node is PackageVisualFX, "root uses PackageVisualFX: " + path)
		_check(String(node.name) == expectations[path][0], "root name preserved: " + path)
		for child_name: String in expectations[path][1]:
			_check(node.has_node(child_name), "%s has %s" % [path, child_name])
		var visual := node as PackageVisualFX
		if visual != null:
			_check(visual.warning_level == NONE, "unbound visual is calm: " + path)
		node.queue_free()
	await process_frame


func _test_probe_feature_detection() -> void:
	var plain := PackageStatusProbe.new(_make_package_instance())
	_check(plain.is_bound(), "probe binds Phase 2 PackageInstance")
	_check(not plain.has_temperature(), "Phase 2 package has no temperature")
	_check(not plain.has_instability(), "Phase 2 package has no instability")
	_check(plain.has_integrity(), "Phase 2 package has integrity")
	_check(is_equal_approx(plain.get_integrity_ratio(), 1.0), "fresh integrity ratio is 1")
	_check(plain.get_warning_level() == NONE, "Phase 2 package never warns")
	_check(not plain.needs_polling(), "Phase 2 package needs no polling")

	var mock := SignalPackage.new()
	var probe := PackageStatusProbe.new(mock)
	_check(probe.has_temperature() and probe.has_instability(), "mock exposes both features")
	_check(probe.get_safe_temperature_range() == Vector2(40.0, 60.0), "safe range read from method")
	_check(not probe.needs_polling(), "signals avoid polling")
	var changes := [0]
	probe.status_changed.connect(func() -> void: changes[0] += 1)
	mock.set_temperature(70.0)
	mock.set_instability(5.0)
	_check(changes[0] == 2, "two-arg and one-arg change signals both relay")
	_check(is_equal_approx(probe.get_instability_ratio(), 0.5), "instability ratio uses max")
	_check(probe.get_display_name() == "Mock Egg", "display name falls back to package id")
	probe.unbind()
	mock.set_temperature(10.0)
	_check(changes[0] == 2, "unbind disconnects signals")

	var polled := PackageStatusProbe.new(PolledPackage.new())
	_check(polled.has_temperature() and polled.has_instability(), "property-only features detected")
	_check(polled.needs_polling(), "property-only package needs polling")
	_check(polled.get_temperature_limits() == PackageStatusProbe.DEFAULT_TEMPERATURE_LIMITS,
		"default temperature limits")
	_check(polled.get_safe_temperature_range().is_equal_approx(Vector2(35.0, 65.0)), "default safe band")

	var gated := PackageStatusProbe.new(GatedPackage.new())
	_check(not gated.has_temperature(), "uses_temperature() gate hides temperature")
	_check(gated.has_instability(), "uses_instability() gate allows instability")


func _test_probe_thresholds() -> void:
	_check(PackageStatusProbe.warning_for(0.0, 0.0) == NONE, "calm is NONE")
	_check(PackageStatusProbe.warning_for(0.1, 0.0) == CAUTION, "outside safe range is CAUTION")
	_check(PackageStatusProbe.warning_for(0.0, 0.5) == CAUTION, "half instability is CAUTION")
	_check(PackageStatusProbe.warning_for(0.6, 0.0) == CRITICAL, "near temperature limit is CRITICAL")
	_check(PackageStatusProbe.warning_for(0.0, 0.8) == CRITICAL, "high instability is CRITICAL")
	var limits := Vector2(0.0, 100.0)
	var safe := Vector2(40.0, 60.0)
	_check(PackageStatusProbe.temperature_bias(50.0, limits, safe) == 0.0, "safe bias is 0")
	_check(is_equal_approx(PackageStatusProbe.temperature_bias(80.0, limits, safe), 0.5), "hot bias")
	_check(is_equal_approx(PackageStatusProbe.temperature_bias(0.0, limits, safe), -1.0), "frozen bias")


func _test_dragon_egg_tracks_temperature() -> void:
	var egg := _spawn(EGG_SCENE) as DragonEggVisualFX
	_check(egg != null, "egg uses DragonEggVisualFX")
	if egg == null:
		return
	var embers := egg.get_node("Embers") as CPUParticles3D
	var frost := egg.get_node("Frost") as CPUParticles3D
	var neutral := egg.get_glow_level()
	_check(embers.emitting and not frost.emitting, "idle egg smoulders without frost")

	var package := SignalPackage.new()
	egg.bind_package(package)
	package.set_temperature(98.0)
	egg.update_visual(0.016)
	var hot := egg.get_glow_level()
	_check(hot > neutral, "overheating egg glows brighter")
	_check(embers.emitting and not frost.emitting, "hot egg throws embers")
	_check(egg.warning_level == CRITICAL, "overheating egg is CRITICAL")
	_check(egg.get_glow_color().b > DragonEggVisualFX.WARM_COLOR.b, "hot glow whitens")

	package.set_temperature(2.0)
	egg.update_visual(0.016)
	_check(egg.get_glow_level() < neutral, "freezing egg dims")
	_check(frost.emitting and not embers.emitting, "freezing egg frosts over")
	_check(egg.get_glow_color().b > egg.get_glow_color().r, "cold glow turns blue")

	var levels := []
	egg.warning_level_changed.connect(func(level: int) -> void: levels.append(level))
	package.set_temperature(50.0)
	egg.update_visual(0.016)
	_check(egg.warning_level == NONE and levels == [NONE], "safe egg clears warning once")
	egg.queue_free()
	await process_frame


func _test_egg_materials_are_per_instance() -> void:
	var a := _spawn(EGG_SCENE) as DragonEggVisualFX
	var b := _spawn(EGG_SCENE) as DragonEggVisualFX
	if a == null or b == null:
		_check(false, "spawn two eggs")
		return
	var mat_a := (a.get_node("Egg") as MeshInstance3D).get_surface_override_material(0)
	var mat_b := (b.get_node("Egg") as MeshInstance3D).get_surface_override_material(0)
	_check(mat_a != mat_b, "egg shell material is local to each instance")
	var package := SignalPackage.new()
	a.bind_package(package)
	package.set_temperature(99.0)
	a.update_visual(0.016)
	b.update_visual(0.016)
	_check(a.get_glow_level() > b.get_glow_level(), "heating one egg leaves the other unchanged")
	a.queue_free()
	b.queue_free()
	await process_frame


func _test_potion_crate_tracks_instability() -> void:
	var crate := _spawn(CRATE_SCENE) as PotionCrateVisualFX
	_check(crate != null, "crate uses PotionCrateVisualFX")
	if crate == null:
		return
	var vapor := crate.get_node("Vapor") as CPUParticles3D
	var bubbles := crate.get_node("Bubbles") as CPUParticles3D
	var cork := crate.get_node("BottleA/Cork") as Node3D
	var cork_rest := cork.position.y
	_check(bubbles.emitting and not vapor.emitting, "idle crate simmers without vapor")
	_check(is_equal_approx(crate.get_agitation(), crate.idle_instability), "unbound crate uses idle agitation")

	var package := SignalPackage.new()
	crate.bind_package(package)
	package.set_instability(1.0)
	crate.update_visual(0.016)
	var calm_rattle := crate.get_rattle_amount()
	_check(crate.warning_level == NONE and not vapor.emitting, "low instability stays calm")

	package.set_instability(6.0)
	crate.update_visual(0.016)
	_check(crate.warning_level == CAUTION and vapor.emitting, "unstable crate vents vapor")

	package.set_instability(9.5)
	crate.update_visual(0.1)
	_check(crate.warning_level == CRITICAL, "volatile crate is CRITICAL")
	_check(crate.get_rattle_amount() > calm_rattle, "volatile bottles rattle harder")
	_check(cork.position.y > cork_rest, "volatile corks pop")
	_check(crate.get_potion_color().g < 0.6, "volatile potion turns red")
	_check(bubbles.speed_scale > 2.0, "volatile potion boils faster")

	package.set_instability(0.0)
	crate.update_visual(0.016)
	_check(is_equal_approx(cork.position.y, cork_rest), "corks reseat when calm")
	crate.queue_free()
	await process_frame


func _test_impact_on_integrity_loss() -> void:
	var parcel := _spawn(PARCEL_SCENE) as PackageVisualFX
	if parcel == null:
		_check(false, "parcel spawns")
		return
	var box := parcel.get_node("Box") as Node3D
	var rest := box.position
	var package := _make_package_instance()
	parcel.bind_package(package)
	_check(parcel.get_impact() == 0.0, "binding does not jolt")
	package.set_integrity(60.0)
	_check(parcel.get_impact() > 0.0, "integrity loss triggers impact")
	parcel.update_visual(0.01)
	_check(not box.position.is_equal_approx(rest), "impact shakes the model")
	for i in 60:
		parcel.update_visual(0.05)
	_check(parcel.get_impact() == 0.0, "impact decays")
	_check(box.position.is_equal_approx(rest), "model settles to rest position")
	_check(parcel.position == Vector3.ZERO, "root transform is never moved")
	parcel.unbind_package()
	_check(parcel.get_bound_package() == null, "unbind clears package")
	parcel.queue_free()
	await process_frame


func _test_meta_auto_binding() -> void:
	var packed := load(EGG_SCENE) as PackedScene
	var egg := packed.instantiate() as DragonEggVisualFX
	var package := SignalPackage.new()
	package.temperature = 95.0
	egg.set_meta(PackageVisualFX.META_PACKAGE, package)
	root.add_child(egg)
	_check(egg.get_bound_package() == package, "metadata binds package on ready")
	_check(egg.warning_level == CRITICAL, "auto-bound egg reflects status immediately")
	egg.queue_free()
	await process_frame


func _test_hud_signal_binding_and_warnings() -> void:
	var hud := _spawn(HUD_SCENE) as PackageStatusHUD
	_check(hud != null, "HUD scene uses PackageStatusHUD")
	if hud == null:
		return
	await process_frame
	_check(not hud.visible, "unbound HUD hides")

	hud.bind_package(_make_package_instance())
	_check(not hud.visible, "HUD hides for package without temperature/instability")

	var package := SignalPackage.new()
	hud.bind_package(package)
	_check(hud.visible, "HUD shows for status package")
	_check(hud.is_temperature_shown() and hud.is_instability_shown(), "both rows shown")
	_check(hud.get_warning_level() == NONE and not hud.is_warning_animating(), "calm HUD is quiet")
	var bar := hud.get_node("Panel/Rows/TemperatureRow/Bar") as ProgressBar
	var band := hud.get_node("Panel/Rows/TemperatureRow/Bar/SafeBand") as Control
	_check(is_equal_approx(band.anchor_left, 0.4) and is_equal_approx(band.anchor_right, 0.6),
		"safe band matches package range")

	var levels := []
	hud.warning_level_changed.connect(func(level: int) -> void: levels.append(level))
	package.set_temperature(65.0)
	_check(is_equal_approx(bar.value, 0.65), "temperature bar follows signal")
	_check(hud.get_warning_level() == CAUTION, "warm package is CAUTION")
	_check(hud.get_warning_text().contains("warm"), "caution text names the cause")
	_check(hud.is_warning_animating(), "caution pulses")

	package.set_instability(9.0)
	_check(hud.get_warning_level() == CRITICAL, "volatile package is CRITICAL")
	_check(hud.get_warning_text().contains("VOLATILE"), "critical text names instability")
	_check((hud.get_node("Panel/Rows/Warning") as Label).visible, "warning line visible")
	_check(levels == [CAUTION, CRITICAL], "warning escalation emitted in order")
	await process_frame
	await process_frame
	_check(hud.is_warning_animating(), "critical animation loops")

	package.set_instability(0.0)
	package.set_temperature(50.0)
	_check(hud.get_warning_level() == NONE, "recovered package clears warning")
	_check(not hud.is_warning_animating(), "warning animation stops")
	_check(not (hud.get_node("Panel/Rows/Warning") as Label).visible, "warning line hidden")
	_check((hud.get_node("Panel") as Control).modulate == Color.WHITE, "panel tint restored")

	hud.unbind_package()
	_check(not hud.visible, "unbinding hides HUD")
	hud.queue_free()
	await process_frame


func _test_hud_polling_and_gates() -> void:
	var hud := _spawn(HUD_SCENE) as PackageStatusHUD
	if hud == null:
		_check(false, "HUD spawns")
		return
	var polled := PolledPackage.new()
	hud.bind_package(polled)
	_check(hud.visible and hud.get_warning_level() == NONE, "polled package shows calm")
	polled.instability = 0.95
	await process_frame
	await process_frame
	_check(hud.get_warning_level() == CRITICAL, "polling picks up property changes")

	hud.bind_package(GatedPackage.new())
	_check(hud.visible, "gated package still shows instability")
	_check(not hud.is_temperature_shown(), "gated temperature row hidden")
	_check(hud.is_instability_shown(), "gated instability row shown")
	_check(hud.get_warning_level() == NONE, "gated temperature never warns")
	hud.queue_free()
	await process_frame
