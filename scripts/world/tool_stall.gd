class_name ToolStall
extends Node3D
## The Toolwright's stall across the lane from the Hill Smithy (Phase 5H): a counter dressed
## with KayKit RPG Tools, an anvil, a grindstone and a tool rack, and Toolwright Hobb behind
## the counter. Like the Armory it holds no shop logic: ShopUI gives `merchant` a Merchant
## selling `catalog` at runtime (group "shop_locations"), so talking to Hobb opens the shop,
## which also buys the courier's gathered materials.

const GROUP := &"shop_locations"

@export var merchant: NPC
@export var catalog: ShopCatalog
## How far in front of the shopkeeper the interaction point sits (serving across the counter).
@export_range(0.0, 2.0, 0.05, "suffix:m") var serve_reach: float = 1.0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if merchant != null:
		# In front of the shopkeeper: NPCs face their local -Z.
		merchant.interactable.position.z -= serve_reach


## Where the courier stands to trade.
func get_shop_front() -> Marker3D:
	return get_node(^"Markers/ShopFront") as Marker3D
