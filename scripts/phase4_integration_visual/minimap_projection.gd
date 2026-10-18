extends RefCounted
## Pure math for the Phase 4 minimap: projects world X/Z onto a 2D map and back.
## Map space is in pixels with the origin at the map's top-left corner, +x to the
## right and +y down, so the result can be drawn directly by a Control.
##
## Orientation: `right_axis` is the world X/Z direction that points to map-right.
## Map-down is that axis rotated +90 degrees. With the default (1, 0), world +X is
## right and world +Z is down (north-up, -Z = north). match_camera() lines the map
## up with what the player sees on screen.

var center := Vector2.ZERO  ## world (x, z) shown at the middle of the map
var world_radius := 30.0  ## metres from the centre to the nearest map edge
var map_size := Vector2(200, 200)  ## pixels
var right_axis := Vector2(1, 0)  ## unit world (x, z) direction drawn as map-right
var circular := false  ## clamp/inside tests use a circle instead of the rectangle


func get_down_axis() -> Vector2:
	return Vector2(-right_axis.y, right_axis.x)


## yaw in radians around +Y, same convention as Node3D.rotation.y.
func set_yaw(yaw: float) -> void:
	right_axis = Vector2(cos(yaw), -sin(yaw))


func get_yaw() -> float:
	return atan2(-right_axis.y, right_axis.x)


## Lines the map up with a camera: camera-right on screen becomes map-right.
## Returns false (and keeps the old orientation) for a camera looking straight
## along its own right axis, which cannot happen for a normal game camera.
func match_camera(camera_basis: Basis) -> bool:
	var r := Vector2(camera_basis.x.x, camera_basis.x.z)
	if r.length_squared() < 0.0001:
		return false
	right_axis = r.normalized()
	return true


func set_center_world(world: Vector3) -> void:
	center = Vector2(world.x, world.z)


func get_half_size() -> Vector2:
	return map_size * 0.5


func get_pixels_per_meter() -> float:
	return minf(map_size.x, map_size.y) * 0.5 / maxf(world_radius, 0.001)


func world_to_map(world: Vector3) -> Vector2:
	return world_xz_to_map(Vector2(world.x, world.z))


func world_xz_to_map(xz: Vector2) -> Vector2:
	var d := xz - center
	return get_half_size() + Vector2(d.dot(right_axis), d.dot(get_down_axis())) * get_pixels_per_meter()


func map_to_world(point: Vector2, height := 0.0) -> Vector3:
	var local := (point - get_half_size()) / get_pixels_per_meter()
	var xz := center + right_axis * local.x + get_down_axis() * local.y
	return Vector3(xz.x, height, xz.y)


## A world-space direction (only X/Z are used) as a unit map direction.
func direction_to_map(world_direction: Vector3) -> Vector2:
	var d := Vector2(world_direction.x, world_direction.z)
	if d.length_squared() < 0.000001:
		return Vector2.ZERO
	return Vector2(d.dot(right_axis), d.dot(get_down_axis())).normalized()


func is_inside(point: Vector2, margin := 0.0) -> bool:
	var o := point - get_half_size()
	if circular:
		var r := minf(map_size.x, map_size.y) * 0.5 - margin
		return o.length_squared() <= r * r
	var h := get_half_size() - Vector2(margin, margin)
	return absf(o.x) <= h.x and absf(o.y) <= h.y


## Pulls a point back along the ray from the map centre until it sits `margin`
## pixels inside the edge. Points already inside are returned unchanged.
func clamp_to_edge(point: Vector2, margin := 0.0) -> Vector2:
	var half := get_half_size()
	var o := point - half
	if o.length_squared() < 0.000001:
		return point
	if circular:
		var r := maxf(minf(half.x, half.y) - margin, 0.0)
		return half + o.limit_length(r)
	var h := Vector2(maxf(half.x - margin, 0.0), maxf(half.y - margin, 0.0))
	var t := 1.0
	if absf(o.x) > h.x:
		t = minf(t, h.x / absf(o.x))
	if absf(o.y) > h.y:
		t = minf(t, h.y / absf(o.y))
	return half + o * t


## Map outline as a closed polygon (used for clipping polylines).
func get_outline(margin := 0.0, segments := 40) -> PackedVector2Array:
	var half := get_half_size()
	var out := PackedVector2Array()
	if circular:
		var r := maxf(minf(half.x, half.y) - margin, 0.0)
		for i in segments:
			out.append(half + Vector2.from_angle(TAU * float(i) / float(segments)) * r)
		return out
	out.append(Vector2(margin, margin))
	out.append(Vector2(map_size.x - margin, margin))
	out.append(Vector2(map_size.x - margin, map_size.y - margin))
	out.append(Vector2(margin, map_size.y - margin))
	return out


## World X/Z rectangle that covers everything visible on the map.
func get_visible_world_rect() -> Rect2:
	var rect := Rect2(center, Vector2.ZERO)
	for corner in [Vector2.ZERO, Vector2(map_size.x, 0), map_size, Vector2(0, map_size.y)]:
		var w := map_to_world(corner)
		rect = rect.expand(Vector2(w.x, w.z))
	return rect
