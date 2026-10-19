class_name EnhancementVisuals
extends Node
## Shows the courier's enhancement levels (Phase 7): an EnhancementGlow on the held weapon
## and on the shield, and an aura around the body for enhanced armor (the Binbun StatusFX
## shatter effect, CC0, recoloured by Enhancement.level_color; more particles and glow per
## level, its light streaks only at +5). Purely cosmetic: EquipmentStats applies the
## bonuses whether or not this shows anything, and UISettings.SHOW_ENHANCEMENT_VFX hides it.
##
## Lives in GameplayServices. The effects are children of the player (or of the held
## models), so they follow teleports and region changes. Rebuilds whenever equipment,
## levels, the held models or the setting change, including after a save is loaded.

const GROUP := &"enhancement_visuals"
const ARMOR_AURA := preload("res://assets/vfx/BinbunVFX_Vol2/StatusFX/effects/status/vfx_status_shatter.tscn")
const AURA_HEIGHT := 0.9
const AURA_SCALE := 0.85

@export var inventory: CourierInventory

var weapon_glow: EnhancementGlow = null
var shield_glow: EnhancementGlow = null
## The armor aura (a VFXStatusBB under the player), null without enhanced armor.
var armor_aura: Node3D = null
var player: Node3D = null
var character: KayKitCharacter = null
var _state: Array = []


static func find(tree: SceneTree) -> EnhancementVisuals:
	return tree.get_first_node_in_group(GROUP) as EnhancementVisuals if tree != null else null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _process(_delta: float) -> void:
	if inventory == null:
		inventory = CourierInventory.find(get_tree())
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		player = get_tree().get_first_node_in_group(CombatController.PLAYER_GROUP) as Node3D
		character = null
		if player != null:
			var found := player.find_children("*", "KayKitCharacter", true, false)
			character = found[0] as KayKitCharacter if not found.is_empty() else null
	if inventory == null or player == null:
		return
	var state := _current_state()
	if state != _state:
		_state = state
		rebuild()


## Level of the item equipped in slot, 0 when nothing (or a tool) is there.
func get_slot_level(slot: ItemDefinition.Slot) -> int:
	var item := inventory.get_equipped(slot) if inventory != null else null
	return inventory.get_enhancement(item.item_id) if item != null and Enhancement.can_enhance(item) else 0


func is_showing() -> bool:
	return UISettings.show_enhancement_vfx()


## Removes and rebuilds every effect from the current equipment and setting.
func rebuild() -> void:
	_clear()
	if inventory == null or player == null or not is_showing():
		return
	if character != null:
		weapon_glow = EnhancementGlow.build(character.get_held_item_node(), get_slot_level(ItemDefinition.Slot.MAIN_HAND))
		shield_glow = EnhancementGlow.build(character.get_off_hand_item_node(), get_slot_level(ItemDefinition.Slot.OFF_HAND))
	var armor_level := get_slot_level(ItemDefinition.Slot.ARMOR)
	if armor_level > 0:
		armor_aura = _build_armor_aura(armor_level)


func _build_armor_aura(level: int) -> Node3D:
	var aura := ARMOR_AURA.instantiate() as Node3D
	aura.name = "EnhancementArmorAura"
	# Own copies of the shared materials, so the colour set here stays on this aura.
	for child in aura.get_children():
		if child is GeometryInstance3D and (child as GeometryInstance3D).material_override != null:
			(child as GeometryInstance3D).material_override = (child as GeometryInstance3D).material_override.duplicate()
		if child is GPUParticles3D and (child as GPUParticles3D).process_material != null:
			(child as GPUParticles3D).process_material = (child as GPUParticles3D).process_material.duplicate()
	var color := Enhancement.level_color(level)
	aura.position = Vector3(0, AURA_HEIGHT, 0)
	aura.scale = Vector3.ONE * AURA_SCALE
	player.add_child(aura)
	aura.set(&"primary_color", color)
	aura.set(&"secondary_color", color.lightened(0.35))
	aura.set(&"tertiary_color", color.darkened(0.3))
	aura.set(&"emission", 3.0 + 1.2 * level)
	aura.set(&"particles_amount", 10 + 6 * level)
	# Without proximity fade the motes stay bright where they pass the courier's body.
	aura.set(&"proximity_fade", false)
	# The light streaks (the effect's quad) are the +5 crown.
	var streaks := aura.get_node_or_null(^"MeshInstance3D") as MeshInstance3D
	if streaks != null:
		streaks.visible = level >= Enhancement.MAX_LEVEL
	aura.set(&"emitting", true)
	return aura


func get_armor_particles() -> GPUParticles3D:
	return armor_aura.get_node_or_null(^"Aura") as GPUParticles3D if armor_aura != null else null


func _clear() -> void:
	# A glow is freed with its held model when the item changes; skip those.
	for node: Variant in [weapon_glow, shield_glow, armor_aura]:
		if is_instance_valid(node):
			var effect := node as Node
			if effect.get_parent() != null:
				effect.get_parent().remove_child(effect)
			effect.queue_free()
	weapon_glow = null
	shield_glow = null
	armor_aura = null


## Everything the effects depend on; a change triggers rebuild().
func _current_state() -> Array:
	var held := character.get_held_item_node() if character != null else null
	var off := character.get_off_hand_item_node() if character != null else null
	return [is_showing(), player.get_instance_id(),
		held.get_instance_id() if held != null else 0, get_slot_level(ItemDefinition.Slot.MAIN_HAND),
		off.get_instance_id() if off != null else 0, get_slot_level(ItemDefinition.Slot.OFF_HAND),
		get_slot_level(ItemDefinition.Slot.ARMOR)]
