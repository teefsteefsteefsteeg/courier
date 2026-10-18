extends SceneTree
## Phase 3 automated checks (package mechanics: ordinary, dragon egg temperature,
## potion instability, condition/quality, reward multipliers, carrier integration).
##   godot --headless --path . --script res://tests/phase3_tests.gd
## Exit code = number of failed checks. Run tests/phase2_tests.gd for Phase 2 regression.
## All mechanics are driven with explicit fixed deltas, so results are deterministic.

const PARCEL := "res://data/packages/pkg_ordinary_parcel.tres"
const EGG := "res://data/packages/pkg_dragon_egg.tres"
const POTION := "res://data/packages/pkg_potion_crate.tres"
const C := PackageInstance.Condition
const T := PackageInstance.TemperatureState

var _failures: int = 0
var _passes: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_data()
	_test_phase2_compatibility()
	_test_ordinary()
	_test_egg_cooling()
	_test_egg_warming_and_overheat()
	_test_potion_instability()
	_test_potion_impacts()
	_test_destruction_signals()
	_test_conditions()
	_test_rewards()
	_test_determinism()
	await _test_carrier_integration()

	print("\n=== Phase 3 tests: %d passed, %d failed ===" % [_passes, _failures])
	quit(_failures)


# --- helpers -------------------------------------------------------------------

func _check(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)


func _new(path: String) -> PackageInstance:
	return PackageInstance.new(load(path))


func _ticks(package: PackageInstance, count: int, delta: float, speed: float, ambient: float) -> void:
	for i in count:
		package.tick(delta, speed, ambient)


# --- tests ---------------------------------------------------------------------

func _test_data() -> void:
	print("[Data]")
	var parcel: PackageDefinition = load(PARCEL)
	var egg: PackageDefinition = load(EGG)
	var potion: PackageDefinition = load(POTION)
	_check(parcel.behavior == PackageDefinition.Behavior.ORDINARY, "parcel is ORDINARY")
	_check(egg.behavior == PackageDefinition.Behavior.TEMPERATURE, "dragon egg is TEMPERATURE")
	_check(potion.behavior == PackageDefinition.Behavior.INSTABILITY, "potion crate is INSTABILITY")
	_check(is_equal_approx(egg.starting_temperature, 60.0) and is_equal_approx(egg.ideal_temperature_min, 45.0) and is_equal_approx(egg.ideal_temperature_max, 75.0), "egg temperature tuning 60 in [45, 75]")
	_check(is_equal_approx(potion.instability_safe_speed, 3.0) and is_equal_approx(potion.instability_damage_threshold, 60.0), "potion instability tuning")


func _test_phase2_compatibility() -> void:
	print("[Phase 2 API compatibility]")
	var p := _new(PARCEL)
	_check(p.get_package_id() == &"pkg_ordinary_parcel" and p.get_quest_id() == &"q001_first_delivery" and p.get_recipient_id() == &"village_merchant", "id getters unchanged")
	_check(is_equal_approx(p.integrity, 100.0), "integrity starts at definition value")
	var events := []
	p.integrity_changed.connect(func(n, o): events.append([n, o]))
	p.set_integrity(80.0)
	_check(events.size() == 1 and is_equal_approx(events[0][0], 80.0) and is_equal_approx(events[0][1], 100.0), "integrity_changed(new, old) emitted")
	p.set_integrity(80.0)
	_check(events.size() == 1, "no signal when value unchanged")
	p.set_integrity(150.0)
	_check(is_equal_approx(p.integrity, 100.0), "integrity clamped to definition maximum")
	_check(not p.is_destroyed(), "partial damage does not destroy")
	var shared: PackageDefinition = load(PARCEL)
	_check(is_equal_approx(shared.integrity, 100.0), "shared definition untouched by instance")


func _test_ordinary() -> void:
	print("[Ordinary parcel]")
	var p := _new(PARCEL)
	_ticks(p, 100, 1.0, 50.0, 200.0)
	_check(is_equal_approx(p.integrity, 100.0) and is_equal_approx(p.instability, 0.0), "no passive change from time, speed or heat")
	_check(p.get_temperature_state() == T.NOT_APPLICABLE and p.is_temperature_safe(), "temperature not applicable")
	_check(not p.uses_temperature() and not p.uses_instability(), "no special mechanic flags")
	p.apply_impact(15.0)
	_check(is_equal_approx(p.integrity, 85.0), "impact 15 -> 85 integrity")
	p.apply_impact(-5.0)
	_check(is_equal_approx(p.integrity, 85.0), "negative impact ignored")
	p.add_instability(500.0)
	_check(not p.is_destroyed(), "instability never explodes an ordinary parcel")


func _test_egg_cooling() -> void:
	print("[Dragon egg: cooling]")
	var egg := _new(EGG)
	_check(egg.uses_temperature() and is_equal_approx(egg.get_temperature(), 60.0) and egg.get_temperature_state() == T.SAFE, "egg starts warm (60) and SAFE")
	var temp_events := [0]
	egg.temperature_changed.connect(func(_n, _o): temp_events[0] += 1)
	_ticks(egg, 30, 1.0, 0.0, 20.0)
	_check(is_equal_approx(egg.temperature, 45.0) and is_equal_approx(egg.integrity, 100.0), "30 s at 20 degrees: 45, no damage (band inclusive)")
	_check(temp_events[0] == 30, "temperature_changed each tick")
	_ticks(egg, 10, 1.0, 0.0, 20.0)
	_check(is_equal_approx(egg.temperature, 40.0) and egg.get_temperature_state() == T.TOO_COLD, "40 s: 40 degrees, TOO_COLD")
	_check(is_equal_approx(egg.integrity, 80.0), "10 cold seconds cost 20 integrity (got %.2f)" % egg.integrity)
	_check(egg.get_condition() == C.GOOD, "condition GOOD at 80%")
	_ticks(egg, 10, 1.0, 0.0, 60.0)
	_check(is_equal_approx(egg.temperature, 45.0) and egg.is_temperature_safe(), "warming 10 s: back to 45, SAFE")
	_check(is_equal_approx(egg.integrity, 62.0), "9 cold ticks while warming cost 18 (got %.2f)" % egg.integrity)
	_ticks(egg, 100, 1.0, 0.0, 60.0)
	_check(is_equal_approx(egg.temperature, 60.0) and is_equal_approx(egg.integrity, 62.0), "settles at ambient without overshoot or damage")


func _test_egg_warming_and_overheat() -> void:
	print("[Dragon egg: overheating]")
	var egg := _new(EGG)
	_ticks(egg, 30, 1.0, 0.0, 100.0)
	_check(is_equal_approx(egg.temperature, 75.0) and is_equal_approx(egg.integrity, 100.0), "heats to 75, still SAFE")
	_ticks(egg, 5, 1.0, 0.0, 100.0)
	_check(egg.get_temperature_state() == T.TOO_HOT and is_equal_approx(egg.integrity, 90.0), "5 hot seconds: TOO_HOT, 90 integrity")
	_ticks(egg, 100, 1.0, 0.0, 100.0)
	_check(egg.is_destroyed() and egg.get_destroyed_reason() == PackageInstance.REASON_RUINED, "prolonged heat ruins the egg")
	_check(egg.get_destroyed_message() == "The Dragon Egg was ruined.", "ruined message")
	var t := egg.temperature
	egg.tick(1.0, 0.0, 100.0)
	_check(is_equal_approx(egg.temperature, t), "destroyed egg no longer simulated")
	var fragile := _new(EGG)
	fragile.apply_impact(6.0)
	_check(is_equal_approx(fragile.integrity, 88.0), "egg impact sensitivity 2x (6 -> 88)")
	_check(is_equal_approx((load(EGG) as PackageDefinition).starting_temperature, 60.0), "shared egg definition untouched")


func _test_potion_instability() -> void:
	print("[Potion crate: instability]")
	var crate := _new(POTION)
	_ticks(crate, 100, 1.0, 2.0, 20.0)
	_check(is_equal_approx(crate.instability, 0.0) and is_equal_approx(crate.integrity, 100.0), "walking below safe speed stays stable")
	_ticks(crate, 5, 1.0, 5.0, 20.0)
	_check(is_equal_approx(crate.instability, 50.0) and is_equal_approx(crate.integrity, 100.0), "5 s at 5 m/s: instability 50, no damage yet")
	_check(is_equal_approx(crate.get_instability_ratio(), 0.5), "instability ratio 0.5")
	_ticks(crate, 5, 1.0, 0.0, 20.0)
	_check(is_equal_approx(crate.instability, 30.0), "5 s at rest recovers to 30")
	_ticks(crate, 6, 1.0, 5.0, 20.0)
	_check(is_equal_approx(crate.instability, 90.0) and is_equal_approx(crate.integrity, 80.0), "6 s fast: 90 instability, 4 ticks over threshold cost 20 (got %.2f)" % crate.integrity)
	_check(not crate.is_destroyed(), "not exploded below 100")
	var reasons := []
	crate.destroyed.connect(func(r): reasons.append(r))
	crate.tick(1.0, 5.0, 20.0)
	_check(crate.is_destroyed() and reasons == [PackageInstance.REASON_EXPLODED], "explodes at 100 instability")
	_check(is_equal_approx(crate.integrity, 0.0) and crate.get_condition() == C.DESTROYED, "explosion zeroes integrity -> DESTROYED")
	_check(crate.get_destroyed_message() == "The Unstable Potion Crate exploded!", "exploded message")
	crate.tick(1.0, 0.0, 20.0)
	crate.set_instability(0.0)
	_check(is_equal_approx(crate.instability, 100.0) and reasons.size() == 1, "destroyed crate frozen; destroyed emitted once")


func _test_potion_impacts() -> void:
	print("[Potion crate: impacts]")
	var crate := _new(POTION)
	crate.apply_impact(2.0)
	_check(is_equal_approx(crate.instability, 20.0) and is_equal_approx(crate.integrity, 99.0), "impact 2: +20 instability, -1 integrity")
	crate.apply_impact(8.0)
	_check(crate.is_destroyed() and crate.get_destroyed_reason() == PackageInstance.REASON_EXPLODED, "big impact explodes the crate")


func _test_destruction_signals() -> void:
	print("[Destruction signals]")
	var p := _new(PARCEL)
	var events := []
	p.integrity_changed.connect(func(n, _o): events.append("integrity:%d" % n))
	p.condition_changed.connect(func(n, _o): events.append("condition:%s" % PackageInstance.condition_name(n)))
	p.destroyed.connect(func(r): events.append("destroyed:%s" % r))
	p.set_integrity(0.0)
	_check(events == ["integrity:0", "condition:Destroyed", "destroyed:ruined"], "signal order %s" % [events])
	p.set_integrity(0.0)
	p.apply_impact(10.0)
	_check(events.size() == 3, "no repeat destruction signals")
	_check(p.get_quality() == 0.0 and p.get_reward_multiplier() == 0.0, "destroyed: quality 0, multiplier 0")


func _test_conditions() -> void:
	print("[Condition / quality]")
	_check(PackageInstance.condition_for_ratio(1.0) == C.PRISTINE and PackageInstance.condition_for_ratio(0.9) == C.PRISTINE, "PRISTINE >= 0.9")
	_check(PackageInstance.condition_for_ratio(0.89) == C.GOOD and PackageInstance.condition_for_ratio(0.6) == C.GOOD, "GOOD 0.6..0.9")
	_check(PackageInstance.condition_for_ratio(0.59) == C.DAMAGED and PackageInstance.condition_for_ratio(0.25) == C.DAMAGED, "DAMAGED 0.25..0.6")
	_check(PackageInstance.condition_for_ratio(0.24) == C.RUINED and PackageInstance.condition_for_ratio(0.0) == C.RUINED, "RUINED < 0.25")
	var p := _new(PARCEL)
	var changes := []
	p.condition_changed.connect(func(n, o): changes.append([n, o]))
	_check(p.get_condition() == C.PRISTINE and p.get_condition_name() == "Pristine", "fresh parcel Pristine")
	p.set_integrity(95.0)
	_check(changes.is_empty(), "no condition signal within the same band")
	p.set_integrity(70.0)
	_check(changes == [[C.GOOD, C.PRISTINE]], "condition_changed(GOOD, PRISTINE)")
	p.set_integrity(30.0)
	_check(p.get_condition() == C.DAMAGED and is_equal_approx(p.get_quality(), 0.3), "Damaged at 30%, quality 0.3")
	p.set_integrity(10.0)
	_check(p.get_condition_name() == "Ruined", "Ruined at 10%")
	p.set_integrity(100.0)
	_check(p.get_condition() == C.PRISTINE and changes.size() == 4, "repair returns to Pristine")


func _test_rewards() -> void:
	print("[Reward multiplier]")
	var reward := QuestReward.new()
	reward.gold = 120
	reward.reputation = 20
	var expected := [[100.0, 1.0, 120, 20], [80.0, 0.8, 96, 16], [50.0, 0.5, 60, 10], [10.0, 0.2, 24, 4]]
	for e in expected:
		var p := _new(PARCEL)
		p.set_integrity(e[0])
		var adjusted := p.get_adjusted_reward(reward)
		_check(is_equal_approx(p.get_reward_multiplier(), e[1]) and adjusted.gold == e[2] and adjusted.reputation == e[3], "integrity %d -> x%.1f = %d Gold / %d Rep (got %d / %d)" % [e[0], e[1], e[2], e[3], adjusted.gold, adjusted.reputation])
	_check(reward.gold == 120 and reward.reputation == 20, "original reward not modified")
	var broken := _new(POTION)
	broken.apply_impact(10.0)
	var zero := broken.get_adjusted_reward(reward)
	_check(zero.gold == 0 and zero.reputation == 0, "destroyed package pays nothing")
	var penalty := QuestReward.new()
	penalty.gold = 50
	penalty.reputation = -10
	var good := _new(PARCEL)
	good.set_integrity(80.0)
	var scaled := good.get_adjusted_reward(penalty)
	_check(scaled.gold == 40 and scaled.reputation == -10, "negative reputation not reduced")
	_check(good.get_adjusted_reward(null) == null, "null reward -> null")
	_check(good.apply_reward_multiplier(25) == 20, "apply_reward_multiplier(25) at x0.8 = 20")


func _test_determinism() -> void:
	print("[Determinism]")
	var a := _new(EGG)
	var b := _new(EGG)
	var c := _new(POTION)
	var d := _new(POTION)
	for i in 3000:
		var ambient := 10.0 if posmod(i, 1200) < 600 else 90.0
		var speed := float(i % 7)
		for pair in [[a, b], [c, d]]:
			pair[0].tick(1.0 / 60.0, speed, ambient)
			pair[1].tick(1.0 / 60.0, speed, ambient)
		if i % 450 == 0:
			c.apply_impact(1.5)
			d.apply_impact(1.5)
	_check(a.temperature == b.temperature and a.integrity == b.integrity and a.is_destroyed() == b.is_destroyed(), "identical egg runs give identical state (%.4f / %.4f)" % [a.temperature, a.integrity])
	_check(c.instability == d.instability and c.integrity == d.integrity and c.is_destroyed() == d.is_destroyed(), "identical crate runs give identical state (%.4f / %.4f)" % [c.instability, c.integrity])


func _test_carrier_integration() -> void:
	print("[PackageCarrier integration]")
	var carrier := PackageCarrier.new()
	carrier.simulate_mechanics = false
	root.add_child(carrier)
	await process_frame
	var crate := _new(POTION)
	_check(carrier.pick_up(crate), "carrier picks up crate")
	carrier.advance_package(1.0)
	_check(is_equal_approx(crate.instability, 0.0), "first tick after pickup counts as standing still")
	carrier.position = Vector3(5.0, 0.0, 0.0)
	carrier.advance_package(1.0)
	_check(is_equal_approx(crate.instability, 10.0), "moving 5 m in 1 s -> +10 instability (got %.2f)" % crate.instability)
	carrier.position = Vector3(105.0, 0.0, 0.0)
	carrier.advance_package(1.0)
	_check(is_equal_approx(crate.instability, 6.0), "teleport ignored (treated as rest, got %.2f)" % crate.instability)

	var removed := []
	carrier.package_removed.connect(func(p, r): removed.append([p, r]))
	crate.add_instability(100.0)
	_check(not carrier.is_carrying() and removed.size() == 1 and removed[0][0] == crate and removed[0][1] == &"destroyed", "exploded package removed with reason destroyed")
	_check(not crate.destroyed.is_connected(carrier._on_package_destroyed), "carrier disconnected from removed package")

	var egg := _new(EGG)
	carrier.ambient_temperature = 20.0
	carrier.pick_up(egg)
	for i in 10:
		carrier.advance_package(1.0)
	_check(is_equal_approx(egg.temperature, 55.0), "carried egg cools toward carrier ambient (got %.2f)" % egg.temperature)
	carrier.drop_impact_force = 5.0
	carrier.drop_package()
	_check(not carrier.is_carrying() and is_equal_approx(egg.integrity, 90.0), "drop impact 5 costs the egg 10 integrity")
	var parcel := _new(PARCEL)
	carrier.drop_impact_force = 0.0
	carrier.pick_up(parcel)
	carrier.drop_package()
	_check(is_equal_approx(parcel.integrity, 100.0), "default drop impact is harmless")
	carrier.queue_free()
	await process_frame
