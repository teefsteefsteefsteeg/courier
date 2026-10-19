class_name TeleportPortal
extends Node3D
## A teleport portal: an old stone arch whose swirl, rune circle, motes and light wake up
## once the courier activates it. It is also a location in the shared registry (its
## WorldLocation child, kind PORTAL, same id), so the map, the banner and fast travel use
## the same name.
##
## Interaction (the usual E prompt): an inactive portal is activated on the spot (the
## courier has to be here the first time); an active one opens the TeleportMenu to travel
## to another active portal. Activation is saved by the ExplorationService. Arriving
## travellers land on SpawnPoint, and the portal ignores interaction for arrival_lock
## seconds so a trip can never chain into another.

signal activated

const GROUP := &"teleport_portals"

@export var portal_id: StringName
@export var display_name: String = "Portal"
@export var subtitle: String = ""
@export_range(0.0, 5.0, 0.1, "suffix:s") var arrival_lock: float = 1.2

@onready var interactable: Interactable = $Interactable
@onready var location: WorldLocation = $Location
@onready var spawn_point: Marker3D = $SpawnPoint
@onready var swirl: MeshInstance3D = $Swirl
@onready var runes: MeshInstance3D = $Runes
@onready var motes: GPUParticles3D = $Motes
@onready var light: OmniLight3D = $Light

var _lock_left := 0.0
var _burst := 0.0
var _service: ExplorationService = null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	location.location_id = portal_id
	location.display_name = display_name
	location.subtitle = subtitle
	location.kind = WorldLocation.Kind.PORTAL
	interactable.interacted.connect(_on_interacted)
	_bind.call_deferred()
	_apply_state()


func _bind() -> void:
	_service = ExplorationService.find(get_tree())
	if _service != null and not _service.portal_activated.is_connected(_on_portal_activated):
		_service.portal_activated.connect(_on_portal_activated)
	_apply_state()


static func find(tree: SceneTree, id: StringName) -> TeleportPortal:
	for node in tree.get_nodes_in_group(GROUP):
		if (node as TeleportPortal).portal_id == id:
			return node as TeleportPortal
	return null


func is_active() -> bool:
	return _service != null and _service.is_portal_active(portal_id)


## Where an arriving courier stands: in front of the arch, on the ground.
func get_arrival_position() -> Vector3:
	return spawn_point.global_position


## Called by FastTravel when someone lands here.
func lock_arrival() -> void:
	_lock_left = arrival_lock


func is_locked() -> bool:
	return _lock_left > 0.0


func _process(delta: float) -> void:
	_lock_left = maxf(_lock_left - delta, 0.0)
	if _burst > 0.0:
		_burst = maxf(_burst - delta * 1.2, 0.0)
		_apply_power()


func _on_interacted(interactor: Node) -> void:
	if is_locked() or _service == null:
		return
	if not is_active():
		if _service.activate_portal(portal_id):
			_burst = 1.0
			activated.emit()
			var banner := get_tree().get_first_node_in_group(LocationBanner.GROUP) as LocationBanner
			if banner != null:
				banner.show_notice("TELEPORT UNLOCKED", display_name, subtitle)
		return
	var menu := get_tree().get_first_node_in_group(TeleportMenu.GROUP) as TeleportMenu
	if menu != null:
		menu.open(self, interactor)


func _on_portal_activated(id: StringName) -> void:
	if id == portal_id:
		_apply_state()


func _apply_state() -> void:
	if not is_node_ready():
		return
	var active := is_active()
	interactable.prompt_verb = "Travel from" if active else "Activate"
	interactable.display_name = display_name
	motes.emitting = active
	light.visible = active
	_apply_power()


func _apply_power() -> void:
	var active := is_active()
	var power := (1.0 if active else 0.0) + _burst * 1.2
	(swirl.material_override as ShaderMaterial).set_shader_parameter(&"power", power)
	(runes.material_override as ShaderMaterial).set_shader_parameter(&"power", (0.9 if active else 0.18) + _burst)
	light.light_energy = 1.1 + _burst * 2.5
