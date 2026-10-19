class_name MaterialItem
extends Resource
## A stackable resource the courier gathers with tools (fish, wood, stone, ore, clay),
## authored as .tres in res://data/materials/. CourierInventory keeps a count per
## material_id; repairs consume them and the Toolwright buys them for sell_price each.
## Phase 7 adds seeds (bought from the Toolwright for buy_price, planted in farm plots)
## and produce (harvested, sold). material_id is saved: never rename a shipped id.

## Append only: saved data stores material ids, scenes store these values.
enum Kind { FISH, WOOD, STONE, ORE, CLAY, SEED, PRODUCE }

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


static func kind_name(value: Kind) -> String:
	return ["Fish", "Wood", "Stone", "Ore", "Clay", "Seeds", "Produce"][value]
