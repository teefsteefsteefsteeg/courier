class_name Enhancement
extends RefCounted
## Item enhancement rules (Phase 7): an owned weapon, shield or armor piece can be enhanced
## from +0 to +5. CourierInventory stores the level per item (saved); EquipmentStats applies
## the bonus; the enhancement VFX colour the item by level. One place for the numbers.

const MAX_LEVEL := 5
## Glow colour per level (index 0 = not enhanced): white/silver, green, blue, purple, gold.
const COLORS: Array[Color] = [Color(1, 1, 1, 0), Color(0.86, 0.9, 1.0), Color(0.35, 1.0, 0.45),
		Color(0.3, 0.6, 1.0), Color(0.75, 0.4, 1.0), Color(1.0, 0.78, 0.25)]
const TIER_NAMES: Array[String] = ["", "Silver", "Verdant", "Azure", "Arcane", "Golden"]


static func clamp_level(level: int) -> int:
	return clampi(level, 0, MAX_LEVEL)


static func level_color(level: int) -> Color:
	return COLORS[clamp_level(level)]


## "+3" (or "" for +0).
static func level_text(level: int) -> String:
	return "+%d" % level if level > 0 else ""


## Weapon damage multiplier: +10% per level.
static func damage_multiplier(level: int) -> float:
	return 1.0 + 0.1 * clamp_level(level)


## Extra defense per level on armor and shields.
static func defense_bonus(level: int) -> float:
	return 2.0 * clamp_level(level)
