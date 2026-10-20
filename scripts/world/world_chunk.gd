class_name WorldChunk
extends Resource
## One streamable piece of the open world (Phase 8): a scene whose root carries its own
## world transform, the ground rectangle it covers (world X/Z) and whether it must always be
## loaded (light content other systems rely on: landmarks for the map, water). WorldStreamer
## loads it near the courier and parks it (out of the tree, state kept) when far away.
## Generators write these (e.g. tools/generate_wyrmfall.gd -> WorldChunkSet).

@export var chunk_id: StringName
@export_file("*.tscn") var scene_path: String = ""
## Ground area the chunk covers, world X/Z.
@export var bounds: Rect2
@export var always_loaded: bool = false
## Biome / region name for the map and debugging ("wyrmfall", "whisperwood", ...).
@export var biome: StringName = &""


## Distance on the ground from a world X/Z point to the chunk (0 inside it).
func distance_to(point: Vector2) -> float:
	var closest := Vector2(clampf(point.x, bounds.position.x, bounds.end.x), clampf(point.y, bounds.position.y, bounds.end.y))
	return point.distance_to(closest)
