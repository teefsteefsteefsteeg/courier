class_name CourierInventory
extends Node
## Items the courier owns and what is equipped in each slot. Lives next to CourierWallet
## in GameplayServices. Items are referenced by ItemDefinition.item_id; every id that
## can be owned must be registered (item_definitions) so a save can be read back.
## Weapons are unique: owning one twice is refused.
##
## Also holds the five weapon quick slots (QuickWeaponBar, keys 1-5). A quick slot only
## refers to an owned main-hand weapon by id; ownership stays in the owned list, and a
## weapon sits in at most one quick slot. A newly added weapon fills the first empty slot.

signal item_added(item: ItemDefinition)
## item is null when the slot was emptied.
signal equipment_changed(slot: ItemDefinition.Slot, item: ItemDefinition)
signal quick_slots_changed

const GROUP := &"courier_inventory"
const QUICK_SLOT_COUNT := 5

## Every item that can be owned (shop wares). Unknown ids in a save are dropped.
@export var item_definitions: Array[ItemDefinition] = []

var _definitions: Dictionary[StringName, ItemDefinition] = {}
var _owned: Array[StringName] = []
var _equipped: Dictionary[int, StringName] = {}
var _quick_slots: Array[StringName] = [&"", &"", &"", &"", &""]


func _enter_tree() -> void:
	add_to_group(GROUP)
	for item in item_definitions:
		register_item(item)


static func find(tree: SceneTree) -> CourierInventory:
	return tree.get_first_node_in_group(GROUP) as CourierInventory


func register_item(item: ItemDefinition) -> void:
	if item != null and item.item_id != &"":
		_definitions[item.item_id] = item


func get_definition(item_id: StringName) -> ItemDefinition:
	return _definitions.get(item_id)


func has_item(item_id: StringName) -> bool:
	return _owned.has(item_id)


## Owned item ids in the order they were added.
func get_owned_ids() -> Array[StringName]:
	return _owned.duplicate()


## Every registered item (owned or not), in registration order.
func get_all_definitions() -> Array[ItemDefinition]:
	var items: Array[ItemDefinition] = []
	for item_id in _definitions:
		items.append(_definitions[item_id])
	return items


## Adds item; false if it is null, has no id, or is already owned. A weapon also goes into
## the first empty quick slot.
func add_item(item: ItemDefinition) -> bool:
	if item == null or item.item_id == &"" or has_item(item.item_id):
		return false
	register_item(item)
	_owned.append(item.item_id)
	item_added.emit(item)
	if item.is_weapon() and find_quick_slot(item.item_id) < 0:
		var empty := _quick_slots.find(&"")
		if empty >= 0:
			assign_quick_slot(empty, item.item_id)
	return true


## Equips an owned item in its slot (replacing what was there). False if not owned, or if
## it is an off-hand item while a two-handed weapon is equipped. A two-handed weapon
## empties the off-hand slot.
func equip(item_id: StringName) -> bool:
	var item := get_definition(item_id)
	if item == null or not has_item(item_id):
		return false
	if item.slot == ItemDefinition.Slot.OFF_HAND:
		var main := get_equipped(ItemDefinition.Slot.MAIN_HAND)
		if main != null and main.two_handed:
			return false
	if _equipped.get(item.slot, &"") == item_id:
		return true
	_equipped[item.slot] = item_id
	equipment_changed.emit(item.slot, item)
	if item.two_handed:
		unequip(ItemDefinition.Slot.OFF_HAND)
	return true


func unequip(slot: ItemDefinition.Slot) -> void:
	if not _equipped.has(slot):
		return
	_equipped.erase(slot)
	equipment_changed.emit(slot, null)


func get_equipped(slot: ItemDefinition.Slot) -> ItemDefinition:
	return get_definition(_equipped.get(slot, &""))


func is_equipped(item_id: StringName) -> bool:
	return _equipped.values().has(item_id)


## Every equipped item (for EquipmentStats).
func get_equipped_items() -> Array[ItemDefinition]:
	var items: Array[ItemDefinition] = []
	for slot in _equipped:
		var item := get_definition(_equipped[slot])
		if item != null:
			items.append(item)
	return items


# --- quick slots ----------------------------------------------------------------

## True when item_id may go in a quick slot: an owned main-hand weapon.
func can_quick_slot(item_id: StringName) -> bool:
	var item := get_definition(item_id)
	return item != null and item.is_weapon() and has_item(item_id)


## Puts an owned weapon in quick slot index (0-based), moving it out of any other slot.
## False for a bad index or an item that cannot be quick-slotted.
func assign_quick_slot(index: int, item_id: StringName) -> bool:
	if index < 0 or index >= QUICK_SLOT_COUNT or not can_quick_slot(item_id):
		return false
	if _quick_slots[index] == item_id:
		return true
	var previous := find_quick_slot(item_id)
	if previous >= 0:
		_quick_slots[previous] = &""
	_quick_slots[index] = item_id
	quick_slots_changed.emit()
	return true


func clear_quick_slot(index: int) -> void:
	if index < 0 or index >= QUICK_SLOT_COUNT or _quick_slots[index] == &"":
		return
	_quick_slots[index] = &""
	quick_slots_changed.emit()


## The weapon in quick slot index, or null when the slot is empty.
func get_quick_slot(index: int) -> ItemDefinition:
	if index < 0 or index >= QUICK_SLOT_COUNT:
		return null
	return get_definition(_quick_slots[index])


func get_quick_slot_ids() -> Array[StringName]:
	return _quick_slots.duplicate()


## Index of the quick slot holding item_id, or -1.
func find_quick_slot(item_id: StringName) -> int:
	return _quick_slots.find(item_id) if item_id != &"" else -1


## Equips the weapon in quick slot index. False when the slot is empty.
func select_quick_slot(index: int) -> bool:
	var item := get_quick_slot(index)
	return item != null and equip(item.item_id)


# --- save -----------------------------------------------------------------------

func to_dict() -> Dictionary:
	var equipped := {}
	for slot in _equipped:
		equipped[ItemDefinition.Slot.keys()[slot]] = String(_equipped[slot])
	return {
		"owned": _owned.map(func(id: StringName) -> String: return String(id)),
		"equipped": equipped,
		"quick_slots": _quick_slots.map(func(id: StringName) -> String: return String(id)),
	}


## Replaces the contents with saved data (unknown ids and unowned equipment are dropped).
## Saves from before quick slots fill them with the owned weapons in order.
func from_dict(data: Dictionary) -> void:
	for slot in _equipped.keys():
		unequip(slot)
	_owned.clear()
	_quick_slots.fill(&"")
	for id in data.get("owned", []):
		var item := get_definition(StringName(id))
		if item != null and not has_item(item.item_id):
			_owned.append(item.item_id)
	var equipped: Dictionary = data.get("equipped", {})
	# Main hand first, so a two-handed weapon's rule applies to the saved off-hand item.
	for slot_name in ItemDefinition.Slot.keys():
		if not equipped.has(slot_name):
			continue
		var item := get_definition(StringName(equipped[slot_name]))
		if item != null and has_item(item.item_id) and ItemDefinition.Slot.keys()[item.slot] == slot_name:
			equip(item.item_id)
	if data.has("quick_slots"):
		var saved: Array = data["quick_slots"]
		for index in mini(saved.size(), QUICK_SLOT_COUNT):
			var id := StringName(saved[index])
			if can_quick_slot(id) and find_quick_slot(id) < 0:
				_quick_slots[index] = id
	else:
		var next := 0
		for id in _owned:
			if next < QUICK_SLOT_COUNT and can_quick_slot(id):
				_quick_slots[next] = id
				next += 1
	quick_slots_changed.emit()
