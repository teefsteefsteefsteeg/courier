class_name WyrmfallLayout
extends RefCounted
## Phase 8: the layout of Wyrmfall Vale. tools/generate_wyrmfall.gd builds the vale's
## streamed chunks from it, and the tests read the same numbers, so the terrain, water,
## walls and map always agree. Numbers here are in vale space (X east, Z south, metres);
## open world: the vale is part of the one continuous world, its origin at WORLD_ORIGIN,
## north of the Whisperwood. The forest trail enters through the PASS in the southern hills
## (no gate), where the terrain comes down to the forest floor (height 0).
##
##   - lowland of gentle rolling grass inside a ring of hills (walls at +-BOUNDARY)
##   - a plateau PLATEAU_HEIGHT m high north of a cliff (z CLIFF_TOP_Z..CLIFF_BASE_Z); its
##     stream runs south and falls over the lip into the Falls Pool
##   - the Wyrm River leaves the pool to the south-east and crosses the vale
##   - the road from the Willowmere gate (south-west) crosses the river on the Old Stone
##     Bridge and ends at the foot of the cliff in the east (the dungeon's site)

const HALF := 60.0
## Height samples per side (1 m apart, -HALF..HALF).
const GRID := 121
const BOUNDARY := 54.0

const PLATEAU_HEIGHT := 12.0
const CLIFF_TOP_Z := -25.0
const CLIFF_BASE_Z := -21.0

const POOL_CENTRE := Vector2(-6.0, -15.0)
const POOL_RADIUS := 6.0
## Lowland water surface (pool and river).
const WATER_Y := -0.35
## Depth of the pool and the river bed below the water.
const BED_DEPTH := 1.3
const RIVER_HALF_WIDTH := 2.4
## Where the bank meets the surrounding ground (metres from the river centreline).
const RIVER_BANK := 4.6
const RIVER := [Vector2(-6.0, -15.0), Vector2(-3.0, -10.0), Vector2(1.0, -4.0), Vector2(5.0, 3.0), Vector2(10.0, 10.0),
		Vector2(18.0, 19.0), Vector2(27.0, 27.0), Vector2(38.0, 36.0), Vector2(50.0, 43.0), Vector2(64.0, 50.0)]

## Plateau stream, from the hills in the north down to the cliff lip.
const STREAM := [Vector2(-10.0, -58.0), Vector2(-8.0, -48.0), Vector2(-5.0, -38.0), Vector2(-6.0, -30.0), Vector2(-6.0, -24.6)]
const STREAM_HALF_WIDTH := 1.4
const STREAM_WATER_DROP := 0.45
## The waterfall: where the stream goes over, and its width.
const FALLS_X := -6.0
const FALLS_WIDTH := 4.2

## Over the bridge the road runs exactly north-east (x + z = 12), one of the eight keyboard
## directions of the iso camera, so walking across never rubs along a railing.
const ROAD := [Vector2(-40.0, 61.0), Vector2(-40.0, 50.0), Vector2(-40.0, 44.0), Vector2(-36.0, 38.0), Vector2(-28.0, 30.0), Vector2(-17.0, 20.0), Vector2(-6.0, 13.0),
		Vector2(1.0, 11.0), Vector2(11.0, 1.0), Vector2(22.0, -6.0), Vector2(28.0, -13.0), Vector2(31.0, -17.5)]
const ROAD_HALF_WIDTH := 1.7
## Side path from the road to the ruins.
const RUINS_PATH := [Vector2(-17.0, 20.0), Vector2(-22.0, 10.0), Vector2(-27.0, 1.0)]
## Side path from the road to the falls viewpoint on the west bank, below the pool.
const FALLS_PATH := [Vector2(-6.0, 13.0), Vector2(-8.5, 4.0), Vector2(-10.0, -4.0)]
const FALLS_VIEW := Vector2(-10.0, -4.0)
const PATH_HALF_WIDTH := 1.1

const RUINS_CENTRE := Vector2(-29.0, -4.0)
const CAMP_CENTRE := Vector2(-2.0, 25.0)
const ARRIVAL := Vector2(-36.5, 38.5)
const RETURN_GATE := Vector2(-40.5, 44.5)
## Foot of the eastern cliff where the road ends (the dungeon entrance goes here).
const CLIFF_END := Vector2(31.0, -19.0)

const SEED := 8808

## Where vale space (0, 0, 0) is in the world: the pass's south end meets the Whisperwood's
## north edge at world (14, 0, -124).
const WORLD_ORIGIN := Vector3(54.0, 0.0, -184.0)
## The pass through the southern ring of hills (vale space), from the forest edge to the
## old gate clearing; the hills are cut away within PASS_HALF_WIDTH of it.
const PASS := [Vector2(-40.0, 61.0), Vector2(-40.0, 50.0), Vector2(-40.5, 44.5)]
const PASS_HALF_WIDTH := 6.0
## Walkable width of the pass between its walls.
const PASS_OPEN := 4.5


## Vale space -> world.
static func to_world(p: Vector2, y: float = 0.0) -> Vector3:
	return WORLD_ORIGIN + Vector3(p.x, y, p.y)


## World -> vale space (X/Z).
static func to_local(world: Vector3) -> Vector2:
	return Vector2(world.x - WORLD_ORIGIN.x, world.z - WORLD_ORIGIN.z)


## 1 inside the pass corridor, fading to 0 where the hills stand.
static func pass_factor(x: float, z: float) -> float:
	if z < 38.0:
		return 0.0
	var d := polyline_distance(Vector2(x, z), PASS)
	return 1.0 - smoothstep(PASS_HALF_WIDTH, PASS_HALF_WIDTH + 5.0, d)

static var _noise: FastNoiseLite
static var _detail: FastNoiseLite


static func _noises() -> void:
	if _noise != null:
		return
	_noise = FastNoiseLite.new()
	_noise.seed = SEED
	_noise.frequency = 0.035
	_noise.fractal_octaves = 3
	_detail = FastNoiseLite.new()
	_detail.seed = SEED + 1
	_detail.frequency = 0.12


static func polyline_distance(p: Vector2, points: Array) -> float:
	var best := INF
	for i in points.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, points[i], points[i + 1])))
	return best


## Closest point on a polyline.
static func polyline_closest(p: Vector2, points: Array) -> Vector2:
	var best := INF
	var at := Vector2.ZERO
	for i in points.size() - 1:
		var c := Geometry2D.get_closest_point_to_segment(p, points[i], points[i + 1])
		if p.distance_to(c) < best:
			best = p.distance_to(c)
			at = c
	return at


## 0 below the cliff, 1 on the plateau.
static func plateau_factor(x: float, z: float) -> float:
	_noises()
	# The cliff line wavers a little so it doesn't read as a ruler-straight wall.
	var wobble := _detail.get_noise_2d(x * 0.6, 7.0) * 0.6
	return smoothstep(CLIFF_BASE_Z + wobble, CLIFF_TOP_Z + wobble, z)


static func river_distance(p: Vector2) -> float:
	return polyline_distance(p, RIVER)


static func road_distance(p: Vector2) -> float:
	return minf(minf(polyline_distance(p, ROAD) - ROAD_HALF_WIDTH, polyline_distance(p, RUINS_PATH) - PATH_HALF_WIDTH),
			polyline_distance(p, FALLS_PATH) - PATH_HALF_WIDTH)


## Terrain height at (x, z).
static func height(x: float, z: float) -> float:
	_noises()
	var p := Vector2(x, z)
	# Lowland: soft rolls, never below the water's edge.
	var h := 0.45 + _noise.get_noise_2d(x, z) * 1.3 + _detail.get_noise_2d(x, z) * 0.12
	h = maxf(h, 0.2)
	# The road sits a little flatter.
	var road := road_distance(p)
	if road < 1.5:
		h = lerpf(0.35 + _noise.get_noise_2d(x, z) * 0.5, h, smoothstep(-0.5, 1.5, road))
	# Plateau and cliff.
	var plateau := plateau_factor(x, z)
	h += plateau * (PLATEAU_HEIGHT - 0.4 + _noise.get_noise_2d(x * 0.7 + 40.0, z * 0.7) * 0.8 - h * 0.5)
	# Ring of hills, cut away along the pass.
	var edge := maxf(absf(x), absf(z))
	var gap := pass_factor(x, z)
	h += smoothstep(BOUNDARY - 6.0, HALF, edge) * (7.0 + _noise.get_noise_2d(x + 90.0, z) * 3.0) * (1.0 - gap)
	# The pass comes down to the forest floor (height 0) at the vale's south edge.
	if gap > 0.0:
		h = lerpf(h, 0.0, gap * smoothstep(50.0, HALF, z))
	# Plateau stream channel.
	if plateau > 0.5:
		var s := polyline_distance(p, STREAM)
		if s < STREAM_HALF_WIDTH + 1.6:
			var bed := PLATEAU_HEIGHT - 1.1
			h = lerpf(bed, h, smoothstep(STREAM_HALF_WIDTH - 0.6, STREAM_HALF_WIDTH + 1.6, s))
	else:
		# Pool and river (carved below the water).
		var bed := WATER_Y - BED_DEPTH
		var pool := p.distance_to(POOL_CENTRE)
		if pool < POOL_RADIUS + 2.5:
			h = lerpf(bed, h, smoothstep(POOL_RADIUS - 2.0, POOL_RADIUS + 2.5, pool))
		var river := river_distance(p)
		if river < RIVER_BANK:
			h = lerpf(bed, h, smoothstep(RIVER_HALF_WIDTH - 1.0, RIVER_BANK, river))
	return h


static func is_water(p: Vector2) -> bool:
	if plateau_factor(p.x, p.y) > 0.5:
		return polyline_distance(p, STREAM) < STREAM_HALF_WIDTH
	return p.distance_to(POOL_CENTRE) < POOL_RADIUS or river_distance(p) < RIVER_HALF_WIDTH


## Where the road crosses the river, and the road's direction there.
static func bridge_point() -> Vector2:
	for i in ROAD.size() - 1:
		for j in RIVER.size() - 1:
			var hit: Variant = Geometry2D.segment_intersects_segment(ROAD[i], ROAD[i + 1], RIVER[j], RIVER[j + 1])
			if hit != null:
				return hit
	return Vector2.ZERO


static func bridge_direction() -> Vector2:
	var at := bridge_point()
	for i in ROAD.size() - 1:
		var a: Vector2 = ROAD[i]
		var b: Vector2 = ROAD[i + 1]
		if at.distance_to(Geometry2D.get_closest_point_to_segment(at, a, b)) < 0.01:
			return (b - a).normalized()
	return Vector2.RIGHT
