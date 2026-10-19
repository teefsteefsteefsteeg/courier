class_name RepairSite
extends ToolTarget
## A damaged structure the courier repairs (Phase 5H): a hammer for wooden ones (fences,
## the pond jetty), a trowel for stonework. It needs `materials` (material_id -> count) in
## the inventory to start, takes them when the last stroke lands, then swaps
## damaged_visual for repaired_visual for good and pays reward_gold and reward_reputation
## once: the GatheringService records the repair (saved), and mark_repaired() refuses a
## second time, so the reward can never be paid twice. unlocks (optional) are enabled when
## repaired, e.g. a fishing spot at the end of the jetty, or colliders.

signal repaired

## material_id -> amount taken by the repair.
@export var materials: Dictionary[StringName, int] = {}
@export_range(0, 9999) var reward_gold: int = 20
@export_range(0, 999) var reward_reputation: int = 3
@export var damaged_visual: Node3D
@export var repaired_visual: Node3D
## Nodes shown/enabled only once repaired (a walkway collider, a fishing spot).
@export var unlocks: Array[Node] = []
## Colliders active only while damaged (e.g. keeping the courier off a broken jetty).
@export var blockers: Array[CollisionObject3D] = []


func is_available() -> bool:
	return not is_repaired()


func is_repaired() -> bool:
	var service := get_service()
	return service != null and service.is_repaired(target_id)


func get_unavailable_text() -> String:
	return "repaired"


func get_interaction_prompt(interactor: Node) -> String:
	if is_repaired():
		return ""
	return super(interactor)


## The materials the courier still lacks, e.g. "needs 3 Wood (you have 1)".
func check_requirements(user: ToolUser) -> String:
	var inventory := user.get_inventory() if user != null else null
	if inventory == null:
		return "needs materials"
	var missing: PackedStringArray = []
	for id in materials:
		var have := inventory.get_material_count(id)
		if have < materials[id]:
			var material := inventory.get_material_definition(id)
			missing.append("%d %s (you have %d)" % [materials[id], material.display_name if material != null else String(id), have])
	return "needs " + ", ".join(missing) if not missing.is_empty() else ""


## "3 Wood, 1 Clay" (for the HUD and docs).
func get_materials_text(inventory: CourierInventory) -> String:
	var parts: PackedStringArray = []
	for id in materials:
		var material := inventory.get_material_definition(id) if inventory != null else null
		parts.append("%d %s" % [materials[id], material.display_name if material != null else String(id)])
	return ", ".join(parts)


func complete(user: ToolUser) -> String:
	var service := get_service()
	var inventory := user.get_inventory() if user != null else null
	if service == null or inventory == null or is_repaired():
		return ""
	if not inventory.remove_materials(materials):
		return ""
	if not service.mark_repaired(target_id):
		return ""
	service.add_count(&"repair")
	var wallet := CourierWallet.find(get_tree())
	if wallet != null:
		wallet.add_gold(reward_gold)
		wallet.add_reputation(reward_reputation)
	refresh()
	repaired.emit()
	return "%s repaired! +%d gold, +%d reputation" % [display_name, reward_gold, reward_reputation]


func refresh() -> void:
	# Out of the tree there is no GatheringService to ask; _enter_tree refreshes later.
	if not is_inside_tree():
		return
	var done := is_repaired()
	set_active(damaged_visual, not done)
	set_active(repaired_visual, done)
	for node in unlocks:
		if node is CollisionObject3D:
			(node as CollisionObject3D).process_mode = Node.PROCESS_MODE_INHERIT if done else Node.PROCESS_MODE_DISABLED
		elif node is Node3D:
			(node as Node3D).visible = done
		if node is ToolTarget:
			node.refresh()
	for blocker in blockers:
		blocker.process_mode = Node.PROCESS_MODE_DISABLED if done else Node.PROCESS_MODE_INHERIT
	if interactable != null:
		interactable.enabled = not done
