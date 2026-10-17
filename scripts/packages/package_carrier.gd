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

var _package: PackageInstance = null
var _visual: Node3D = null
var _quest_manager: QuestManager = null


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
	_package = null
	if _visual != null:
		_visual.queue_free()
		_visual = null


func _on_quest_failed(quest_id: StringName, _reason: String) -> void:
	if is_carrying() and _package.get_quest_id() == quest_id:
		remove_package(&"quest_failed")
