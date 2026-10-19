@tool
class_name RiverWater
extends Pond
## Fishable river water (Phase 8): the river is already drawn by its level (a carved
## channel, a water plane), so this adds no geometry; it only tells the fishing rod where
## open water is. The river is the strip within half_width of the centreline `points`
## (local XZ; y is ignored), so the rod casts from any bank and FishingSpots can point at
## it. Fish lists and get_water_y() come from Pond.

## Centreline in local space, in order along the river.
@export var points: PackedVector3Array = PackedVector3Array()
## Half the width of open water (metres from the centreline).
@export_range(0.5, 20.0, 0.1, "suffix:m") var half_width: float = 1.8


func _rebuild() -> void:
	pass


func is_open_water(world_point: Vector3, margin: float = 0.4) -> bool:
	var local := to_local(world_point)
	return distance_to_centreline(Vector2(local.x, local.z)) <= half_width - margin


## XZ distance (local) from the centreline.
func distance_to_centreline(flat: Vector2) -> float:
	var best := INF
	for i in points.size() - 1:
		var a := Vector2(points[i].x, points[i].z)
		var b := Vector2(points[i + 1].x, points[i + 1].z)
		best = minf(best, flat.distance_to(Geometry2D.get_closest_point_to_segment(flat, a, b)))
	return best
