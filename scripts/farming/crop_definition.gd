class_name CropDefinition
extends Resource
## One crop the courier can grow in a FarmPlot (authored as .tres in res://data/crops/).
## Planting uses one `seed_item`; the crop passes `stage_count` growth stages of `stage_seconds`
## each (play time, see FarmService) and then pays yield_min..yield_max of `produce`.
## crop_id is saved: never rename a shipped id.

@export var crop_id: StringName
@export var display_name: String = ""
@export var seed_item: MaterialItem
@export var produce: MaterialItem
@export_range(1, 20) var yield_min: int = 2
@export_range(1, 20) var yield_max: int = 3
## Growth stages after planting; the crop is ripe after the last one.
@export_range(1, 6) var stage_count: int = 3
@export_range(1.0, 3600.0, 1.0, "suffix:s") var stage_seconds: float = 40.0
## The ripe plant; earlier stages show it smaller (FarmPlot.STAGE_SCALES).
@export var model: PackedScene
## Uniform scale of the ripe model in the bed.
@export var model_scale: float = 1.0
## Plants in one bed: 9 (three rows of three) or 3 (big crops, the middle row only).
@export_enum("3:3", "9:9") var plants_per_bed: int = 9


func get_grow_seconds() -> float:
	return stage_count * stage_seconds
