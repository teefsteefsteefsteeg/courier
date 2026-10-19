class_name FarmPlot
extends Node3D
## One raised garden bed (Phase 7 farming). It holds no state of its own: FarmService says
## what grows here and how far along it is, and this node shows it and turns the courier's
## interaction into planting or harvesting.
##   empty    "[E] Plant Wheat Seeds (4)": plants the selected seed (FarmService.preferred
##            seed when carried, else the first crop the courier has seeds for)
##   growing  "Wheat · ripe in 0:40": the plants grow through the crop's stages
##   ripe     "[E] Harvest Wheat": produce into the inventory, the bed is empty again
## Messages go to the quest toasts (QuestNotification).

## Saved in FarmService: unique per bed, never rename a shipped id.
@export var plot_id: StringName
@export var display_name: String = "Garden Bed"

const SEEDLING := preload("res://assets/generated/phase7/crop_seedling.glb")
## Height of the soil ridges in garden_bed.glb.
const SOIL_HEIGHT := 0.28
## Plant scale per stage before ripe (the seedling model shows stage 0).
const STAGE_SCALES := [0.0, 0.45, 0.75]
const SPOTS_9 := [Vector2(-0.6, -0.49), Vector2(0, -0.49), Vector2(0.6, -0.49), Vector2(-0.6, 0), Vector2(0, 0),
		Vector2(0.6, 0), Vector2(-0.6, 0.49), Vector2(0, 0.49), Vector2(0.6, 0.49)]
const SPOTS_3 := [Vector2(-0.55, 0), Vector2(0, 0), Vector2(0.55, 0)]

var interactable: Interactable
var plants: Node3D
var _service: FarmService
var _shown_crop: StringName = &""
var _shown_stage: int = -2


func _ready() -> void:
	interactable = get_node_or_null(^"Interactable") as Interactable
	plants = get_node_or_null(^"Plants") as Node3D
	if plants == null:
		plants = Node3D.new()
		plants.name = "Plants"
		add_child(plants)
	if interactable != null:
		interactable.display_name = display_name
		interactable.interacted.connect(_on_interacted)
	_bind.call_deferred()


func _bind() -> void:
	_service = FarmService.find(get_tree())
	if _service != null:
		_service.plot_changed.connect(func(id: StringName) -> void:
			if id == plot_id:
				refresh())
		_service.stage_changed.connect(func(id: StringName, _stage: int) -> void:
			if id == plot_id:
				refresh())
	refresh()


func get_service() -> FarmService:
	return _service


## The crop the courier would plant here now, or null when they carry no seeds.
func get_seed_choice(interactor: Node) -> CropDefinition:
	var inventory := CourierInventory.find(get_tree())
	if _service == null or inventory == null:
		return null
	var preferred := _service.crop_for_seed(_service.preferred_seed)
	if preferred != null and inventory.get_material_count(preferred.seed_item.material_id) > 0:
		return preferred
	for crop in _service.get_crops():
		if inventory.get_material_count(crop.seed_item.material_id) > 0:
			return crop
	return null


func get_interaction_prompt(interactor: Node) -> String:
	if _service == null:
		return ""
	var crop := _service.get_planted_crop(plot_id)
	if crop == null:
		var choice := get_seed_choice(interactor)
		if choice == null:
			return "%s · empty, buy seeds from the Toolwright" % display_name
		var inventory := CourierInventory.find(get_tree())
		return "Plant %s (%d)" % [choice.seed_item.display_name, inventory.get_material_count(choice.seed_item.material_id)]
	if _service.is_ripe(plot_id):
		return "Harvest %s" % crop.display_name
	return "%s · ripe in %s" % [crop.display_name, ToolTarget.format_time(_service.seconds_until_ripe(plot_id))]


func _on_interacted(interactor: Node) -> void:
	if _service == null:
		return
	var inventory := CourierInventory.find(get_tree())
	var crop := _service.get_planted_crop(plot_id)
	if crop == null:
		var choice := get_seed_choice(interactor)
		if choice == null:
			_say("You have no seeds. The Toolwright sells them.", QuestNotification.KIND_WARNING)
			return
		var result := _service.plant(plot_id, choice.crop_id, inventory)
		_say(FarmService.plant_result_text(result, choice), QuestNotification.KIND_SUCCESS if result == FarmService.PlantResult.OK else QuestNotification.KIND_WARNING)
	elif _service.is_ripe(plot_id):
		var added := _service.harvest(plot_id, inventory)
		if added > 0:
			_say("Harvested +%d %s." % [added, crop.produce.display_name], QuestNotification.KIND_SUCCESS)
		else:
			_say("Your %s stack is full; sell some to the Toolwright." % crop.produce.display_name, QuestNotification.KIND_WARNING)
	else:
		_say("%s: ripe in %s." % [crop.display_name, ToolTarget.format_time(_service.seconds_until_ripe(plot_id))], QuestNotification.KIND_INFO)


## Rebuilds the plants for the current crop and stage.
func refresh() -> void:
	var crop := _service.get_planted_crop(plot_id) if _service != null else null
	var stage := _service.get_stage(plot_id) if crop != null else -1
	var crop_id: StringName = crop.crop_id if crop != null else &""
	if crop_id == _shown_crop and stage == _shown_stage:
		return
	var grew := crop_id == _shown_crop and stage > _shown_stage
	_shown_crop = crop_id
	_shown_stage = stage
	for child in plants.get_children():
		plants.remove_child(child)
		child.queue_free()
	if crop == null:
		return
	var spots: Array = SPOTS_3 if crop.plants_per_bed == 3 else SPOTS_9
	var ripe := stage >= crop.stage_count
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(plot_id)
	for spot: Vector2 in spots:
		# The model goes in a holder: imported crops keep their own root transform (the
		# Quaternius FBX roots are Z-up and in centimetres).
		var plant := Node3D.new()
		var scale := 1.0
		if stage == 0:
			plant.add_child(SEEDLING.instantiate())
		else:
			plant.add_child(crop.model.instantiate())
			scale = crop.model_scale * (1.0 if ripe else float(STAGE_SCALES[mini(stage, STAGE_SCALES.size() - 1)]))
		plant.position = Vector3(spot.x + rng.randf_range(-0.05, 0.05), SOIL_HEIGHT, spot.y + rng.randf_range(-0.04, 0.04))
		plant.rotation.y = rng.randf() * TAU
		plant.scale = Vector3.ONE * scale
		plants.add_child(plant)
		if grew and is_inside_tree():
			# A small pop as the plants reach the next stage.
			plant.scale = Vector3.ONE * scale * 0.8
			create_tween().tween_property(plant, ^"scale", Vector3.ONE * scale, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func get_plant_count() -> int:
	return plants.get_child_count()


func _say(text: String, kind: StringName) -> void:
	for node in get_tree().root.find_children("*", "QuestNotification", true, false):
		(node as QuestNotification).push_message(text, kind)
		return
