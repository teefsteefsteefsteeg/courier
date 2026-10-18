class_name ItemDefinition
extends Resource
## Static data for a shop item / inventory item (authored as .tres in res://data/items/).
##
## Item data contract (what shops, the inventory, the save file and equipment read):
##   item_id       StringName, unique and stable (saved; never rename a shipped id)
##   display_name  shown in the shop and HUD
##   description   one or two lines of flavour
##   slot          equipment slot the item goes in (MAIN_HAND weapon, OFF_HAND shield)
##   price         gold cost in shops (> 0)
##   icon          32x32 pixel-art Texture2D, drawn with nearest filtering
##   held_model    optional PackedScene shown in the courier's hand when equipped
##   stat bonuses  applied by EquipmentStats to the courier's existing combat stats:
##                 bolt_damage_bonus (+), bolt_cooldown_multiplier (x), bolt_range_bonus (+),
##                 shield_durability_bonus (+). The courier has no melee attack, so every
##                 weapon works through the Magic Bolt; zero/one means "no change".

enum Slot { MAIN_HAND, OFF_HAND }

@export var item_id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var slot: Slot = Slot.MAIN_HAND
@export_range(1, 99999) var price: int = 1
@export var icon: Texture2D
@export var held_model: PackedScene

@export_group("Stats")
## Added to CombatController.bolt_damage.
@export var bolt_damage_bonus: float = 0.0
## Multiplies CombatController.bolt_cooldown (below 1 = faster).
@export_range(0.1, 4.0, 0.05) var bolt_cooldown_multiplier: float = 1.0
## Added to CombatController.bolt_range (metres).
@export var bolt_range_bonus: float = 0.0
## Added to CombatController.shield_max_durability (Package Shield).
@export var shield_durability_bonus: float = 0.0


static func slot_name(value: Slot) -> String:
	return "Weapon" if value == Slot.MAIN_HAND else "Off-hand"


## Player-facing stat lines, e.g. ["+8 bolt damage", "25% slower casting"].
func get_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	if bolt_damage_bonus != 0.0:
		lines.append("%+d bolt damage" % roundi(bolt_damage_bonus))
	if not is_equal_approx(bolt_cooldown_multiplier, 1.0):
		var percent := roundi(absf(1.0 - bolt_cooldown_multiplier) * 100.0)
		lines.append("%d%% %s casting" % [percent, "faster" if bolt_cooldown_multiplier < 1.0 else "slower"])
	if bolt_range_bonus != 0.0:
		lines.append("%+d m bolt range" % roundi(bolt_range_bonus))
	if shield_durability_bonus != 0.0:
		lines.append("%+d package shield" % roundi(shield_durability_bonus))
	return lines
