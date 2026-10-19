class_name Armory
extends Node3D
## Willowmere's weapon shop: the armory hall, its outdoor weapon displays and
## the weaponsmith behind the counter. Visuals and the interaction point only;
## there is no shop UI or economy here. The gameplay branch connects
## `shop_requested` (fired when the courier talks to the merchant) to its shop
## screen, and can read the markers below to place anything else.

signal shop_requested(interactor: Node)

## The weaponsmith NPC behind the counter.
@export var merchant: NPC
## How far in front of the weaponsmith (towards the yard) her interaction point sits. She
## serves across the counter, so the courier can trade from the yard instead of having to
## press against the counter to come within reach.
@export_range(0.0, 2.0, 0.05, "suffix:m") var serve_reach: float = 1.0


func _ready() -> void:
	if merchant != null:
		merchant.interactable.position.z += serve_reach
		merchant.interactable.interacted.connect(_on_merchant_interacted)


## Where the courier stands to trade, in front of the counter.
func get_shop_front() -> Marker3D:
	return get_node(^"Markers/ShopFront") as Marker3D


## The shop door (decorative; the hall has no interior).
func get_entrance() -> Marker3D:
	return get_node(^"Markers/Entrance") as Marker3D


func _on_merchant_interacted(interactor: Node) -> void:
	shop_requested.emit(interactor)
