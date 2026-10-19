class_name CourierInventory
extends Node
## Items the courier owns and what is equipped in each slot. Lives next to CourierWallet
## in GameplayServices. Items are referenced by ItemDefinition.item_id; every id that
## can be owned must be registered (item_definitions) so a save can be read back.
## Weapons are unique: owning one twice is refused.
##
## Also holds the five quick slots (QuickWeaponBar, keys 1-5). A quick slot only refers to
## an owned main-hand weapon or tool by id; ownership stays in the owned list, and an item
## sits in at most one quick slot. A newly added weapon or tool fills the first empty slot.
## Tools (ItemDefinition.tool_type) go in the main hand like weapons.
##
## Materials (Phase 5H): stackable MaterialItem counts (fish, wood, stone, ore, clay, and
## since Phase 7 seeds and produce), up to MAX_STACK each, added by gathering, buying and
## harvesting and removed by repairs, planting and selling.
##
## Enhancement (Phase 7): each owned item has a level 0..Enhancement.MAX_LEVEL.

signal item_added(item: ItemDefinition)
## item is null when the slot was emptied.
signal equipment_changed(slot: ItemDefinition.Slot, item: ItemDefinition)
signal quick_slots_changed
## A material count changed by delta (positive when gathered).
signal materials_changed(material: MaterialItem, count: int, delta: int)
## An owned item's enhancement level changed.
signal enhancement_changed(item_id: StringName, level: int)

const GROUP := &"courier_inventory"
const QUICK_SLOT_COUNT := 5
const MAX_STACK := 999

## Every item that can be owned (shop wares). Unknown ids in a save are dropped.
@export var item_definitions: Array[ItemDefinition] = []
## Every material that can be carried. Unknown ids in a save are dropped.
@export var material_definitions: Array[MaterialItem] = []

var _definitions: Dictionary[StringName, ItemDefinition] = {}
var _owned: Array[StringName] = []
var _equipped: Dictionary[int, StringName] = {}
var _quick_slots: Array[StringName] = [&"", &"", &"", &"", &""]
var _material_definitions: Dictionary[StringName, MaterialItem] = {}
var _materials: Dictionary[StringName, int] = {}
var _enhancements: Dictionary[StringName, int] = {}


func _enter_tree() -> void:
	add_to_group(GROUP)
	for item in item_definitions:
		register_item(item)
	for material in material_definitions:
		register_material(material)


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


## Adds item; false if it is null, has no id, or is already owned. A weapon or tool also
## goes into the first empty quick slot.
func add_item(item: ItemDefinition) -> bool:
	if item == null or item.item_id == &"" or has_item(item.item_id):
		return false
	register_item(item)
	_owned.append(item.item_id)
	item_added.emit(item)
	if item.is_quick_slottable() and find_quick_slot(item.item_id) < 0:
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

## True when item_id may go in a quick slot: an owned main-hand weapon or tool.
func can_quick_slot(item_id: StringName) -> bool:
	var item := get_definition(item_id)
	return item != null and item.is_quick_slottable() and has_item(item_id)


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


## The tool in the main hand, or null (bare hands or a weapon).
func get_equipped_tool() -> ItemDefinition:
	var item := get_equipped(ItemDefinition.Slot.MAIN_HAND)
	return item if item != null and item.is_tool() else null


## The first owned tool of type, or null.
func find_owned_tool(type: ItemDefinition.ToolType) -> ItemDefinition:
	for id in _owned:
		var item := get_definition(id)
		if item != null and item.is_tool() and item.tool_type == type:
			return item
	return null


# --- enhancement ----------------------------------------------------------------

## Enhancement level of an item (0 when not owned or never enhanced).
func get_enhancement(item_id: StringName) -> int:
	return _enhancements.get(item_id, 0) if has_item(item_id) else 0


## Sets an owned item's level (clamped to 0..MAX_LEVEL). False when it is not owned.
func set_enhancement(item_id: StringName, level: int) -> bool:
	if not has_item(item_id):
		return false
	level = Enhancement.clamp_level(level)
	if get_enhancement(item_id) == level:
		return true
	if level == 0:
		_enhancements.erase(item_id)
	else:
		_enhancements[item_id] = level
	enhancement_changed.emit(item_id, level)
	return true


# --- materials ------------------------------------------------------------------

func register_material(material: MaterialItem) -> void:
	if material != null and material.material_id != &"":
		_material_definitions[material.material_id] = material


func get_material_definition(material_id: StringName) -> MaterialItem:
	return _material_definitions.get(material_id)


## Every registered material, in registration order.
func get_all_materials() -> Array[MaterialItem]:
	var out: Array[MaterialItem] = []
	for id in _material_definitions:
		out.append(_material_definitions[id])
	return out


func get_material_count(material_id: StringName) -> int:
	return _materials.get(material_id, 0)


## Adds up to amount of a material (capped at MAX_STACK). Returns how many were added.
func add_material(material: MaterialItem, amount: int = 1) -> int:
	if material == null or material.material_id == &"" or amount <= 0:
		return 0
	register_material(material)
	var count := get_material_count(material.material_id)
	var added := mini(amount, MAX_STACK - count)
	if added <= 0:
		return 0
	_materials[material.material_id] = count + added
	materials_changed.emit(material, count + added, added)
	return added


## True when every material_id -> amount in costs is carried.
func has_materials(costs: Dictionary) -> bool:
	for id in costs:
		if get_material_count(StringName(id)) < int(costs[id]):
			return false
	return true


## Removes every material_id -> amount in costs, all or nothing. Returns whether it did.
func remove_materials(costs: Dictionary) -> bool:
	if not has_materials(costs):
		return false
	for id in costs:
		var material_id := StringName(id)
		var amount := int(costs[id])
		if amount <= 0:
			continue
		var count := get_material_count(material_id) - amount
		if count > 0:
			_materials[material_id] = count
		else:
			_materials.erase(material_id)
		materials_changed.emit(get_material_definition(material_id), count, -amount)
	return true


## Carried materials (material_id -> count) in registration order.
func get_material_counts() -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	for id in _material_definitions:
		if _materials.has(id):
			out[id] = _materials[id]
	return out


# --- save -----------------------------------------------------------------------

func to_dict() -> Dictionary:
	var equipped := {}
	for slot in _equipped:
		equipped[ItemDefinition.Slot.keys()[slot]] = String(_equipped[slot])
	var materials := {}
	for id in _materials:
		materials[String(id)] = _materials[id]
	var enhancements := {}
	for id in _enhancements:
		enhancements[String(id)] = _enhancements[id]
	return {
		"owned": _owned.map(func(id: StringName) -> String: return String(id)),
		"equipped": equipped,
		"quick_slots": _quick_slots.map(func(id: StringName) -> String: return String(id)),
		"materials": materials,
		"enhancements": enhancements,
	}


## Replaces the contents with saved data (unknown ids and unowned equipment are dropped).
## Saves from before quick slots fill them with the owned weapons in order; saves from
## before materials carry none.
func from_dict(data: Dictionary) -> void:
	for slot in _equipped.keys():
		unequip(slot)
	for id in _enhancements.keys():
		_enhancements.erase(id)
		enhancement_changed.emit(id, 0)
	_owned.clear()
	_quick_slots.fill(&"")
	for id in _materials.keys():
		var removed: int = _materials[id]
		_materials.erase(id)
		materials_changed.emit(get_material_definition(id), 0, -removed)
	var saved_materials: Dictionary = data.get("materials", {})
	for id in saved_materials:
		var material := get_material_definition(StringName(id))
		if material != null:
			add_material(material, clampi(int(saved_materials[id]), 0, MAX_STACK))
	for id in data.get("owned", []):
		var item := get_definition(StringName(id))
		if item != null and not has_item(item.item_id):
			_owned.append(item.item_id)
	var enhancements: Dictionary = data.get("enhancements", {})
	for id in enhancements:
		set_enhancement(StringName(id), int(enhancements[id]))
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
