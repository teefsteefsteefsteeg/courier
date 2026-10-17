class_name CourierWallet
extends Node
## Player gold and reputation. Lives next to QuestManager in GameplayServices.

signal gold_changed(new_value: int, delta: int)
signal reputation_changed(new_value: int, delta: int)

const GROUP := &"courier_wallet"

@export var gold: int = 0
@export var reputation: int = 0


func _enter_tree() -> void:
	add_to_group(GROUP)


func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold = maxi(gold + amount, 0)
	gold_changed.emit(gold, amount)


func add_reputation(amount: int) -> void:
	if amount == 0:
		return
	reputation += amount
	reputation_changed.emit(reputation, amount)


static func find(tree: SceneTree) -> CourierWallet:
	return tree.get_first_node_in_group(GROUP) as CourierWallet
