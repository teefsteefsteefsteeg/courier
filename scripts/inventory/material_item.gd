class_name MaterialItem
extends Resource
## A stackable resource the courier gathers with tools (fish, wood, stone, ore, clay),
## authored as .tres in res://data/materials/. CourierInventory keeps a count per
## material_id; repairs consume them and the Toolwright buys them for sell_price each.
## Phase 7 adds seeds (bought from the Toolwright for buy_price, planted in farm plots)
## and produce (harvested, sold). material_id is saved: never rename a shipped id.
## Phase 8 adds consumables (ConsumableItem, a subclass): food, health and mana potions and
## combat buffs, bought at the Food Market and eaten / drunk from the inventory or the
## consumable quick slots (6-0).

## Append only: saved data stores material ids, scenes store these values.
enum Kind { FISH, WOOD, STONE, ORE, CLAY, SEED, PRODUCE, FOOD, HEALTH_POTION, MANA_POTION, BUFF }

@export var material_id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var kind: Kind = Kind.WOOD
## 32x32 pixel-art icon, drawn with nearest filtering.
@export var icon: Texture2D
## Gold a merchant pays for one (0 = cannot be sold).
@export_range(0, 9999) var sell_price: int = 1
## Gold a merchant that sells materials charges for one (0 = not for sale).
@export_range(0, 9999) var buy_price: int = 0
## Most one stack can hold (0 = CourierInventory.MAX_STACK).
@export_range(0, 999) var max_stack: int = 0


static func kind_name(value: Kind) -> String:
	return ["Fish", "Wood", "Stone", "Ore", "Clay", "Seeds", "Produce", "Food", "Health Potion", "Mana Potion", "Combat Buff"][value]


## The most of this material one stack can hold.
func get_stack_limit() -> int:
	return max_stack if max_stack > 0 else CourierInventory.MAX_STACK


## True for things the courier eats or drinks (ConsumableItem).
func is_consumable() -> bool:
	return kind >= Kind.FOOD
