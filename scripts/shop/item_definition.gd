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
##   weapon_type   how the courier attacks with it (main hand): STAFF casts the Magic Bolt,
##                 SWORD fast melee, AXE heavy melee, BOW arrows. NONE = not a weapon (the
##                 shield); without a weapon the courier casts the Magic Bolt bare-handed.
##   two_handed    occupies both hands: equipping it empties the off-hand slot
##   stat bonuses  applied by EquipmentStats to the courier's existing combat stats:
##                 bolt_damage_bonus (+), bolt_cooldown_multiplier (x), bolt_range_bonus (+)
##                 for the Magic Bolt (staff), shield_durability_bonus (+) for the Package
##                 Shield; zero/one means "no change".
##   attack stats  for SWORD / AXE / BOW: attack_damage, attack_range (m), attack_cooldown
##                 (s), and for melee attack_arc_degrees and attack_windup (s until the hit).

enum Slot { MAIN_HAND, OFF_HAND }
enum WeaponType { NONE, STAFF, SWORD, AXE, BOW }

@export var item_id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var slot: Slot = Slot.MAIN_HAND
@export_range(1, 99999) var price: int = 1
@export var icon: Texture2D
@export var held_model: PackedScene
@export var weapon_type: WeaponType = WeaponType.NONE
@export var two_handed: bool = false

@export_group("Stats")
## Added to CombatController.bolt_damage.
@export var bolt_damage_bonus: float = 0.0
## Multiplies CombatController.bolt_cooldown (below 1 = faster).
@export_range(0.1, 4.0, 0.05) var bolt_cooldown_multiplier: float = 1.0
## Added to CombatController.bolt_range (metres).
@export var bolt_range_bonus: float = 0.0
## Added to CombatController.shield_max_durability (Package Shield).
@export var shield_durability_bonus: float = 0.0

@export_group("Attack")
## Damage per melee hit or arrow (SWORD, AXE, BOW).
@export var attack_damage: float = 0.0
## Melee reach or arrow range, in metres.
@export var attack_range: float = 0.0
## Seconds between attacks.
@export var attack_cooldown: float = 0.5
## Melee only: width of the swing in front of the courier.
@export_range(10.0, 360.0, 5.0, "suffix:°") var attack_arc_degrees: float = 110.0
## Melee only: seconds from the swing starting to the hit landing.
@export_range(0.0, 2.0, 0.01, "suffix:s") var attack_windup: float = 0.1


static func slot_name(value: Slot) -> String:
	return "Weapon" if value == Slot.MAIN_HAND else "Off-hand"


static func weapon_type_name(value: WeaponType) -> String:
	return ["", "Staff", "Sword", "Axe", "Bow"][value]


## True for main-hand weapons (what quick slots accept).
func is_weapon() -> bool:
	return slot == Slot.MAIN_HAND and weapon_type != WeaponType.NONE


func is_melee() -> bool:
	return weapon_type == WeaponType.SWORD or weapon_type == WeaponType.AXE


## Player-facing stat lines, e.g. ["20 damage", "0.36 s", "1.8 m reach"].
func get_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	if is_melee() or weapon_type == WeaponType.BOW:
		lines.append("%d damage" % roundi(attack_damage))
		lines.append("%.2f s" % attack_cooldown)
		lines.append(("%.1f m reach" if is_melee() else "%d m range") % (attack_range if is_melee() else roundi(attack_range)))
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


## "Sword · fast melee" style summary of how the weapon attacks ("" for non-weapons).
func get_attack_summary() -> String:
	match weapon_type:
		WeaponType.STAFF:
			return "Staff · magic bolts"
		WeaponType.SWORD:
			return "Sword · fast melee"
		WeaponType.AXE:
			return "Axe · heavy melee"
		WeaponType.BOW:
			return "Bow · arrows"
	return ""
