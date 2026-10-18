class_name PackageCarrier
extends Node3D
## Player component that holds at most one PackageInstance and shows its visual.
## Place it on the player where the package should appear (e.g. above the head).

signal carried_package_changed(package: PackageInstance)
signal package_picked_up(package: PackageInstance)
signal package_dropped(package: PackageInstance)
## Package left the game: delivered or confiscated (quest failed).
signal package_removed(package: PackageInstance, reason: StringName)
signal pickup_blocked(package: PackageInstance, reason: String)

## Scene spawned when a package is dropped. Root must be a PackagePickup.
@export var dropped_pickup_scene: PackedScene
## Ground offset (relative to the owning body) where dropped packages land.
@export var drop_offset: Vector3 = Vector3(0.0, 0.0, 0.9)
@export var input_enabled: bool = true
## Tick the carried package's mechanic every physics frame (see advance_package()).
@export var simulate_mechanics: bool = true
## Temperature the carried package drifts toward. Heat/cold zones may change it at runtime.
@export var ambient_temperature: float = 20.0
## Impact force applied to a package when it is dropped (0 = drops are harmless).
@export_range(0.0, 100.0, 0.5) var drop_impact_force: float = 0.0
## Movement faster than this (m/s) between two ticks is treated as a teleport and ignored.
@export var max_tracked_speed: float = 20.0
## Fail the package's quest via QuestManager when the carried package is destroyed.
@export var fail_quest_on_destroyed: bool = true

var _package: PackageInstance = null
var _visual: Node3D = null
var _quest_manager: QuestManager = null
var _last_position: Vector3 = Vector3.ZERO
var _has_last_position: bool = false


func _ready() -> void:
	_connect_quest_manager.call_deferred()


func _connect_quest_manager() -> void:
	_quest_manager = QuestManager.find(get_tree())
	if _quest_manager != null:
		_quest_manager.quest_failed.connect(_on_quest_failed)


func _unhandled_input(event: InputEvent) -> void:
	var body := get_parent()
	if body is PlayerController and not (body as PlayerController).input_enabled:
		return
	if input_enabled and is_carrying() and event.is_action_pressed(&"drop_package"):
		drop_package()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if simulate_mechanics and is_carrying():
		advance_package(delta)


## Advances the carried package by delta seconds, using the carrier's movement since
## the previous call as speed. The first call after a pickup counts as standing still.
func advance_package(delta: float) -> void:
	if not is_carrying() or delta <= 0.0:
		return
	var current := global_position if is_inside_tree() else position
	var speed := 0.0
	if _has_last_position:
		speed = current.distance_to(_last_position) / delta
		if speed > max_tracked_speed:
			speed = 0.0
	_last_position = current
	_has_last_position = true
	_package.tick(delta, speed, ambient_temperature)


## Finds the carrier on a node (e.g. the interactor passed to Interactable.interacted).
static func find_on(node: Node) -> PackageCarrier:
	if node == null:
		return null
	if node is PackageCarrier:
		return node
	for child in node.get_children():
		if child is PackageCarrier:
			return child
	return null


func is_carrying() -> bool:
	return _package != null


func get_package() -> PackageInstance:
	return _package


func pick_up(package: PackageInstance) -> bool:
	if package == null:
		return false
	if is_carrying():
		pickup_blocked.emit(package, "Your hands are full. Drop the %s first." % _package.definition.package_name)
		return false
	_package = package
	_has_last_position = false
	package.destroyed.connect(_on_package_destroyed)
	_show_visual()
	package_picked_up.emit(package)
	carried_package_changed.emit(package)
	return true


## Drops the carried package into the world as a PackagePickup. Returns the spawned pickup.
func drop_package() -> PackagePickup:
	if not is_carrying():
		return null
	var package := _package
	_clear()
	var pickup: PackagePickup = null
	if dropped_pickup_scene != null:
		pickup = dropped_pickup_scene.instantiate() as PackagePickup
		pickup.package_instance = package
		var body := get_parent() as Node3D
		var world_parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
		world_parent.add_child(pickup)
		var origin := body.global_transform if body != null else global_transform
		pickup.global_position = origin.origin + origin.basis * drop_offset
	# After spawning, so a package destroyed by the fall is handled by its pickup.
	package.apply_impact(drop_impact_force)
	package_dropped.emit(package)
	carried_package_changed.emit(null)
	return pickup


## Removes the package from play (successful delivery, confiscation).
func remove_package(reason: StringName = &"delivered") -> PackageInstance:
	if not is_carrying():
		return null
	var package := _package
	_clear()
	package_removed.emit(package, reason)
	carried_package_changed.emit(null)
	return package


func _show_visual() -> void:
	var scene := _package.definition.package_scene
	if scene != null:
		_visual = scene.instantiate() as Node3D
		add_child(_visual)


func _clear() -> void:
	if _package != null and _package.destroyed.is_connected(_on_package_destroyed):
		_package.destroyed.disconnect(_on_package_destroyed)
	_package = null
	_has_last_position = false
	if _visual != null:
		_visual.queue_free()
		_visual = null


func _on_quest_failed(quest_id: StringName, _reason: String) -> void:
	if is_carrying() and _package.get_quest_id() == quest_id:
		remove_package(&"quest_failed")


## Fails the quest (which confiscates the package via _on_quest_failed); if no quest
## took it, the package is removed with reason &"destroyed".
func _on_package_destroyed(_reason: StringName) -> void:
	if not is_carrying():
		return
	var package := _package
	if fail_quest_on_destroyed and _quest_manager != null:
		_quest_manager.fail_quest(package.get_quest_id(), package.get_destroyed_message())
	if _package == package:
		remove_package(&"destroyed")
