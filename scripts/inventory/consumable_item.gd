class_name ConsumableItem
extends MaterialItem
## Food, potions and combat buffs (Phase 8), authored as .tres in res://data/consumables/.
## A stackable MaterialItem (kind FOOD, HEALTH_POTION, MANA_POTION or BUFF), so stacks,
## saving, buying (buy_price) and selling work as for any material. CourierVitals.consume()
## applies the effects and takes one from the stack:
##   heal                 HP restored at once
##   heal_over_time       HP restored evenly over effect_duration (food)
##   mana                 MP restored at once
##   rage                 rage added at once
##   buff_* fields        a timed buff for effect_duration seconds (one per buff_id; eating
##                        the same buff again refreshes it): damage x, defense +, critical
##                        chance +, rage gain x, HP and MP regeneration +/s
## Potions share a short use cooldown (CourierVitals.POTION_COOLDOWN); food does not.

## Health restored at once.
@export var heal: float = 0.0
## Health restored evenly over effect_duration.
@export var heal_over_time: float = 0.0
## Mana restored at once.
@export var mana: float = 0.0
## Rage added at once.
@export var rage: float = 0.0
## Seconds the heal-over-time and the buff last.
@export_range(0.0, 600.0, 1.0, "suffix:s") var effect_duration: float = 0.0

@export_group("Buff")
## Buffs with the same id replace each other (&"" = no buff).
@export var buff_id: StringName = &""
@export var buff_name: String = ""
## Multiplies the damage of every attack and skill (1 = no change).
@export var damage_multiplier: float = 1.0
@export var defense_bonus: float = 0.0
## Added to the chance (0..1) that a hit is critical.
@export_range(0.0, 1.0, 0.01) var crit_chance: float = 0.0
## Multiplies rage gained from hits.
@export var rage_gain_multiplier: float = 1.0
@export var hp_regen_bonus: float = 0.0
@export var mp_regen_bonus: float = 0.0


func has_buff() -> bool:
	return buff_id != &"" and effect_duration > 0.0


func is_potion() -> bool:
	return kind == Kind.HEALTH_POTION or kind == Kind.MANA_POTION


## Player-facing effect lines, e.g. ["+60 HP", "+20% damage for 90 s"].
func get_effect_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	if heal > 0.0:
		lines.append("+%d HP" % roundi(heal))
	if heal_over_time > 0.0:
		lines.append("+%d HP over %d s" % [roundi(heal_over_time), roundi(effect_duration)])
	if mana > 0.0:
		lines.append("+%d MP" % roundi(mana))
	if rage > 0.0:
		lines.append("+%d rage" % roundi(rage))
	if has_buff():
		var seconds := " for %d s" % roundi(effect_duration)
		if not is_equal_approx(damage_multiplier, 1.0):
			lines.append("%+d%% damage%s" % [roundi((damage_multiplier - 1.0) * 100.0), seconds])
		if defense_bonus != 0.0:
			lines.append("%+d defense%s" % [roundi(defense_bonus), seconds])
		if crit_chance > 0.0:
			lines.append("+%d%% critical chance%s" % [roundi(crit_chance * 100.0), seconds])
		if not is_equal_approx(rage_gain_multiplier, 1.0):
			lines.append("%+d%% rage from hits%s" % [roundi((rage_gain_multiplier - 1.0) * 100.0), seconds])
		if hp_regen_bonus > 0.0:
			lines.append("+%.1f HP/s regeneration%s" % [hp_regen_bonus, seconds])
		if mp_regen_bonus > 0.0:
			lines.append("+%.1f MP/s regeneration%s" % [mp_regen_bonus, seconds])
	return lines
