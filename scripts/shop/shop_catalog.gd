class_name ShopCatalog
extends Resource
## The wares one merchant sells (authored as .tres in res://data/shops/).

@export var shop_id: StringName
@export var title: String = "Shop"
@export var greeting: String = ""
@export var items: Array[ItemDefinition] = []
## The merchant also buys the courier's gathered materials (MaterialItem.sell_price each).
@export var buys_materials: bool = false
## The merchant enhances owned weapons, shields and armor (Phase 7: Brenna).
@export var enhances_items: bool = false
## Stackable goods the merchant sells for MaterialItem.buy_price each (Phase 7: seeds).
@export var sells_materials: Array[MaterialItem] = []


func get_item(item_id: StringName) -> ItemDefinition:
	for item in items:
		if item != null and item.item_id == item_id:
			return item
	return null
