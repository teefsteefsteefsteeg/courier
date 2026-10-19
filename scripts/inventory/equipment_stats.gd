class_name EquipmentStats
extends Node
## Applies the courier's equipped items to the combat stats the game already has:
## Magic Bolt damage, cooldown and range, and Package Shield durability. Base values are
## read from the player's CombatController once, so unequipping restores them exactly.
## Sets the courier's attack style and melee/arrow stats from the main-hand weapon's type,
## and shows the main-hand and off-hand items' held_model in the courier's hands.
## Lives in GameplayServices; the player is found through CombatController.PLAYER_GROUP.

@export var inventory: CourierInventory
@export var combat: CombatController

var _base := {}
var _character: KayKitCharacter = null
## Main-hand weapon id last applied (&"" = none); null before the first apply.
var _last_weapon: Variant = null


func _ready() -> void:
	_bind.call_deferred()


func _bind() -> void:
	if inventory == null:
		inventory = CourierInventory.find(get_tree())
	if combat == null:
		var body := get_tree().get_first_node_in_group(CombatController.PLAYER_GROUP)
		if body != null:
			for child in body.get_children():
				if child is CombatController:
					combat = child
			var characters := body.find_children("*", "KayKitCharacter", true, false)
			_character = characters[0] as KayKitCharacter if not characters.is_empty() else null
	if inventory == null or combat == null:
		return
	_base = {
		"bolt_damage": combat.bolt_damage,
		"bolt_cooldown": combat.bolt_cooldown,
		"bolt_range": combat.bolt_range,
		"shield_max_durability": combat.shield_max_durability,
	}
	if not inventory.equipment_changed.is_connected(_on_equipment_changed):
		inventory.equipment_changed.connect(_on_equipment_changed)
	apply()


## Recomputes the combat stats from the base values and every equipped item.
func apply() -> void:
	if combat == null or _base.is_empty():
		return
	var damage: float = _base["bolt_damage"]
	var cooldown: float = _base["bolt_cooldown"]
	var bolt_range: float = _base["bolt_range"]
	var shield: float = _base["shield_max_durability"]
	for item in inventory.get_equipped_items():
		damage += item.bolt_damage_bonus
		cooldown *= item.bolt_cooldown_multiplier
		bolt_range += item.bolt_range_bonus
		shield += item.shield_durability_bonus
	combat.bolt_damage = maxf(damage, 1.0)
	combat.bolt_cooldown = maxf(cooldown, 0.05)
	combat.bolt_range = maxf(bolt_range, 1.0)
	combat.shield_max_durability = maxf(shield, 1.0)
	var weapon := inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND)
	var weapon_id: StringName = weapon.item_id if weapon != null else &""
	_apply_attack(weapon)
	if _last_weapon != null and _last_weapon != weapon_id:
		combat.switch_weapon()
	_last_weapon = weapon_id
	if _character != null:
		_character.set_held_item(weapon.held_model if weapon != null else null)
		var off_hand := inventory.get_equipped(ItemDefinition.Slot.OFF_HAND)
		_character.set_off_hand_item(off_hand.held_model if off_hand != null else null)


## Picks the courier's primary attack from the weapon type: a sword swings fast, an axe
## swings heavy, a bow shoots arrows, and a staff or bare hands cast the Magic Bolt.
func _apply_attack(weapon: ItemDefinition) -> void:
	var type := weapon.weapon_type if weapon != null else ItemDefinition.WeaponType.NONE
	match type:
		ItemDefinition.WeaponType.SWORD, ItemDefinition.WeaponType.AXE:
			combat.melee_damage = maxf(weapon.attack_damage, 1.0)
			combat.melee_range = maxf(weapon.attack_range, 0.5)
			combat.melee_cooldown = maxf(weapon.attack_cooldown, 0.05)
			combat.melee_arc_degrees = weapon.attack_arc_degrees
			combat.melee_windup = maxf(weapon.attack_windup, 0.0)
			combat.set_attack_style(CombatController.AttackStyle.HEAVY_MELEE if type == ItemDefinition.WeaponType.AXE else CombatController.AttackStyle.FAST_MELEE)
		ItemDefinition.WeaponType.BOW:
			combat.arrow_damage = maxf(weapon.attack_damage, 1.0)
			combat.arrow_range = maxf(weapon.attack_range, 1.0)
			combat.arrow_cooldown = maxf(weapon.attack_cooldown, 0.05)
			combat.set_attack_style(CombatController.AttackStyle.ARROW)
		_:
			combat.set_attack_style(CombatController.AttackStyle.MAGIC_BOLT)


func get_base_stat(stat: String) -> float:
	return _base.get(stat, 0.0)


func _on_equipment_changed(_slot: ItemDefinition.Slot, _item: ItemDefinition) -> void:
	apply()
