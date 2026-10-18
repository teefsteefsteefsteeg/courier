class_name Phase3Showcase
extends Node3D
## A permanent post-office exhibit for evaluating the two magical delivery types.
## It does not alter quest availability, pickups, or rewards.  Interacting with
## the placard switches the existing gameplay HUD between the live egg and crate.

@export var dragon_egg_definition: PackageDefinition
@export var potion_crate_definition: PackageDefinition
@export var cycle_seconds := 8.0

@onready var interactable: Interactable = $Interactable
@onready var egg_visual: DragonEggVisualFX = $DragonEgg
@onready var potion_visual: PotionCrateVisualFX = $PotionCrate
@onready var status_label: Label3D = $StatusLabel

var _egg: PackageInstance
var _potion: PackageInstance
var _showing_egg := true
var _time := 0.0
var _hud: PackageStatusHUD


func _ready() -> void:
	_egg = PackageInstance.new(dragon_egg_definition)
	_potion = PackageInstance.new(potion_crate_definition)
	egg_visual.bind_package(_egg)
	potion_visual.bind_package(_potion)
	interactable.interacted.connect(_on_interacted)
	_hud = _find_scene_root().get_node_or_null("GameplayHUD/PackageStatusHUD") as PackageStatusHUD
	# GameplayHUD initializes later in the village scene and clears its initial
	# empty carrier binding, so bind after the whole scene has entered the tree.
	_show_selected_package.call_deferred()


func _process(delta: float) -> void:
	_time += delta
	# Make both effects obvious while preserving their real PackageInstance API.
	_egg.set_temperature(60.0 + 32.0 * sin(_time * TAU / cycle_seconds))
	_potion.set_instability(57.0 + 38.0 * sin(_time * TAU / (cycle_seconds * 0.72)))
	_update_label()


func _on_interacted(_interactor: Node) -> void:
	_showing_egg = not _showing_egg
	_show_selected_package()


func _show_selected_package() -> void:
	if _hud != null:
		_hud.bind_package(_egg if _showing_egg else _potion)
	interactable.display_name = "Arcane Cargo Exhibit — %s (press E to switch)" % ("Dragon Egg" if _showing_egg else "Volatile Potion")
	_update_label()


func _update_label() -> void:
	if _showing_egg:
		status_label.text = "ARCANE CARGO EXHIBIT\nDragon Egg  %d°\n[E] View potion crate" % roundi(_egg.get_temperature())
	else:
		status_label.text = "ARCANE CARGO EXHIBIT\nVolatile Potion  %d%% unstable\n[E] View dragon egg" % roundi(_potion.get_instability())


func _find_scene_root() -> Node:
	var node: Node = self
	while node.get_parent() != null and node.get_parent() != get_tree().root:
		node = node.get_parent()
	return node
