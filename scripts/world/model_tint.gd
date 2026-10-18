class_name ModelTint
extends Node
## Recolours the imported Quaternius models under its parent by material name.
## The FBX files keep their Blender material names ("RoofTiles", "Windows",
## "Liquid_Red", ...), so a prop can repaint just its roof or make its windows
## glow. Materials not listed keep their imported colour.

## Material name -> albedo colour.
@export var colors: Dictionary = {}
## Material name -> emission colour (also used as albedo).
@export var glow: Dictionary = {}
@export_range(0.0, 16.0, 0.1) var glow_energy: float = 2.0

## Shared tinted materials, so identical tints batch together.
static var _cache: Dictionary = {}


func _ready() -> void:
	apply(get_parent(), colors, glow, glow_energy)


static func apply(root: Node, tint_colors: Dictionary, tint_glow: Dictionary, energy: float) -> void:
	if tint_colors.is_empty() and tint_glow.is_empty():
		return
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
			if source == null:
				continue
			var key := source.resource_name
			if tint_colors.has(key) or tint_glow.has(key):
				mesh_instance.set_surface_override_material(surface, tinted(source, tint_colors.get(key), tint_glow.get(key), energy))


static func tinted(source: BaseMaterial3D, color: Variant, emission: Variant, energy: float) -> BaseMaterial3D:
	var cache_key := "%d|%s|%s|%.2f" % [source.get_instance_id(), color, emission, energy]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var material := source.duplicate() as BaseMaterial3D
	if color is Color:
		material.albedo_color = color
	if emission is Color:
		material.albedo_color = emission
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = energy
	_cache[cache_key] = material
	return material
