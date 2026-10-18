extends SceneTree
## Equipped weapons are visible: every Armory item has a held model, equipping puts it
## in the right bone slot (weapons: right hand, shield: left hand), switching replaces
## it, unequipping removes it, and a save round trip, attacks and the combat stats keep
## working. Regression for "purchased weapon not visible in the hand": the Battle Axe and
## the Wooden Shield had no held_model, so equipping the axe emptied the hand.
## Run headless from the project root:
##   godot --headless --path . --script res://tests/equipment_visual_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"
const CATALOG := "res://data/shops/armory.tres"
const KAYKIT_WEAPONS := "res://assets/models/kaykit_weapons/"

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var inventory: CourierInventory
var equipment: EquipmentStats
var combat: CombatController
var character: KayKitCharacter
var catalog: ShopCatalog


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	catalog = load(CATALOG) as ShopCatalog
	_test_data()
	level = (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(level)
	player = level.get_node("Player")
	await _frames(10)
	inventory = CourierInventory.find(self)
	equipment = level.find_children("*", "EquipmentStats", true, false)[0] as EquipmentStats
	combat = player.find_children("*", "CombatController", true, false)[0] as CombatController
	character = player.find_children("*", "KayKitCharacter", true, false)[0] as KayKitCharacter
	for item in catalog.items:
		inventory.add_item(item)
	await _test_each_item()
	await _test_switch_and_unequip()
	await _test_save_round_trip()
	await _test_attack_keeps_weapon()
	_test_npc_props()
	print("\n=== Equipment visual tests: %d passed, %d failed ===" % [_passes, _failures])
	quit(_failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame


# --- tests -------------------------------------------------------------------

func _test_data() -> void:
	print("[Every Armory item has a held model]")
	for item in catalog.items:
		_check(item.held_model != null, "%s has a held_model" % item.display_name)
	var models := {}
	for item_id in [&"wooden_sword", &"iron_sword", &"steel_sword", &"battle_axe"]:
		var item := catalog.get_item(item_id)
		models[item.held_model.resource_path if item.held_model else ""] = true
	_check(models.size() == 4, "the three swords and the axe each look different (%d models)" % models.size())
	for item_id in [&"battle_axe", &"wooden_shield"]:
		var item := catalog.get_item(item_id)
		_check(item.held_model != null and item.held_model.resource_path.begins_with(KAYKIT_WEAPONS), "%s reuses a KayKit weapon model" % item.display_name)


func _test_each_item() -> void:
	print("[Equipping shows the model in the hand]")
	for item in catalog.items:
		_unequip_all()
		await _frames(1)
		inventory.equip(item.item_id)
		await _frames(2)
		var main := item.slot == ItemDefinition.Slot.MAIN_HAND
		var held := character.get_held_item_node() if main else character.get_off_hand_item_node()
		var other := character.get_off_hand_item_node() if main else character.get_held_item_node()
		_check(_shows(held, item, "handslot.r" if main else "handslot.l"), "%s appears in the %s hand" % [item.display_name, "right" if main else "left"])
		_check(other == null, "%s leaves the other hand empty" % item.display_name)


func _test_switch_and_unequip() -> void:
	print("[Switching and unequipping]")
	_unequip_all()
	inventory.equip(&"iron_sword")
	await _frames(1)
	inventory.equip(&"battle_axe")
	await _frames(2)
	var slot := character.skeleton.get_node(^"RightHandSlot")
	_check(slot.get_child_count() == 1 and _shows(character.get_held_item_node(), catalog.get_item(&"battle_axe"), "handslot.r"),
			"switching the sword for the axe replaces the model (regression: the axe emptied the hand)")
	inventory.equip(&"steel_sword")
	await _frames(2)
	_check(slot.get_child_count() == 1 and _shows(character.get_held_item_node(), catalog.get_item(&"steel_sword"), "handslot.r"), "switching to the steel sword updates the model")
	inventory.equip(&"wooden_shield")
	await _frames(2)
	_check(_shows(character.get_held_item_node(), catalog.get_item(&"steel_sword"), "handslot.r") and _shows(character.get_off_hand_item_node(), catalog.get_item(&"wooden_shield"), "handslot.l"),
			"sword and shield shown together")
	inventory.unequip(ItemDefinition.Slot.MAIN_HAND)
	await _frames(2)
	_check(character.get_held_item_node() == null and character.get_off_hand_item_node() != null, "unequipping the weapon removes it and keeps the shield")
	inventory.unequip(ItemDefinition.Slot.OFF_HAND)
	await _frames(2)
	_check(character.get_off_hand_item_node() == null, "unequipping the shield removes it")


func _test_save_round_trip() -> void:
	print("[Save round trip]")
	_unequip_all()
	inventory.equip(&"battle_axe")
	inventory.equip(&"wooden_shield")
	var data := inventory.to_dict()
	_unequip_all()
	await _frames(2)
	inventory.from_dict(data)
	await _frames(2)
	_check(_shows(character.get_held_item_node(), catalog.get_item(&"battle_axe"), "handslot.r") and _shows(character.get_off_hand_item_node(), catalog.get_item(&"wooden_shield"), "handslot.l"),
			"a loaded save shows the equipped axe and shield")
	var axe := catalog.get_item(&"battle_axe")
	_check(is_equal_approx(combat.bolt_damage, equipment.get_base_stat("bolt_damage") + axe.bolt_damage_bonus), "loaded axe still sets the bolt damage (%.1f)" % combat.bolt_damage)


func _test_attack_keeps_weapon() -> void:
	print("[Attacking keeps the weapon]")
	var held := character.get_held_item_node()
	character.play_once(&"attack")
	await _frames(5)
	_check(character.get_held_item_node() == held and held != null and held.is_visible_in_tree(), "the attack animation keeps the axe in hand")
	_check(combat.try_magic_bolt(Vector3.RIGHT), "a bolt can still be cast with the axe equipped")


func _test_npc_props() -> void:
	print("[NPC props unchanged]")
	var pip := level.get_node("NPCs/VillagerPip")
	var pip_character := pip.find_children("*", "KayKitCharacter", true, false)[0] as KayKitCharacter
	_check(pip_character.get_held_item_node() != null and pip_character.get_off_hand_item_node() == null, "Pip still holds his sword, left hand empty")


# --- helpers -------------------------------------------------------------------

func _unequip_all() -> void:
	for slot in [ItemDefinition.Slot.MAIN_HAND, ItemDefinition.Slot.OFF_HAND]:
		inventory.unequip(slot)


## True if held is the item's model, visible, on the right bone and near the courier.
func _shows(held: Node3D, item: ItemDefinition, bone: String) -> bool:
	if held == null or item.held_model == null:
		return false
	var slot := held.get_parent() as BoneAttachment3D
	var meshes := held.find_children("*", "MeshInstance3D", true, false)
	return held.scene_file_path == item.held_model.resource_path and held.is_visible_in_tree() \
			and slot != null and slot.bone_name == bone and not meshes.is_empty() \
			and held.global_position.distance_to(player.global_position) < 1.5
