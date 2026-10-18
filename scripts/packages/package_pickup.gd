class_name PackagePickup
extends Node3D
## A package lying in the world that the player can pick up with E.
##
## Two modes:
## - Source (package_definition set, package_instance null): a pickup point, e.g. at the
##   post office. Only visible while a quest's current objective is to pick it up.
## - Dropped (package_instance set by PackageCarrier): always available until picked up;
##   freed if its quest fails.

signal picked_up(package: PackageInstance)

@export var package_definition: PackageDefinition
## Source mode only: hide unless an in-progress quest needs this package picked up.
@export var only_when_quest_needs: bool = true
## Dropped mode only: keep ticking the package's mechanic (speed 0) while it lies here.
@export var simulate_while_dropped: bool = true
## Temperature a dropped package drifts toward.
@export var ambient_temperature: float = 20.0

var package_instance: PackageInstance = null

@onready var interactable: Interactable = $Interactable
@onready var visual_root: Node3D = $VisualRoot

var _quest_manager: QuestManager = null


func _ready() -> void:
	if package_instance != null:
		package_definition = package_instance.definition
		package_instance.destroyed.connect(_on_package_destroyed)
	if package_definition == null:
		push_error("PackagePickup %s has no package" % name)
		return
	interactable.prompt_verb = "Pick up"
	interactable.display_name = package_definition.package_name
	interactable.interacted.connect(_on_interacted)
	if package_definition.package_scene != null:
		visual_root.add_child(package_definition.package_scene.instantiate())
	_quest_manager = QuestManager.find(get_tree())
	if _quest_manager != null:
		_quest_manager.quest_state_changed.connect(_on_quest_state_changed)
		_quest_manager.objective_completed.connect(_on_objective_completed)
	_refresh()


func _physics_process(delta: float) -> void:
	if simulate_while_dropped and is_dropped() and not is_queued_for_deletion():
		package_instance.tick(delta, 0.0, ambient_temperature)


func is_dropped() -> bool:
	return package_instance != null


func is_available() -> bool:
	return interactable.enabled


func _on_interacted(interactor: Node) -> void:
	var carrier := PackageCarrier.find_on(interactor)
	if carrier == null or not is_available():
		return
	var package := package_instance if is_dropped() else PackageInstance.new(package_definition)
	if not carrier.pick_up(package):
		return
	picked_up.emit(package)
	if is_dropped():
		if package_instance.destroyed.is_connected(_on_package_destroyed):
			package_instance.destroyed.disconnect(_on_package_destroyed)
		queue_free()
	else:
		# Report after hiding so listeners see a consistent world.
		_set_available(false)
		if _quest_manager != null:
			_quest_manager.notify_package_picked_up(package_definition.package_id)


func _refresh() -> void:
	if is_dropped():
		_set_available(true)
	elif not only_when_quest_needs:
		_set_available(true)
	else:
		_set_available(_quest_manager != null and _quest_manager.is_package_pickup_pending(package_definition.package_id))


func _set_available(value: bool) -> void:
	interactable.enabled = value
	visible = value


func _on_quest_state_changed(quest_id: StringName, new_status: QuestState.Status, _old: QuestState.Status) -> void:
	if is_dropped() and quest_id == package_instance.get_quest_id() and new_status == QuestState.Status.FAILED:
		queue_free()
		return
	_refresh()


func _on_objective_completed(_quest_id: StringName, _index: int) -> void:
	_refresh()


## A dropped package was ruined/exploded on the ground: fail its quest and disappear.
func _on_package_destroyed(_reason: StringName) -> void:
	if _quest_manager != null:
		_quest_manager.fail_quest(package_instance.get_quest_id(), package_instance.get_destroyed_message())
	if not is_queued_for_deletion():
		queue_free()
