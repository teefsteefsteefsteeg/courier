class_name RestBed
extends Node3D
## A bed the courier may rest in (Phase 8, Granny Hollis's spare bed): "[E] Rest in the
## bed" restores full health and leaves the courier standing beside it. Refused at full
## health ("You're not tired."). Needs an Interactable child.

signal rested(healed: float)

var interactable: Interactable


func _ready() -> void:
	for child in get_children():
		if child is Interactable:
			interactable = child
	if interactable == null:
		return
	interactable.prompt_verb = "Rest in"
	interactable.display_name = "the bed"
	interactable.interacted.connect(rest)


## Heals the courier to full. Returns the health restored (0 when there was nothing to heal).
func rest(interactor: Node = null) -> float:
	var health := CombatHealth.find_on(interactor) if interactor != null else null
	if health == null:
		var combat := CombatController.find_on(interactor)
		health = combat.health if combat != null else null
	if health == null or health.is_dead():
		return 0.0
	var healed := health.heal(health.get_max_health())
	var notices := get_tree().root.find_children("*", "QuestNotification", true, false)
	if not notices.is_empty():
		(notices[0] as QuestNotification).push_message("You rest a while and feel restored (+%d HP)." % roundi(healed) if healed > 0.0 else "You're not tired.", QuestNotification.KIND_INFO)
	rested.emit(healed)
	return healed
