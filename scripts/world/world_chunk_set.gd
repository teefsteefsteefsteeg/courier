class_name WorldChunkSet
extends Resource
## The chunks one generator made for one biome (e.g. data/world/wyrmfall_chunks.tres from
## tools/generate_wyrmfall.gd). WorldStreamer streams every chunk of every set it is given.

@export var biome: StringName = &""
@export var chunks: Array[WorldChunk] = []
