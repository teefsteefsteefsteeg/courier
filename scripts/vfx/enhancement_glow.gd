class_name EnhancementGlow
extends Node3D
## The passive enhancement effect of a held weapon (or shield), built under its held model
## so it follows every swing. Phase 8 elemental rework: every weapon class has its own
## element and every level its own composition (not one glow recoloured):
##   SWORD  fire / blade     +1 silver sparks  +2 glowing blade trails  +3 embers running
##                           up the blade  +4 flames wrapping the blade  +5 inferno blade
##                           (fire stream, ember storm, heat flashes)
##   AXE    earth / quake    +1 metallic sparks  +2 falling stones and dust  +3 pulsing earth
##                           runes  +4 orbiting rocks, rubble, twin runes  +5 magma, boulders,
##                           dust rings
##   BOW    wind / lightning +1 breeze  +2 air trails round the string  +3 wind spirals
##                           +4 electric arcs and sparks  +5 thunderstorm (lightning strikes)
##   STAFF  arcane / water   +1 floating motes  +2 rotating rune circles  +3 water orbiting
##                           the tip  +4 orbiting crystals and energy streams  +5 arcane storm
##                           (twin rune rings, warp pulses, crystals)
##   shield (NONE)           the generic tiers (silver spark, nature, water, lightning, legendary)
## Flipbooks come from the Super Pixel Effects Gigapack (assets/vfx/enhancement/, VfxStrip);
## motes, embers, stones, streaks and droplets are CPUParticles3D; rune circles, orbiting
## rocks, droplets and crystals turn on spinners. Passive only: nothing here deals damage
## (attack effects: AttackEffects; the +5 skills: WeaponUltimates).
## EnhancementVisuals creates and removes it.

const TIER_NAMES: Array[String] = ["", "Silver Spark", "Nature Energy", "Water", "Lightning", "Legendary"]
## Element and level names per weapon class, for the inventory and tests.
const WEAPON_TIERS := {
	ItemDefinition.WeaponType.SWORD: ["", "Silver Sparks", "Blade Trails", "Ember Edge", "Wrapped Flames", "Inferno Blade"],
	ItemDefinition.WeaponType.AXE: ["", "Iron Sparks", "Stone Dust", "Earth Runes", "Rockbound", "Earthshaker"],
	ItemDefinition.WeaponType.BOW: ["", "Breeze", "Air Trails", "Wind Spiral", "Charged Arcs", "Thunderstorm"],
	ItemDefinition.WeaponType.STAFF: ["", "Motes", "Rune Circles", "Tidal Orbit", "Arcane Crystals", "Arcane Storm"],
}

## Where effects sit along the grip-to-tip axis (0 = grip, 1 = tip; negative = the other
## side of the grip, for a bow held in the middle), per weapon type.
const SPAN := {
	ItemDefinition.WeaponType.SWORD: Vector2(0.3, 1.0),
	# The battle axe's crescent head runs along the shaft below the hand.
	ItemDefinition.WeaponType.AXE: Vector2(0.15, 0.65),
	ItemDefinition.WeaponType.BOW: Vector2(-0.9, 0.9),
	ItemDefinition.WeaponType.STAFF: Vector2(0.72, 1.0),
	ItemDefinition.WeaponType.NONE: Vector2(0.2, 0.8),
}

const OVER_BODY_PRIORITY := 10
const BOW_SIZE := 1.15
## The bow's top limb is level with the courier's face and its middle with the chest: its
## effects stay below this point of the span (0 = bottom limb, 1 = top limb).
const BOW_TOP := 0.35
const FIRE_SHEET := "res://assets/vfx/boss/fire_8x8.png"

var level: int = 0
var weapon_type: ItemDefinition.WeaponType = ItemDefinition.WeaponType.NONE
## True for a bow's effects, which draw over the courier's body (see _show_over_body).
var shows_over_body := false
## The composition's elements, for tests (e.g. &"sword_flames", &"axe_runes", &"light").
var elements: Array[StringName] = []
## Grip-to-tip axis end in the held model's space (for tests and placement).
var tip: Vector3 = Vector3.ZERO
var strips: Array[VfxStrip] = []
var particles: Array[CPUParticles3D] = []
## Rings, rocks, droplets and crystals (MeshInstance3D / Sprite3D on spinners).
var shapes: Array[GeometryInstance3D] = []
var light: OmniLight3D = null
var _base: Vector3
var _span := Vector2(0.3, 1.0)
var _light_energy := 0.0
var _flicker := 0.0
## [node, local axis, radians per second]
var _spins: Array = []
## [node, base scale, amplitude, frequency]
var _pulses: Array = []

static var _textures: Dictionary = {}


## Builds the effect for an item at item_level (1-5) under held, the held model node (in
## the tree, so its meshes' extent is known). weapon_type picks the element and placement.
## Null at +0.
static func build(held: Node3D, item_level: int, type: ItemDefinition.WeaponType = ItemDefinition.WeaponType.SWORD) -> EnhancementGlow:
	item_level = Enhancement.clamp_level(item_level)
	if held == null or item_level <= 0:
		return null
	var glow := EnhancementGlow.new()
	glow.name = "EnhancementGlow"
	glow.level = item_level
	glow.weapon_type = type
	glow._span = SPAN.get(type, SPAN[ItemDefinition.WeaponType.NONE])
	var box := local_bounds(held)
	var axis := longest_axis(box)
	# The grip is at the model origin; the tip is the far end of the longest axis.
	var near_end := box.position[axis]
	var far_end := box.end[axis]
	var tip_value := far_end if absf(far_end) >= absf(near_end) else near_end
	glow._base = box.get_center()
	glow._base[axis] = 0.0
	glow.tip = glow._base
	glow.tip[axis] = tip_value
	held.add_child(glow)
	glow._populate()
	if type == ItemDefinition.WeaponType.BOW:
		glow._show_over_body()
	return glow


## The name of a weapon class's level (falls back to the generic tier names).
static func tier_name(type: ItemDefinition.WeaponType, item_level: int) -> String:
	var names: Array = WEAPON_TIERS.get(type, TIER_NAMES)
	return names[clampi(item_level, 0, names.size() - 1)]


## A point at t along the weapon's span (0..1 from the span's start to its end).
func along(t: float) -> Vector3:
	return _base.lerp(tip, lerpf(_span.x, _span.y, t))


## Unit grip-to-tip direction in the held model's space.
func axis_direction() -> Vector3:
	return (tip - _base).normalized() if tip != _base else Vector3.UP


## Length of the weapon's span in the held model's space (sizes scale with it).
func span_length() -> float:
	return _base.distance_to(tip) * absf(_span.y - _span.x)


func _populate() -> void:
	match weapon_type:
		ItemDefinition.WeaponType.SWORD:
			[_sword_1, _sword_2, _sword_3, _sword_4, _sword_5][level - 1].call()
		ItemDefinition.WeaponType.AXE:
			[_axe_1, _axe_2, _axe_3, _axe_4, _axe_5][level - 1].call()
		ItemDefinition.WeaponType.BOW:
			[_bow_1, _bow_2, _bow_3, _bow_4, _bow_5][level - 1].call()
		ItemDefinition.WeaponType.STAFF:
			[_staff_1, _staff_2, _staff_3, _staff_4, _staff_5][level - 1].call()
		_:
			[_silver_spark, _nature, _water, _lightning, _legendary][level - 1].call()


func _process(delta: float) -> void:
	_flicker += delta
	for spin: Array in _spins:
		var node := spin[0] as Node3D
		node.rotate(spin[1], float(spin[2]) * delta)
	for pulse: Array in _pulses:
		var node := pulse[0] as Node3D
		node.scale = (pulse[1] as Vector3) * (1.0 + float(pulse[2]) * sin(_flicker * TAU * float(pulse[3])))
	if light != null:
		light.light_energy = _light_energy * (0.8 + 0.2 * sin(_flicker * 23.0) * sin(_flicker * 7.3))


# --- sword: fire / blade energy -----------------------------------------------------

func _sword_1() -> void:
	var silver := Color(0.88, 0.93, 1.0)
	for i in 2:
		var spark := _strip(&"sword_sparks", &"spark", 0.42, Color(silver, 1.0), false, along(0.45 + 0.5 * i))
		spark.repeat_every = 1.3
		spark.delay(0.65 * i)
	_strip(&"sword_glint", &"sparkle", 0.3, Color(silver, 0.9), true, along(0.8), 5)


func _sword_2() -> void:
	# Long-lived streaks left in world space: still, they line the edge; swung, they trail.
	var trail := _particles(&"sword_trail", "streak", 26, 0.2, Color(0.75, 0.9, 1.0), 0.32, Vector3.ZERO, 0.0)
	trail.initial_velocity_max = 0.05
	trail.spread = 10.0
	_strip(&"sword_edge_glow", &"sparkle", 0.36, Color(0.7, 0.88, 1.0, 0.95), true, along(0.55))
	_strip(&"sword_edge_glow", &"sparkle", 0.28, Color(0.7, 0.88, 1.0, 0.85), true, along(0.95), 9)


func _sword_3() -> void:
	var ember := Color(1.0, 0.55, 0.15)
	# Embers that run from the grip to the tip, in the blade's own space.
	var run := _particles(&"sword_embers", "dot", 20, 0.1, ember, 0.9, Vector3.ZERO, 0.0, [along(0.0), along(0.1)])
	run.local_coords = true
	run.direction = axis_direction()
	run.spread = 6.0
	run.initial_velocity_min = span_length() * 1.0
	run.initial_velocity_max = span_length() * 1.3
	_particles(&"sword_rising_embers", "dot", 10, 0.07, Color(1.0, 0.7, 0.3), 1.2, Vector3(0, 0.8, 0), 0.0)
	_add_light(ember, 0.5)


func _sword_4() -> void:
	# Flames on alternate sides of the blade, as if wrapped round it.
	var side := axis_direction().cross(Vector3.FORWARD if absf(axis_direction().z) < 0.9 else Vector3.RIGHT).normalized() * span_length() * 0.06
	for i in 3:
		var flame := _strip(&"sword_flames", &"flame" if i % 2 == 0 else &"flame_b", 0.3, Color(1, 1, 1, 0.95), true,
				along(0.25 + 0.33 * i) + side * (1.0 if i % 2 == 0 else -1.0), i * 3)
		flame.offset.y = 20.0
	var run := _particles(&"sword_embers", "dot", 12, 0.06, Color(1.0, 0.55, 0.15), 0.8, Vector3.ZERO, 0.0, [along(0.0), along(0.15)])
	run.local_coords = true
	run.direction = axis_direction()
	run.initial_velocity_min = span_length() * 1.1
	run.initial_velocity_max = span_length() * 1.4
	_add_light(Color(1.0, 0.5, 0.18), 1.1)


func _sword_5() -> void:
	for i in 4:
		var flame := _strip(&"sword_inferno", &"flame" if i % 2 == 0 else &"flame_b", 0.44, Color(1, 1, 1, 1), true, along(0.15 + 0.27 * i), i * 2)
		flame.offset.y = 22.0
	var flash := _strip(&"sword_heat_flash", &"slash_flash", 0.7, Color(1.0, 0.62, 0.22, 0.95), false, along(0.7))
	flash.repeat_every = 1.6
	var stream := _particles(&"sword_fire_stream", "fire", 14, 0.32, Color(1, 1, 1), 0.7, Vector3(0, 1.4, 0), 0.0)
	stream.scale_amount_min = 0.8
	stream.scale_amount_max = 1.4
	_particles(&"sword_ember_storm", "dot", 20, 0.06, Color(1.0, 0.68, 0.25), 1.1, Vector3(0, 1.6, 0), 0.0)
	_add_light(Color(1.0, 0.48, 0.15), 1.4)


# --- axe: earth / shockwave -----------------------------------------------------------

func _axe_1() -> void:
	var steel := Color(1.0, 0.82, 0.55)
	for i in 2:
		var spark := _strip(&"axe_sparks", &"spark", 0.5, steel, false, along(0.5 + 0.45 * i))
		spark.repeat_every = 0.9
		spark.delay(0.45 * i)
	_particles(&"axe_metal_glints", "dot", 10, 0.045, Color(1.0, 0.9, 0.7), 0.6, Vector3(0, -3.0, 0), 0.0)


func _axe_2() -> void:
	_particles(&"axe_pebbles", "pebble", 12, 0.08, Color(0.62, 0.52, 0.4), 0.9, Vector3(0, -4.0, 0), 1.2)
	for i in 2:
		var dust := _strip(&"axe_dust", &"dust_puff", 0.55, Color(0.78, 0.66, 0.5, 0.85), false, along(0.35 + 0.6 * i))
		dust.repeat_every = 1.8
		dust.delay(0.9 * i)


func _axe_3() -> void:
	var amber := Color(1.0, 0.68, 0.22)
	var ring := _ring(&"axe_runes", "rune", span_length() * 1.1, Color(amber, 0.95), along(0.55), 1.4)
	_pulses.append([ring, ring.scale, 0.12, 0.8])
	_particles(&"axe_pebbles", "pebble", 8, 0.07, Color(0.6, 0.5, 0.38), 0.9, Vector3(0, -4.0, 0), 1.2)
	_add_light(amber, 0.5)


func _axe_4() -> void:
	var amber := Color(1.0, 0.62, 0.2)
	_ring(&"axe_runes", "rune", span_length() * 1.25, Color(amber, 0.95), along(0.5), 1.3)
	_ring(&"axe_runes", "rune", span_length() * 0.85, Color(1.0, 0.8, 0.35, 0.9), along(0.5), -2.1)
	var orbit := _spinner(along(0.5), 2.4)
	for i in 3:
		var rock := _sprite(&"axe_orbit_rocks", "pebble", span_length() * 0.32, Color(0.55, 0.47, 0.36), orbit)
		rock.position = _perpendicular(TAU * i / 3.0) * span_length() * 0.75
	var rubble := _strip(&"axe_rubble", &"rubble", 0.6, Color(0.75, 0.66, 0.52, 0.9), false, along(0.8))
	rubble.repeat_every = 1.4
	_add_light(amber, 0.9)


func _axe_5() -> void:
	var orbit := _spinner(along(0.5), 1.8)
	for i in 4:
		var rock := _sprite(&"axe_orbit_rocks", "pebble", span_length() * 0.45, Color(0.5, 0.42, 0.32), orbit)
		rock.position = _perpendicular(TAU * i / 4.0) * span_length() * 1.0
	_ring(&"axe_runes", "rune", span_length() * 1.5, Color(1.0, 0.55, 0.15, 1.0), along(0.5), 1.1)
	var magma := _particles(&"axe_magma", "dot", 18, 0.07, Color(1.0, 0.42, 0.1), 0.9, Vector3(0, 1.1, 0), 0.0)
	magma.initial_velocity_max = 0.6
	for i in 2:
		var dust := _strip(&"axe_dust_ring", &"dust_ring", 0.9, Color(1, 1, 1, 0.9), false, along(0.4 + 0.5 * i))
		dust.repeat_every = 1.5
		dust.delay(0.75 * i)
	_particles(&"axe_pebbles", "pebble", 10, 0.09, Color(0.55, 0.45, 0.34), 0.9, Vector3(0, -4.0, 0), 1.2)
	_add_light(Color(1.0, 0.45, 0.12), 1.2)


# --- bow: wind / lightning ------------------------------------------------------------

func _bow_1() -> void:
	var breeze := _particles(&"bow_breeze", "streak", 12, 0.16, Color(0.85, 1.0, 0.92), 1.0, Vector3(0.9, 0.1, 0), 0.0, _bow_points())
	breeze.initial_velocity_max = 0.2


func _bow_2() -> void:
	for i in 2:
		_strip(&"bow_air_trails", &"swirl", 0.55, Color(0.78, 1.0, 0.9, 0.85), true, _bow_at(0.05 + 0.28 * i), i * 6)
	var breeze := _particles(&"bow_breeze", "streak", 10, 0.16, Color(0.85, 1.0, 0.92), 1.0, Vector3(0.9, 0.1, 0), 0.0, _bow_points())
	breeze.initial_velocity_max = 0.2


func _bow_3() -> void:
	var spiral := _spinner(_bow_at(0.22), 5.5)
	for i in 3:
		var streak := _sprite(&"bow_wind_spiral", "streak", span_length() * 0.3, Color(0.8, 1.0, 0.92, 0.95), spiral)
		streak.position = _perpendicular(TAU * i / 3.0) * span_length() * 0.18 + axis_direction() * span_length() * (i - 1) * 0.12
	_strip(&"bow_air_trails", &"swirl", 0.7, Color(0.75, 1.0, 0.9, 0.9), true, _bow_at(0.22))


func _bow_4() -> void:
	var electric := Color(0.55, 0.85, 1.0)
	for i in 2:
		_strip(&"bow_arcs", &"arc_ring", 0.5, Color(electric, 0.95), true, _bow_at(0.03 + 0.3 * i), i * 4)
	var bolt := _strip(&"bow_bolts", &"arc_ring", 0.4, Color(0.8, 0.95, 1.0, 1.0), false, _bow_at(0.15))
	bolt.repeat_every = 0.8
	var sparks := _particles(&"bow_sparks", "dot", 16, 0.04, Color(0.8, 0.95, 1.0), 0.25, Vector3.ZERO, 0.0, _bow_points())
	sparks.initial_velocity_min = 0.6
	sparks.initial_velocity_max = 1.4
	sparks.spread = 180.0
	_add_light(electric, 0.9)


func _bow_5() -> void:
	var electric := Color(0.6, 0.85, 1.0)
	_strip(&"bow_storm", &"aura", 0.65, Color(electric, 1.0), true, _bow_at(0.22))
	for i in 2:
		_strip(&"bow_arcs", &"arc_ring", 0.6, Color(0.85, 0.95, 1.0, 1.0), true, _bow_at(0.02 + 0.3 * i), i * 5)
	# A lightning strike that comes down on the bottom limb, away from the face.
	var strike := _strip(&"bow_strike", &"strike", 0.8, Color.WHITE, false, _bow_at(0.0))
	strike.offset.y = 30.0
	strike.repeat_every = 1.4
	var spiral := _spinner(_bow_at(0.22), 6.0)
	for i in 3:
		var streak := _sprite(&"bow_wind_spiral", "streak", span_length() * 0.3, Color(0.8, 1.0, 0.95, 0.9), spiral)
		streak.position = _perpendicular(TAU * i / 3.0) * span_length() * 0.2
	_add_light(electric, 1.3)


## Emission points along the bow below BOW_TOP (the grip and the bottom limb).
func _bow_points() -> Array:
	var points: Array = []
	for i in 7:
		points.append(_bow_at(BOW_TOP * i / 6.0))
	return points


## A point t along the bow measured from its lower limb (0) to its upper limb (1): which end
## of the model is down depends on how the courier holds it, so it is measured in the world.
func _bow_at(t: float) -> Vector3:
	var a := along(0.0)
	var b := along(1.0)
	var flipped := is_inside_tree() and to_global(a).y > to_global(b).y
	return along(1.0 - t if flipped else t)


# --- staff: arcane / water / storm ----------------------------------------------------

func _staff_1() -> void:
	var motes := _particles(&"staff_motes", "dot", 18, 0.09, Color(0.82, 0.62, 1.0), 1.6, Vector3(0, 0.15, 0), 0.0)
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = span_length() * 0.6
	motes.emission_points = PackedVector3Array()
	motes.position = along(0.85)


func _staff_2() -> void:
	var violet := Color(0.72, 0.5, 1.0)
	_ring(&"staff_rune_circle", "rune", span_length() * 1.5, Color(violet, 1.0), along(0.95), 1.6)
	var upright := _ring(&"staff_rune_circle", "rune", span_length() * 0.9, Color(0.85, 0.7, 1.0, 0.9), along(0.95), -2.4)
	upright.rotate(_perpendicular(0.0), PI * 0.5)
	var motes := _particles(&"staff_motes", "dot", 8, 0.05, violet, 1.4, Vector3(0, 0.15, 0), 0.0)
	motes.position = along(0.9)


func _staff_3() -> void:
	var water := Color(0.4, 0.75, 1.0)
	var orbit := _spinner(along(0.92), 3.2)
	for i in 4:
		var drop := _sprite(&"staff_water_orbit", "dot", span_length() * 0.3, Color(water, 1.0), orbit)
		drop.position = _perpendicular(TAU * i / 4.0) * span_length() * 0.8
	_strip(&"staff_swirl", &"swirl", 0.75, Color(water, 0.95), true, along(0.95))
	var bubbles := _strip(&"staff_bubbles", &"bubbles", 0.5, Color(0.6, 0.88, 1.0, 0.9), false, along(1.0))
	bubbles.repeat_every = 2.0
	_add_light(water, 0.6)


func _staff_4() -> void:
	var arcane := Color(0.7, 0.45, 1.0)
	var orbit := _spinner(along(0.9), 2.0)
	for i in 3:
		var crystal := _crystal(&"staff_crystals", span_length() * 0.35, arcane, orbit)
		crystal.position = _perpendicular(TAU * i / 3.0) * span_length() * 0.9
	var stream := _particles(&"staff_streams", "streak", 16, 0.07, Color(0.8, 0.6, 1.0), 0.7, Vector3.ZERO, 0.0, [along(-1.5), along(-1.0)])
	stream.local_coords = true
	stream.direction = axis_direction()
	stream.spread = 4.0
	stream.initial_velocity_min = span_length() * 3.0
	stream.initial_velocity_max = span_length() * 3.6
	_strip(&"staff_charge", &"charge", 0.55, Color(0.85, 0.7, 1.0, 0.95), true, along(1.0))
	_add_light(arcane, 0.8)


func _staff_5() -> void:
	var arcane := Color(0.72, 0.45, 1.0)
	_ring(&"staff_storm_rings", "rune", span_length() * 3.2, Color(arcane, 1.0), along(0.95), 1.3)
	_ring(&"staff_storm_rings", "rune", span_length() * 2.2, Color(0.55, 0.8, 1.0, 1.0), along(0.95), -2.0)
	var orbit := _spinner(along(0.95), 2.6)
	for i in 4:
		var crystal := _crystal(&"staff_crystals", span_length() * 0.6, arcane if i % 2 == 0 else Color(0.45, 0.75, 1.0), orbit)
		crystal.position = _perpendicular(TAU * i / 4.0) * span_length() * 1.7
	var warp := _strip(&"staff_warp", &"warp", 1.3, Color(0.8, 0.6, 1.0, 1.0), false, along(1.0))
	warp.repeat_every = 1.2
	_strip(&"staff_storm_crackle", &"aura", 0.6, Color(0.7, 0.55, 1.0, 0.9), true, along(1.0))
	var stream := _particles(&"staff_streams", "streak", 14, 0.07, Color(0.85, 0.65, 1.0), 0.7, Vector3.ZERO, 0.0, [along(-1.5), along(-1.0)])
	stream.local_coords = true
	stream.direction = axis_direction()
	stream.initial_velocity_min = span_length() * 3.0
	stream.initial_velocity_max = span_length() * 3.6
	_add_light(arcane, 1.2)


# --- generic tiers (shields) -----------------------------------------------------------

func _silver_spark() -> void:
	var silver := Color(0.88, 0.93, 1.0)
	for i in 2:
		var spark := _strip(&"spark", &"spark", 0.42, Color(silver, 1.0), false, along(0.45 + 0.5 * i))
		spark.repeat_every = 1.3
		spark.delay(0.65 * i)
	_strip(&"glint", &"sparkle", 0.34, Color(silver, 0.9), true, along(0.7), 5)
	_particles(&"motes", "dot", 10, 0.05, silver, 0.9, Vector3(0, 0.25, 0), 0.0)


func _nature() -> void:
	for i in 3:
		var bloom := _strip(&"nature", &"nature_burst", 0.5, Color.WHITE, false, along(0.25 + 0.37 * i))
		bloom.repeat_every = 1.5
		bloom.delay(0.5 * i)
	_particles(&"leaves", "leaf", 14, 0.13, Color(0.45, 0.95, 0.35), 1.4, Vector3(0, 0.45, 0), 1.6)
	_particles(&"motes", "dot", 8, 0.05, Color(0.7, 1.0, 0.5), 1.0, Vector3(0, 0.3, 0), 0.0)


func _water() -> void:
	var water := Color(0.35, 0.72, 1.0)
	_strip(&"swirl", &"swirl", 0.85, Color(water, 0.95), true, along(0.55))
	var bubbles := _strip(&"bubbles", &"bubbles", 0.55, Color(0.6, 0.88, 1.0, 0.9), false, along(0.95))
	bubbles.repeat_every = 2.2
	_particles(&"drips", "dot", 12, 0.06, water, 0.8, Vector3(0, -2.5, 0), 0.0)
	_add_light(water, 0.6)


func _lightning() -> void:
	var violet := Color(0.72, 0.42, 1.0)
	_strip(&"crackle", &"aura", 0.62, Color(violet, 0.95), true, along(0.4))
	_strip(&"crackle", &"aura", 0.5, Color(violet, 0.85), true, along(0.9), 8)
	for i in 2:
		var bolt := _strip(&"bolt", &"bolt_flash", 0.48, Color.WHITE, false, along(0.3 + 0.6 * i))
		bolt.repeat_every = 0.9 + 0.35 * i
		bolt.delay(0.45 * i)
	_add_light(violet, 1.1)


func _legendary() -> void:
	for i in 3:
		var flame := _strip(&"flame", &"flame" if i % 2 == 0 else &"flame_b", 0.34, Color(1, 1, 1, 0.95), true, along(0.35 + 0.3 * i), i * 2)
		flame.offset.y = 20.0
	_strip(&"crackle", &"aura", 0.85, Color(0.78, 0.5, 1.0, 1.0), true, along(0.65), 4)
	var ring := _strip(&"swirl", &"swirl", 0.95, Color(0.4, 0.78, 1.0, 1.0), true, along(0.05), 2)
	ring.name = "Vfx_water_ring"
	var bolt := _strip(&"bolt", &"bolt_flash", 0.55, Color.WHITE, false, along(1.0))
	bolt.repeat_every = 1.1
	_particles(&"embers", "dot", 14, 0.05, Color(1.0, 0.62, 0.2), 1.1, Vector3(0, 0.9, 0), 0.0)
	_particles(&"drips", "dot", 8, 0.06, Color(0.4, 0.78, 1.0), 0.8, Vector3(0, -2.5, 0), 0.0)
	_add_light(Color(1.0, 0.6, 0.25), 1.6)


# --- builders ------------------------------------------------------------------------

## The courier holds a bow across the body, so from the iso camera most of it is behind the
## courier and its effects were hidden. The bow's flipbooks, particles and shapes draw over
## the body (no depth test, drawn after it) and a little larger.
func _show_over_body() -> void:
	shows_over_body = true
	for sprite in strips:
		var material := sprite.material_override as StandardMaterial3D
		material.no_depth_test = true
		material.render_priority = OVER_BODY_PRIORITY
		sprite.pixel_size *= BOW_SIZE
	for emitter in particles:
		var quad := emitter.mesh as QuadMesh
		quad.size *= BOW_SIZE
		var material := quad.material as StandardMaterial3D
		material.no_depth_test = true
		material.render_priority = OVER_BODY_PRIORITY
	for shape in shapes:
		var material := shape.material_override as StandardMaterial3D
		if material != null:
			material.no_depth_test = true
			material.render_priority = OVER_BODY_PRIORITY


func _record(element: StringName) -> void:
	if not elements.has(element):
		elements.append(element)


## A flipbook (VfxStrip of source) at a point of the weapon, recorded as element.
func _strip(element: StringName, source: StringName, size: float, tint: Color, looping: bool, at: Vector3, start_frame: int = 0) -> VfxStrip:
	var sprite := VfxStrip.create(source, size, tint, looping, start_frame)
	sprite.name = "Vfx_%s_%d" % [element, strips.size()]
	sprite.position = at
	add_child(sprite)
	strips.append(sprite)
	_record(element)
	return sprite


## Particles emitted along the weapon's span (or from `points`), in world space by default
## (so they trail behind a swing). texture: "dot", "leaf", "streak", "pebble" or "fire"
## (the animated 8x8 fire sheet).
func _particles(kind: StringName, texture: String, amount: int, size: float, color: Color, lifetime: float, gravity: Vector3, spin: float, points: Array = []) -> CPUParticles3D:
	var emitter := CPUParticles3D.new()
	emitter.name = "Particles_" + String(kind)
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.local_coords = false
	emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	var emission := PackedVector3Array()
	if points.is_empty():
		for i in 9:
			emission.append(along(i / 8.0))
	else:
		for p: Vector3 in points:
			emission.append(p)
	emitter.emission_points = emission
	emitter.direction = Vector3.UP
	emitter.spread = 70.0
	emitter.initial_velocity_min = 0.05
	emitter.initial_velocity_max = 0.35
	emitter.gravity = gravity
	emitter.angular_velocity_min = -spin * 90.0
	emitter.angular_velocity_max = spin * 90.0
	emitter.angle_max = 360.0 if spin > 0.0 else 0.0
	emitter.scale_amount_min = 0.7
	emitter.scale_amount_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(color, 0.0))
	fade.add_point(0.15, Color(color, 1.0))
	fade.set_color(fade.get_point_count() - 1, Color(color, 0.0))
	emitter.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var material: StandardMaterial3D
	if texture == "fire":
		material = _additive(load(FIRE_SHEET) as Texture2D, Color.WHITE)
		material.particles_anim_h_frames = 8
		material.particles_anim_v_frames = 8
		material.particles_anim_loop = false
		emitter.anim_speed_min = 1.0
		emitter.anim_speed_max = 1.0
	else:
		material = _additive(_texture(texture), Color.WHITE)
		if texture == "pebble":
			# Stones are solid: blended normally, not added.
			material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	quad.material = material
	emitter.mesh = quad
	add_child(emitter)
	particles.append(emitter)
	_record(kind)
	return emitter


## A pivot at `at` that turns about the weapon's axis at speed (radians per second).
func _spinner(at: Vector3, speed: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "Spinner%d" % _spins.size()
	pivot.position = at
	add_child(pivot)
	_spins.append([pivot, axis_direction(), speed])
	return pivot


## A glowing ring (a flat quad with a rune texture) round the weapon's axis at `at`,
## turning at speed.
func _ring(element: StringName, texture: String, diameter: float, tint: Color, at: Vector3, speed: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = "Ring_%s_%d" % [element, shapes.size()]
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * diameter
	# The quad faces +Z; turn it so its face is perpendicular to the weapon's axis.
	quad.orientation = PlaneMesh.FACE_Z
	ring.mesh = quad
	var material := _additive(_texture(texture), tint)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = at
	ring.basis = Basis(Quaternion(Vector3.BACK, axis_direction()))
	add_child(ring)
	shapes.append(ring)
	_spins.append([ring, Vector3.BACK, speed])
	_record(element)
	return ring


## A billboard sprite (rock, droplet, wind streak) on a spinner.
func _sprite(element: StringName, texture: String, size: float, tint: Color, parent: Node3D) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = "Sprite_%s_%d" % [element, shapes.size()]
	sprite.texture = _texture(texture)
	sprite.pixel_size = size / 32.0
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := _additive(sprite.texture, tint)
	if texture == "pebble":
		material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	sprite.material_override = material
	parent.add_child(sprite)
	shapes.append(sprite)
	_record(element)
	return sprite


## A small glowing crystal (prism) on a spinner.
func _crystal(element: StringName, size: float, tint: Color, parent: Node3D) -> MeshInstance3D:
	var crystal := MeshInstance3D.new()
	crystal.name = "Crystal_%d" % shapes.size()
	var prism := PrismMesh.new()
	prism.size = Vector3(size * 0.45, size, size * 0.45)
	crystal.mesh = prism
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(tint, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 2.5
	material.roughness = 0.2
	crystal.material_override = material
	crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(crystal)
	shapes.append(crystal)
	_spins.append([crystal, Vector3.UP, 3.0])
	_record(element)
	return crystal


## A unit vector perpendicular to the weapon's axis, at angle round it.
func _perpendicular(angle: float) -> Vector3:
	var axis := axis_direction()
	var first := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	return first.rotated(axis, angle)


func _add_light(color: Color, energy: float) -> void:
	light = OmniLight3D.new()
	light.name = "GlowLight"
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 1.9
	light.shadow_enabled = false
	light.position = along(0.6)
	_light_energy = energy
	add_child(light)
	_record(&"light")


## Procedural sprites shared by every glow: "dot" (soft round mote / droplet / ember),
## "leaf" (a pointed leaf with a mid-rib), "streak" (a long soft wind / trail stroke),
## "pebble" (a lumpy stone with a dark rim) and "rune" (a ring of glyph ticks).
static func _texture(kind: String) -> Texture2D:
	if _textures.has(kind):
		return _textures[kind]
	var size := 64 if kind == "rune" else 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := size * 0.5
	for y in size:
		for x in size:
			var u := (x - half + 0.5) / half
			var v := (y - half + 0.5) / half
			var r := sqrt(u * u + v * v)
			var a := 0.0
			var shade := 1.0
			match kind:
				"leaf":
					var width := 0.42 * (1.0 - v * v)
					a = clampf((width - absf(u)) * 6.0, 0.0, 1.0) if absf(v) < 1.0 else 0.0
					if absf(u) < 0.05 and v > -0.85:
						a *= 0.55
				"streak":
					a = clampf(1.0 - absf(v) * 6.0, 0.0, 1.0) * clampf(1.0 - absf(u), 0.0, 1.0)
				"pebble":
					var edge := 0.78 + 0.12 * sin(atan2(v, u) * 3.0 + 0.7) + 0.06 * sin(atan2(v, u) * 7.0)
					a = clampf((edge - r) * 8.0, 0.0, 1.0)
					shade = 1.0 - clampf((r - edge + 0.25) * 2.5, 0.0, 0.55) + 0.12 * clampf(-u - v, 0.0, 1.0)
				"rune":
					var band := clampf(1.0 - absf(r - 0.86) * 22.0, 0.0, 1.0) + clampf(1.0 - absf(r - 0.56) * 30.0, 0.0, 1.0) * 0.6
					var angle := atan2(v, u)
					var tick := clampf(1.0 - absf(fposmod(angle * 12.0 / TAU, 1.0) - 0.5) * 9.0, 0.0, 1.0)
					var glyph := tick * (1.0 if r > 0.62 and r < 0.78 else 0.0)
					a = clampf(band + glyph, 0.0, 1.0)
				_:
					a = clampf(1.0 - r, 0.0, 1.0)
					a *= a
			image.set_pixel(x, y, Color(shade, shade, shade, a))
	var texture := ImageTexture.create_from_image(image)
	_textures[kind] = texture
	return texture


static func _additive(texture: Texture2D, tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = texture
	material.albedo_color = tint
	return material


## Bounds of every mesh under node, in node's own space.
static func local_bounds(node: Node3D) -> AABB:
	var to_local := node.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var part: AABB = (to_local * mesh.global_transform) * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


static func longest_axis(box: AABB) -> int:
	var size := box.size
	if size.x >= size.y and size.x >= size.z:
		return Vector3.AXIS_X
	return Vector3.AXIS_Y if size.y >= size.z else Vector3.AXIS_Z


static func _world_scale(node: Node3D) -> float:
	var scale := node.global_transform.basis.get_scale()
	return (absf(scale.x) + absf(scale.y) + absf(scale.z)) / 3.0
