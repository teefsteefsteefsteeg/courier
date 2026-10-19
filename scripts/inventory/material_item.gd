class_name MaterialItem
extends Resource
## A stackable resource the courier gathers with tools (fish, wood, stone, ore, clay),
## authored as .tres in res://data/materials/. CourierInventory keeps a count per
## material_id; repairs consume them and the Toolwright buys them for sell_price each.
## material_id is saved: never rename a shipped id.

enum Kind { FISH, WOOD, STONE, ORE, CLAY }

@export var material_id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var kind: Kind = Kind.WOOD
## 32x32 pixel-art icon, drawn with nearest filtering.
@export var icon: Texture2D
## Gold a merchant pays for one (0 = cannot be sold).
@export_range(0, 9999) var sell_price: int = 1


static func kind_name(value: Kind) -> String:
	return ["Fish", "Wood", "Stone", "Ore", "Clay"][value]
