class_name MedievalBuilding
extends StaticBody3D
## A Medieval Village house with per-instance colours, so one model can dress
## several homes (and the purple-roofed alchemy shop). Transparent colours keep
## the model's own material.

const ROOF_MATERIALS := ["RoofTiles", "RoofTiles_Red"]
const WALL_MATERIALS := ["Plaster", "Beige"]
const WINDOW_MATERIALS := ["Windows"]

@export var roof_color := Color(0, 0, 0, 0)
@export var wall_color := Color(0, 0, 0, 0)
## Emission for window panes (lit interiors). Transparent = unlit.
@export var window_glow := Color(0, 0, 0, 0)
@export_range(0.0, 8.0, 0.1) var window_glow_energy: float = 0.6


func _ready() -> void:
	var colors := {}
	for key in ROOF_MATERIALS:
		if roof_color.a > 0.0:
			colors[key] = roof_color
	for key in WALL_MATERIALS:
		if wall_color.a > 0.0:
			colors[key] = wall_color
	var glow := {}
	for key in WINDOW_MATERIALS:
		if window_glow.a > 0.0:
			glow[key] = window_glow
	ModelTint.apply(self, colors, glow, window_glow_energy)
