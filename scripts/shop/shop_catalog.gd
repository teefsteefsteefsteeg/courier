class_name ShopCatalog
extends Resource
## The wares one merchant sells (authored as .tres in res://data/shops/).

@export var shop_id: StringName
@export var title: String = "Shop"
@export var greeting: String = ""
@export var items: Array[ItemDefinition] = []
## The merchant also buys the courier's gathered materials (MaterialItem.sell_price each).
@export var buys_materials: bool = false


func get_item(item_id: StringName) -> ItemDefinition:
	for item in items:
		if item != null and item.item_id == item_id:
			return item
	return null
