class_name CourierVitals
extends Node
## The courier's HP regeneration, mana (MP), rage and consumable buffs (Phase 8). Lives in
## GameplayServices, so all of it carries across regions with the player.
##
## HP: after hp_regen_delay seconds without taking damage, health regenerates at
## hp_regen_per_second (x combat_regen_factor while in combat: a hit dealt or taken within
## combat_window seconds, or an enemy chasing or attacking the courier). Never above the
## maximum, never while knocked out. Food heals over time on top of it and potions heal at
## once: fast recovery needs them.
## MP: max_mana, regenerates at mana_regen_per_second. A staff's Magic Bolts and its Arcane
## Storm spend it (CombatController.mana_source, WeaponUltimates via the "courier_mana"
## group). Mana potions and some food restore it.
## Rage: built by the primary attack's hits (rage_per_hit, CombatController.basic_hit) and
## by damage taken (rage_per_damage); decays once out of combat for rage_decay_delay
## seconds. A +5 weapon's ultimate costs ULTIMATE_RAGE_COST (WeaponUltimates, "courier_rage").
## Buffs: ConsumableItem buff fields for effect_duration seconds (play time), one per
## buff_id; the courier's CombatController gets the summed damage multiplier, defense bonus
## and critical chance. Consumables are used with consume() (inventory window) or the five
## consumable quick slots (keys 6-0, use_slot()).
## Saved by SaveGame ("vitals": health, mana, rage, buffs and heals in progress).
## Development mode (DevMode: a debug build with a window; never headless tests) gives
## unlimited rage: the bar stays full and ultimates never spend it (unlimited_rage).

signal mana_changed(current: float, maximum: float)
signal rage_changed(current: float, maximum: float)
signal buffs_changed
## A consumable was used (effects applied, one taken from the stack).
signal consumed(item: ConsumableItem)
## reason: &"none_left", &"dead", &"cooldown", &"full", &"busy", &"unknown"
signal consume_refused(item: ConsumableItem, reason: StringName)

const GROUP := &"courier_vitals"
const MANA_GROUP := &"courier_mana"
const RAGE_GROUP := &"courier_rage"
## Rage a +5 weapon's ultimate costs.
const ULTIMATE_RAGE_COST := 50.0
## Seconds between two potions (food has no cooldown).
const POTION_COOLDOWN := 1.5
const SLOT_ACTIONS: Array[StringName] = [&"consumable_slot_1", &"consumable_slot_2", &"consumable_slot_3", &"consumable_slot_4", &"consumable_slot_5"]

@export var inventory: CourierInventory
## Step timers every frame (tests turn it off and call advance()).
@export var simulate: bool = true

@export_group("Health")
@export_range(0.0, 50.0, 0.1, "suffix:HP/s") var hp_regen_per_second: float = 1.5
## Seconds after the last damage before natural regeneration starts.
@export_range(0.0, 60.0, 0.1, "suffix:s") var hp_regen_delay: float = 6.0
## Natural regeneration while in combat (0 = paused).
@export_range(0.0, 1.0, 0.05) var combat_regen_factor: float = 0.25
## Seconds after the last hit dealt or taken that still count as combat.
@export_range(0.0, 30.0, 0.5, "suffix:s") var combat_window: float = 5.0

@export_group("Mana")
@export var max_mana: float = 100.0
@export_range(0.0, 50.0, 0.1, "suffix:MP/s") var mana_regen_per_second: float = 2.5

@export_group("Rage")
@export var max_rage: float = 100.0
@export var rage_per_hit: float = 8.0
## Rage per point of damage taken.
@export var rage_per_damage: float = 0.5
@export_range(0.0, 60.0, 0.5, "suffix:s") var rage_decay_delay: float = 8.0
@export_range(0.0, 50.0, 0.5, "suffix:/s") var rage_decay_per_second: float = 4.0

var combat: CombatController = null
var health: CombatHealth = null
var mana: float = -1.0
var rage: float = 0.0
## Active buffs: {"id", "name", "remaining", "item": ConsumableItem}.
var buffs: Array[Dictionary] = []
## Heals in progress: {"per_second", "remaining"}.
var heals: Array[Dictionary] = []
var potion_cooldown_left: float = 0.0
## Seconds since the courier last took damage / since the last hit dealt or taken.
var since_damage: float = 999.0
var since_combat: float = 999.0
var _player: PlayerController = null
## Rage never runs out (development mode by default; tests can set it).
var unlimited_rage: bool = false


static func find(tree: SceneTree) -> CourierVitals:
	return tree.get_first_node_in_group(GROUP) as CourierVitals if tree != null else null


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group(MANA_GROUP)
	add_to_group(RAGE_GROUP)
	if mana < 0.0:
		mana = max_mana
	unlimited_rage = DevMode.is_enabled()
	if unlimited_rage:
		rage = max_rage


func _process(delta: float) -> void:
	_bind()
	if simulate:
		advance(delta)


func _unhandled_input(event: InputEvent) -> void:
	for index in SLOT_ACTIONS.size():
		if InputMap.has_action(SLOT_ACTIONS[index]) and event.is_action_pressed(SLOT_ACTIONS[index]):
			if _player != null and not _player.input_enabled:
				return
			use_slot(index)
			get_viewport().set_input_as_handled()
			return


## Finds the courier (and binds to a new one after a scene change).
func _bind() -> void:
	if combat != null and is_instance_valid(combat):
		return
	if inventory == null:
		inventory = CourierInventory.find(get_tree())
	var body := get_tree().get_first_node_in_group(CombatController.PLAYER_GROUP)
	combat = CombatController.find_on(body) if body != null else null
	if combat == null:
		return
	_player = body as PlayerController
	health = combat.health
	combat.mana_source = self
	combat.basic_hit.connect(_on_basic_hit)
	combat.target_hit.connect(func(_t: Node, _a: float) -> void: since_combat = 0.0)
	if health != null:
		health.damaged.connect(_on_damaged)
	_apply_buffs()


## Steps regeneration, heals, rage decay and buffs by delta seconds.
func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	since_damage += delta
	since_combat += delta
	potion_cooldown_left = maxf(potion_cooldown_left - delta, 0.0)
	_step_buffs(delta)
	var dead := health == null or health.is_dead()
	if not dead:
		var rate := get_hp_regen_rate()
		for i in range(heals.size() - 1, -1, -1):
			var step := minf(delta, float(heals[i]["remaining"]))
			rate += float(heals[i]["per_second"]) * step / delta
			heals[i]["remaining"] = float(heals[i]["remaining"]) - step
			if float(heals[i]["remaining"]) <= 0.0:
				heals.remove_at(i)
		if rate > 0.0 and health.get_health() < health.get_max_health():
			health.heal(rate * delta)
	else:
		heals.clear()
	var mana_rate := mana_regen_per_second + _buff_sum(&"mp_regen_bonus")
	if mana < max_mana and mana_rate > 0.0 and not dead:
		_set_mana(mana + mana_rate * delta)
	if rage > 0.0 and since_combat >= rage_decay_delay:
		_set_rage(rage - rage_decay_per_second * delta)


## Natural HP regeneration per second right now (0 while waiting after damage); food
## buffs add their regeneration even then.
func get_hp_regen_rate() -> float:
	var bonus := _buff_sum(&"hp_regen_bonus")
	if since_damage < hp_regen_delay:
		return bonus
	return hp_regen_per_second * (combat_regen_factor if is_in_combat() else 1.0) + bonus


## A hit dealt or taken recently, or an enemy chasing / attacking the courier.
func is_in_combat() -> bool:
	if since_combat < combat_window:
		return true
	if not is_inside_tree() or combat == null:
		return false
	var body := combat.get_parent() as Node3D
	for node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead() or enemy.state == Enemy.State.IDLE or enemy.find_target() != body:
			continue
		if body != null and enemy.horizontal_distance_to(body) <= enemy.lose_interest_radius:
			return true
	return false


# --- mana ------------------------------------------------------------------------

## Pays amount MP. False (nothing spent) when there is not enough.
func spend(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if mana + 0.0001 < amount:
		return false
	_set_mana(mana - amount)
	return true


func restore_mana(amount: float) -> float:
	var before := mana
	_set_mana(mana + amount)
	return mana - before


func get_mana() -> float:
	return mana


func _set_mana(value: float) -> void:
	var clamped := clampf(value, 0.0, max_mana)
	if is_equal_approx(clamped, mana):
		mana = clamped
		return
	mana = clamped
	mana_changed.emit(mana, max_mana)


# --- rage ------------------------------------------------------------------------

func add_rage(amount: float) -> void:
	if amount > 0.0:
		_set_rage(rage + amount)


## Pays amount rage. False (nothing spent) when there is not enough.
func spend_rage(amount: float) -> bool:
	if unlimited_rage:
		return true
	if rage + 0.0001 < amount:
		return false
	_set_rage(rage - amount)
	return true


func has_rage(amount: float) -> bool:
	return unlimited_rage or rage + 0.0001 >= amount


func get_rage() -> float:
	return rage


func _set_rage(value: float) -> void:
	var clamped := max_rage if unlimited_rage else clampf(value, 0.0, max_rage)
	if is_equal_approx(clamped, rage):
		rage = clamped
		return
	rage = clamped
	rage_changed.emit(rage, max_rage)


func _on_basic_hit(_target: Node, _amount: float) -> void:
	since_combat = 0.0
	add_rage(rage_per_hit * _buff_product(&"rage_gain_multiplier"))


func _on_damaged(amount: float, _source: Vector3) -> void:
	since_damage = 0.0
	since_combat = 0.0
	add_rage(amount * rage_per_damage)


# --- consumables --------------------------------------------------------------------

## Uses one of a carried consumable. Returns whether it was used.
func consume(material_id: StringName) -> bool:
	var item := inventory.get_material_definition(material_id) as ConsumableItem if inventory != null else null
	if item == null:
		consume_refused.emit(null, &"unknown")
		return false
	var reason := _refusal(item)
	if reason != &"":
		consume_refused.emit(item, reason)
		_notify(_refusal_text(item, reason), QuestNotification.KIND_WARNING)
		return false
	inventory.remove_materials({material_id: 1})
	if item.is_potion():
		potion_cooldown_left = POTION_COOLDOWN
	if item.heal > 0.0:
		health.heal(item.heal)
	if item.heal_over_time > 0.0 and item.effect_duration > 0.0:
		heals.append({"per_second": item.heal_over_time / item.effect_duration, "remaining": item.effect_duration})
	if item.mana > 0.0:
		restore_mana(item.mana)
	if item.rage > 0.0:
		add_rage(item.rage)
	if item.has_buff():
		_add_buff(item, item.effect_duration)
	consumed.emit(item)
	_notify("%s: %s" % [item.display_name, ", ".join(item.get_effect_lines())], QuestNotification.KIND_SUCCESS)
	return true


## Uses the consumable in quick slot index (0-based, keys 6-0).
func use_slot(index: int) -> bool:
	var item := inventory.get_consumable_slot(index) if inventory != null else null
	if item == null:
		_notify("Consumable slot [%s] is empty. Put food or a potion on it in the inventory." % InputHints.key_for(SLOT_ACTIONS[index]), QuestNotification.KIND_INFO)
		return false
	return consume(item.material_id)


## Why item can't be used now (&"" when it can).
func _refusal(item: ConsumableItem) -> StringName:
	if inventory.get_material_count(item.material_id) <= 0:
		return &"none_left"
	if health == null or health.is_dead():
		return &"dead"
	if _player != null and not _player.input_enabled and _player.is_inside_tree() and get_tree().get_node_count_in_group(QuestJournal.MODAL_GROUP) == 0:
		return &"busy"
	if item.is_potion() and potion_cooldown_left > 0.0:
		return &"cooldown"
	# A potion that only restores something already full would be wasted.
	var wants_health := item.heal > 0.0 or item.heal_over_time > 0.0
	var health_full := health.get_health() >= health.get_max_health()
	var mana_full := mana >= max_mana
	if item.is_potion() and not item.has_buff() and item.rage <= 0.0:
		if (not wants_health or health_full) and (item.mana <= 0.0 or mana_full):
			return &"full"
	return &""


func _refusal_text(item: ConsumableItem, reason: StringName) -> String:
	match reason:
		&"none_left":
			return "No %s left." % item.display_name
		&"cooldown":
			return "Wait a moment before the next potion."
		&"full":
			return "No need: you're already at full %s." % ("mana" if item.kind == MaterialItem.Kind.MANA_POTION else "health")
		&"dead":
			return "Not while knocked out."
	return "Not now."


# --- buffs ------------------------------------------------------------------------------

func _add_buff(item: ConsumableItem, seconds: float) -> void:
	for buff in buffs:
		if buff["id"] == item.buff_id:
			buff["remaining"] = seconds
			buff["item"] = item
			buff["name"] = item.buff_name
			_apply_buffs()
			return
	buffs.append({"id": item.buff_id, "name": item.buff_name if not item.buff_name.is_empty() else item.display_name, "remaining": seconds, "item": item})
	_apply_buffs()


func has_buff(buff_id: StringName) -> bool:
	return buffs.any(func(b: Dictionary) -> bool: return b["id"] == buff_id)


func get_buff_remaining(buff_id: StringName) -> float:
	for buff in buffs:
		if buff["id"] == buff_id:
			return float(buff["remaining"])
	return 0.0


func _step_buffs(delta: float) -> void:
	var expired := false
	for i in range(buffs.size() - 1, -1, -1):
		buffs[i]["remaining"] = float(buffs[i]["remaining"]) - delta
		if float(buffs[i]["remaining"]) <= 0.0:
			_notify("%s wore off." % buffs[i]["name"], QuestNotification.KIND_INFO)
			buffs.remove_at(i)
			expired = true
	if expired:
		_apply_buffs()


## Pushes the summed buff effects to the courier's CombatController.
func _apply_buffs() -> void:
	if combat != null and is_instance_valid(combat):
		combat.damage_multiplier = _buff_product(&"damage_multiplier")
		combat.defense_bonus = _buff_sum(&"defense_bonus")
		combat.crit_chance = clampf(_buff_sum(&"crit_chance"), 0.0, 1.0)
	buffs_changed.emit()


func _buff_sum(property: StringName) -> float:
	var total := 0.0
	for buff in buffs:
		total += float((buff["item"] as ConsumableItem).get(property))
	return total


func _buff_product(property: StringName) -> float:
	var total := 1.0
	for buff in buffs:
		total *= float((buff["item"] as ConsumableItem).get(property))
	return total


# --- save -----------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"health": health.get_health() if health != null and not health.is_dead() else -1.0,
		"mana": mana,
		"rage": rage,
		"buffs": buffs.map(func(b: Dictionary) -> Dictionary: return {"item": String((b["item"] as ConsumableItem).material_id), "remaining": b["remaining"]}),
		"heals": heals.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	_bind()
	_set_mana(float(data.get("mana", max_mana)))
	_set_rage(float(data.get("rage", 0.0)))
	buffs.clear()
	for saved in data.get("buffs", []):
		var item := inventory.get_material_definition(StringName(saved.get("item", ""))) as ConsumableItem if inventory != null else null
		if item != null and item.has_buff() and float(saved.get("remaining", 0.0)) > 0.0:
			buffs.append({"id": item.buff_id, "name": item.buff_name if not item.buff_name.is_empty() else item.display_name, "remaining": float(saved["remaining"]), "item": item})
	heals.clear()
	for saved in data.get("heals", []):
		if saved is Dictionary and float(saved.get("remaining", 0.0)) > 0.0:
			heals.append({"per_second": float(saved.get("per_second", 0.0)), "remaining": float(saved["remaining"])})
	var saved_health := float(data.get("health", -1.0))
	if health != null and saved_health > 0.0:
		health.set_health(saved_health)
	_apply_buffs()


func _notify(text: String, kind: StringName) -> void:
	if not is_inside_tree():
		return
	var notices := get_tree().root.find_children("*", "QuestNotification", true, false)
	if not notices.is_empty():
		(notices[0] as QuestNotification).push_message(text, kind)
