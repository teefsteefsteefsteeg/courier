class_name CourierInventory
extends Node
## Items the courier owns and what is equipped in each slot. Lives next to CourierWallet
## in GameplayServices. Items are referenced by ItemDefinition.item_id; every id that
## can be owned must be registered (item_definitions) so a save can be read back.
## Weapons are unique: owning one twice is refused.

signal item_added(item: ItemDefinition)
## item is null when the slot was emptied.
signal equipment_changed(slot: ItemDefinition.Slot, item: ItemDefinition)

const GROUP := &"courier_inventory"

## Every item that can be owned (shop wares). Unknown ids in a save are dropped.
@export var item_definitions: Array[ItemDefinition] = []

var _definitions: Dictionary[StringName, ItemDefinition] = {}
var _owned: Array[StringName] = []
var _equipped: Dictionary[int, StringName] = {}


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


## Adds item; false if it is null, has no id, or is already owned.
func add_item(item: ItemDefinition) -> bool:
	if item == null or item.item_id == &"" or has_item(item.item_id):
		return false
	register_item(item)
	_owned.append(item.item_id)
	item_added.emit(item)
	return true


## Equips an owned item in its slot (replacing what was there). False if not owned.
func equip(item_id: StringName) -> bool:
	var item := get_definition(item_id)
	if item == null or not has_item(item_id):
		return false
	if _equipped.get(item.slot, &"") == item_id:
		return true
	_equipped[item.slot] = item_id
	equipment_changed.emit(item.slot, item)
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


func to_dict() -> Dictionary:
	var equipped := {}
	for slot in _equipped:
		equipped[ItemDefinition.Slot.keys()[slot]] = String(_equipped[slot])
	return {"owned": _owned.map(func(id: StringName) -> String: return String(id)), "equipped": equipped}


## Replaces the contents with saved data (unknown ids and unowned equipment are dropped).
func from_dict(data: Dictionary) -> void:
	for slot in _equipped.keys():
		unequip(slot)
	_owned.clear()
	for id in data.get("owned", []):
		var item := get_definition(StringName(id))
		if item != null and not has_item(item.item_id):
			_owned.append(item.item_id)
	var equipped: Dictionary = data.get("equipped", {})
	for slot_name in equipped:
		var item := get_definition(StringName(equipped[slot_name]))
		if item != null and has_item(item.item_id) and ItemDefinition.Slot.keys()[item.slot] == slot_name:
			equip(item.item_id)
