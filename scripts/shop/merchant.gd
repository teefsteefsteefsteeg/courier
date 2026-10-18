class_name Merchant
extends Node
## Makes its parent a shop. Put it under an NPC (the NPC keeps its dialogue; the prompt
## becomes "Browse wares of <name>" and interacting opens the shop) or under any node that
## has an Interactable child (e.g. scenes/gameplay/shop/merchant_counter.tscn, for the
## Armory building). ShopUI opens on `shop_requested`; other UIs can listen as well.
##
## Merchant interface (what a shop UI needs, so other merchant types can implement it):
##   group "merchants", signal shop_requested(merchant, interactor),
##   get_catalog() -> ShopCatalog, get_merchant_name() -> String

signal shop_requested(merchant: Merchant, interactor: Node)

const GROUP := &"merchants"

@export var catalog: ShopCatalog
## Shown as the shop owner; defaults to the parent NPC's name or the catalog title.
@export var merchant_name: String = ""
## Prompt verb for a parent NPC.
@export var prompt_verb: String = "Browse wares of"

var interactable: Interactable = null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	# Deferred: a parent NPC readies after its children, and its `interactable` is @onready.
	_bind.call_deferred()


func _bind() -> void:
	var owner_node := get_parent()
	if owner_node is NPC:
		interactable = (owner_node as NPC).interactable
	elif owner_node is Interactable:
		interactable = owner_node
	elif owner_node != null:
		for child in owner_node.get_children():
			if child is Interactable:
				interactable = child
	if interactable == null:
		push_warning("Merchant %s: no Interactable on %s" % [name, owner_node])
		return
	if not owner_node is NPC:
		interactable.prompt_verb = "Browse"
		interactable.display_name = get_merchant_name()
	interactable.interacted.connect(_on_interacted)


func get_catalog() -> ShopCatalog:
	return catalog


func get_merchant_name() -> String:
	if not merchant_name.is_empty():
		return merchant_name
	if get_parent() is NPC:
		return (get_parent() as NPC).npc_name
	return catalog.title if catalog != null else "Shop"


## Prompt verb for NPC.get_interaction_prompt() ("Browse wares of Smith Hilda").
func get_prompt_verb(_npc: NPC, _interactor: Node) -> String:
	return prompt_verb


## Opens the shop (also used by tests and scripted sequences).
func open_shop(interactor: Node) -> void:
	shop_requested.emit(self, interactor)


func _on_interacted(interactor: Node) -> void:
	open_shop(interactor)
