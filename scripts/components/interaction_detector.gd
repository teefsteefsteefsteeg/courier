class_name InteractionDetector
extends Area3D
## Tracks Interactable areas overlapping this area and focuses the closest one.
## The overlap of this shape with an Interactable's shape *is* the interaction range.

signal focus_changed(interactable: Interactable)
signal interaction_performed(interactable: Interactable)

var focused: Interactable = null
var _candidates: Array[Interactable] = []


func _ready() -> void:
	monitoring = true
	monitorable = false
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _physics_process(_delta: float) -> void:
	_update_focus()


## Interacts with the focused Interactable, if any. Returns true if something was interacted with.
func try_interact(interactor: Node) -> bool:
	_update_focus()
	if focused == null:
		return false
	focused.interact(interactor)
	interaction_performed.emit(focused)
	return true


func _update_focus() -> void:
	var best: Interactable = null
	var best_distance := INF
	for candidate in _candidates:
		if not is_instance_valid(candidate) or not candidate.enabled:
			continue
		var distance := global_position.distance_squared_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	if best != focused:
		focused = best
		focus_changed.emit(focused)


func _on_area_entered(area: Area3D) -> void:
	if area is Interactable and not _candidates.has(area):
		_candidates.append(area)


func _on_area_exited(area: Area3D) -> void:
	if area is Interactable:
		_candidates.erase(area)
