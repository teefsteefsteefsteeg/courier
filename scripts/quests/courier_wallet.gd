class_name CourierWallet
extends Node
## Player gold and reputation. Lives next to QuestManager in GameplayServices.
## Reputation also maps to a courier rank (Phase 5F); see RANKS.

signal gold_changed(new_value: int, delta: int)
signal reputation_changed(new_value: int, delta: int)
## Emitted after reputation_changed when the reputation crosses a RANKS threshold.
signal rank_changed(new_rank: int, old_rank: int)

const GROUP := &"courier_wallet"
## [minimum reputation, rank title], ascending. Index into this array is the rank.
const RANKS := [
	[0, "Novice Courier"],
	[15, "Apprentice Courier"],
	[35, "Journeyman Courier"],
	[75, "Trusted Courier"],
	[150, "Renowned Courier"],
]

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
	var old_rank := get_rank()
	reputation += amount
	reputation_changed.emit(reputation, amount)
	var new_rank := get_rank()
	if new_rank != old_rank:
		rank_changed.emit(new_rank, old_rank)


func get_rank() -> int:
	return rank_for(reputation)


func get_rank_title() -> String:
	return rank_title(get_rank())


## 0..1 progress from the current rank threshold to the next (1 at the top rank).
func get_rank_progress() -> float:
	return rank_progress(reputation)


## Reputation still needed for the next rank, or 0 at the top rank.
func get_reputation_to_next_rank() -> int:
	var rank := get_rank()
	if rank >= RANKS.size() - 1:
		return 0
	return int(RANKS[rank + 1][0]) - reputation


static func rank_for(value: int) -> int:
	var rank := 0
	for i in RANKS.size():
		if value >= int(RANKS[i][0]):
			rank = i
	return rank


static func rank_title(rank: int) -> String:
	return String(RANKS[clampi(rank, 0, RANKS.size() - 1)][1])


static func rank_progress(value: int) -> float:
	var rank := rank_for(value)
	if rank >= RANKS.size() - 1:
		return 1.0
	var low := int(RANKS[rank][0])
	var high := int(RANKS[rank + 1][0])
	return clampf(float(value - low) / float(high - low), 0.0, 1.0)


static func find(tree: SceneTree) -> CourierWallet:
	return tree.get_first_node_in_group(GROUP) as CourierWallet
