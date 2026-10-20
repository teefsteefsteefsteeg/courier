extends Control
## Draws a MinimapModel through a MinimapProjection: background, world grid,
## quest route, markers (player arrow, objective diamonds pinned to the edge,
## NPC dots, enemy triangles), a north tick and optional labels.
## Purely visual: give it a model, then call update_view() each frame (or leave
## auto_update on). Several views can share one model.
##
## Phase 5G exploration layer (when `exploration` is set): the baked terrain image
## (`map_texture` over `map_world_rect`) under the markers, the ExplorationService fog
## over ground not explored yet, and every discovered location from the shared registry
## with a kind icon (labels when show_labels is on). Undiscovered places and inactive
## portals are not drawn. The fog is map-only; it never touches the 3D view.

const MinimapProjection := preload("res://scripts/phase4_integration_visual/minimap_projection.gd")
const Model := preload("res://scripts/phase4_integration_visual/minimap_model.gd")

const KIND_COLORS := {
	&"player": Color(0.2, 0.65, 1.0),
	&"objective": Color(1.0, 0.82, 0.3),
	&"npc": Color(0.45, 0.9, 1.0),
	&"enemy": Color(1.0, 0.38, 0.32),
	&"poi": Color(0.85, 0.85, 0.95),
}
const KIND_SIZES := {&"player": 9.0, &"objective": 7.5, &"npc": 4.5, &"enemy": 5.0, &"poi": 4.5}
const DRAW_ORDER: Array[StringName] = [&"poi", &"npc", &"enemy", &"objective", &"player"]
const BACKGROUND := Color(0.07, 0.11, 0.08, 0.86)
const BORDER := Color(0.55, 1.0, 0.35, 0.75)
const GRID := Color(0.6, 0.9, 0.6, 0.09)
const ROUTE_START := Color(0.55, 1.0, 0.35, 0.9)
const ROUTE_END := Color(1.0, 0.85, 0.3, 0.9)
## Location icon colours by WorldLocation.Kind (town, guild, shop, forest, clearing, portal).
const LOCATION_COLORS := [Color(1.0, 0.86, 0.5), Color(0.95, 0.75, 0.45), Color(0.98, 0.8, 0.35),
		Color(0.55, 0.85, 0.45), Color(0.7, 0.95, 0.6), Color(0.72, 0.55, 1.0)]

@export var auto_update := true
@export var circular := true
## Metres from the centre to the nearest edge.
@export var world_radius := 32.0
## Keep the player at the centre. Off: the view stays on `fixed_center`.
@export var follow_player := true
@export var fixed_center := Vector2.ZERO
## Rotate so the map matches the active Camera3D (isometric yaw). Off: north-up.
@export var align_to_camera := true
@export var grid_spacing := 10.0
@export var marker_scale := 1.0
@export var show_labels := false
## Labels for these kinds when show_labels is on.
@export var label_kinds: Array[StringName] = [&"objective", &"npc", &"poi"]
@export var show_route := true
@export var show_north := true
@export var edge_margin := 9.0
@export var font_size := 12

var model: Model
var projection := MinimapProjection.new()
## Phase 5G exploration layer (see the class doc); all optional.
var exploration: ExplorationService = null
var map_texture: Texture2D = null
var map_world_rect := Rect2()
@export var show_locations := true
## id -> {point: Vector2 (map px), inside: bool, pinned: bool}
var placements: Dictionary = {}
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = not circular
	resized.connect(update_view)


func _process(delta: float) -> void:
	_time += delta
	if auto_update and is_visible_in_tree():
		update_view()


func set_model(value: Model) -> void:
	model = value
	update_view()


## Recomputes the projection and every marker placement, then redraws.
func update_view() -> void:
	projection.map_size = size if size.x > 1.0 and size.y > 1.0 else custom_minimum_size.max(Vector2(64, 64))
	projection.world_radius = world_radius
	projection.circular = circular
	if align_to_camera:
		var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam != null:
			projection.match_camera(cam.global_basis)
	placements.clear()
	if model != null:
		model.prune()
		var player := model.get_player_world()
		if follow_player and player.is_finite():
			projection.set_center_world(player)
		elif not follow_player:
			projection.center = fixed_center
		for id in model.markers:
			var m: Dictionary = model.markers[id]
			var world := model.get_marker_world(id)
			if not bool(m["visible"]) or not world.is_finite():
				continue
			var p := projection.world_to_map(world)
			var inside := projection.is_inside(p, edge_margin * 0.5)
			if not inside and not bool(m["pin"]):
				continue
			placements[id] = {
				"point": p if inside else projection.clamp_to_edge(p, edge_margin),
				"inside": inside,
				"pinned": not inside,
			}
	queue_redraw()


## Map-space position of a placed marker, or Vector2.INF if it is not drawn.
func get_marker_point(id: StringName) -> Vector2:
	return placements[id]["point"] if placements.has(id) else Vector2.INF


func is_marker_drawn(id: StringName) -> bool:
	return placements.has(id)


func is_marker_pinned(id: StringName) -> bool:
	return placements.has(id) and bool(placements[id]["pinned"])


func get_kind_color(kind: StringName) -> Color:
	return KIND_COLORS.get(kind, KIND_COLORS[&"poi"])


# --- drawing -------------------------------------------------------------------

func _draw() -> void:
	var half := projection.get_half_size()
	var radius := minf(half.x, half.y)
	if circular:
		draw_circle(half, radius, BACKGROUND)
	else:
		draw_rect(Rect2(Vector2.ZERO, projection.map_size), BACKGROUND)
	if map_texture != null and map_world_rect.has_area():
		_draw_world_texture(map_texture, Color.WHITE)
	else:
		_draw_grid()
	if exploration != null and map_world_rect.has_area():
		# The fog grid always covers the exploration rect (the region maps keep their own).
		_draw_world_texture(exploration.get_fog_texture(), Color.WHITE, ExplorationService.WORLD_RECT)
	if exploration != null and show_locations:
		_draw_locations()
	if show_route and model != null:
		_draw_route()
	if model != null:
		for kind in DRAW_ORDER:
			for id in placements:
				var m: Dictionary = model.markers.get(id, {})
				if not m.is_empty() and m["kind"] == kind:
					_draw_marker(id, m)
	if circular:
		draw_arc(half, radius - 1.0, 0.0, TAU, 64, BORDER, 2.0, true)
	else:
		draw_rect(Rect2(Vector2.ONE, projection.map_size - Vector2(2, 2)), BORDER, false, 2.0)
	if show_north:
		_draw_north()


## Draws a texture that covers rect (map_world_rect by default), clipped to the map outline
## (circle or box): the outline polygon with each point's UV taken from its world position.
func _draw_world_texture(texture: Texture2D, tint: Color, rect: Rect2 = Rect2()) -> void:
	var area := rect if rect.has_area() else map_world_rect
	var outline := projection.get_outline(1.0)
	var uvs := PackedVector2Array()
	for point in outline:
		var world := projection.map_to_world(point)
		uvs.append((Vector2(world.x, world.z) - area.position) / area.size)
	draw_polygon(outline, PackedColorArray([tint]), uvs, texture)


## Discovered locations (and active portals) with their kind icon.
func _draw_locations() -> void:
	for location in exploration.get_locations():
		var id := location.location_id
		if location.kind == WorldLocation.Kind.PORTAL:
			if not exploration.is_portal_active(id):
				continue
		elif location.hidden_until_discovered and not exploration.is_discovered(id):
			continue
		var p := projection.world_xz_to_map(location.get_map_position())
		if not projection.is_inside(p, edge_margin * 0.5):
			continue
		var s := 6.0 * marker_scale
		draw_location_icon(self, location.kind, p, s, _time)
		if show_labels:
			_draw_label(p + Vector2(0, -s - 6.0), location.display_name, LOCATION_COLORS[location.kind])


## Map icon for a WorldLocation.Kind at p (size s), shared with the map legend.
static func draw_location_icon(canvas: CanvasItem, kind: int, p: Vector2, s: float, time := 0.0) -> void:
	var color: Color = LOCATION_COLORS[kind]
	var ink := Color(0.06, 0.04, 0.03, 0.95)
	match kind:
		WorldLocation.Kind.TOWN:
			var house := PackedVector2Array([p + Vector2(-s, s * 0.8), p + Vector2(-s, -s * 0.1), p + Vector2(0, -s), p + Vector2(s, -s * 0.1), p + Vector2(s, s * 0.8)])
			canvas.draw_colored_polygon(house, color)
			house.append(house[0])
			canvas.draw_polyline(house, ink, 1.5, true)
		WorldLocation.Kind.GUILD:
			canvas.draw_rect(Rect2(p - Vector2(s, s * 0.7), Vector2(s * 2.0, s * 1.4)), color)
			canvas.draw_rect(Rect2(p - Vector2(s, s * 0.7), Vector2(s * 2.0, s * 1.4)), ink, false, 1.5)
			canvas.draw_polyline(PackedVector2Array([p + Vector2(-s, -s * 0.7), p + Vector2(0, s * 0.15), p + Vector2(s, -s * 0.7)]), ink, 1.2, true)
		WorldLocation.Kind.SHOP:
			canvas.draw_circle(p, s + 1.5, ink)
			canvas.draw_circle(p, s, color)
			canvas.draw_circle(p, s * 0.4, ink)
		WorldLocation.Kind.FOREST, WorldLocation.Kind.CLEARING:
			var tree := PackedVector2Array([p + Vector2(0, -s * 1.1), p + Vector2(s, s * 0.6), p + Vector2(-s, s * 0.6)])
			canvas.draw_colored_polygon(tree, color)
			tree.append(tree[0])
			canvas.draw_polyline(tree, ink, 1.5, true)
			canvas.draw_line(p + Vector2(0, s * 0.6), p + Vector2(0, s * 1.1), ink, 2.0)
		WorldLocation.Kind.PORTAL:
			var pulse := 1.0 + 0.15 * sin(time * 3.0)
			canvas.draw_arc(p, s * 1.35 * pulse, 0.0, TAU, 24, Color(color, 0.5), 2.0, true)
			canvas.draw_circle(p, s + 1.5, ink)
			canvas.draw_circle(p, s, color)
			var star := PackedVector2Array([p + Vector2(0, -s * 0.75), p + Vector2(s * 0.25, 0), p + Vector2(0, s * 0.75), p + Vector2(-s * 0.25, 0)])
			canvas.draw_colored_polygon(star, Color(1, 1, 1, 0.9))


func _draw_grid() -> void:
	if grid_spacing <= 0.0:
		return
	var area := projection.get_visible_world_rect()
	var outline := projection.get_outline(1.0)
	var x := floorf(area.position.x / grid_spacing) * grid_spacing
	var guard := 0
	while x <= area.end.x and guard < 200:
		_draw_clipped(PackedVector2Array([
			projection.world_xz_to_map(Vector2(x, area.position.y)),
			projection.world_xz_to_map(Vector2(x, area.end.y)),
		]), outline, GRID, 1.0)
		x += grid_spacing
		guard += 1
	var z := floorf(area.position.y / grid_spacing) * grid_spacing
	while z <= area.end.y and guard < 400:
		_draw_clipped(PackedVector2Array([
			projection.world_xz_to_map(Vector2(area.position.x, z)),
			projection.world_xz_to_map(Vector2(area.end.x, z)),
		]), outline, GRID, 1.0)
		z += grid_spacing
		guard += 1


func _draw_route() -> void:
	var pts := model.route_points
	if pts.size() < 2:
		return
	var outline := projection.get_outline(2.0)
	var count := pts.size() - 1
	for i in count:
		var color := ROUTE_START.lerp(ROUTE_END, float(i) / maxf(float(count - 1), 1.0))
		_draw_clipped(PackedVector2Array([projection.world_to_map(pts[i]), projection.world_to_map(pts[i + 1])]), outline, color, 3.0 * marker_scale)


func _draw_clipped(line: PackedVector2Array, outline: PackedVector2Array, color: Color, width: float) -> void:
	for piece: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(line, outline):
		if piece.size() >= 2:
			draw_polyline(piece, color, width, true)


func _draw_marker(id: StringName, m: Dictionary) -> void:
	var placement: Dictionary = placements[id]
	var p: Vector2 = placement["point"]
	var kind: StringName = m["kind"]
	var color: Color = m["color"]
	if color.a <= 0.0:
		color = get_kind_color(kind)
	var s := float(KIND_SIZES.get(kind, 4.5)) * marker_scale
	var state: StringName = m["state"]
	if state == Model.STATE_DEFEATED:
		color = color.darkened(0.55)
		color.a = 0.6
	var outline_color := Color(0.03, 0.05, 0.04, 0.9)
	match kind:
		&"player":
			var fwd := projection.direction_to_map(model.get_player_heading())
			if fwd == Vector2.ZERO:
				fwd = Vector2.UP
			var side := Vector2(-fwd.y, fwd.x)
			var tri := PackedVector2Array([p + fwd * s * 1.25, p - fwd * s * 0.7 + side * s * 0.8, p - fwd * s * 0.35, p - fwd * s * 0.7 - side * s * 0.8])
			draw_colored_polygon(tri, color)
			tri.append(tri[0])
			draw_polyline(tri, outline_color, 1.5, true)
		&"objective":
			var pulse := 1.0 + 0.18 * sin(_time * 5.0)
			var r := s * pulse
			if state == Model.STATE_COMPLETE:
				color = Color(0.45, 1.0, 0.5)
			if bool(placement["pinned"]):
				_draw_edge_arrow(p, color, s)
			draw_arc(p, r + 3.0 * marker_scale, 0.0, TAU, 24, Color(color, 0.45), 1.5, true)
			var diamond := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
			draw_colored_polygon(diamond, color)
			diamond.append(diamond[0])
			draw_polyline(diamond, outline_color, 1.5, true)
		&"enemy":
			var tri := PackedVector2Array([p + Vector2(0, s), p + Vector2(-s, -s * 0.8), p + Vector2(s, -s * 0.8)])
			draw_colored_polygon(tri, color)
			tri.append(tri[0])
			draw_polyline(tri, outline_color, 1.2, true)
		&"npc":
			draw_circle(p, s + 1.2, outline_color)
			draw_circle(p, s, color)
		_:
			draw_rect(Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), outline_color)
			draw_rect(Rect2(p - Vector2(s, s) * 0.75, Vector2(s, s) * 1.5), color)

	if show_labels and String(m["label"]) != "" and label_kinds.has(kind):
		_draw_label(p + Vector2(0, -s - 5.0), String(m["label"]), color)


## Small chevron on the rim pointing outward to an off-map objective.
func _draw_edge_arrow(p: Vector2, color: Color, s: float) -> void:
	var out := (p - projection.get_half_size()).normalized()
	if out == Vector2.ZERO:
		return
	var side := Vector2(-out.y, out.x)
	var tip := p + out * (s + 6.0)
	draw_colored_polygon(PackedVector2Array([tip, p + out * (s + 1.0) + side * s * 0.7, p + out * (s + 1.0) - side * s * 0.7]), color)


func _draw_label(at: Vector2, text: String, color: Color) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var fs := int(font_size * maxf(marker_scale, 1.0))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	var pos := Vector2(at.x - w * 0.5, at.y)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.02, 0.04, 0.03, 0.9))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color.lightened(0.25))


func _draw_north() -> void:
	var font := get_theme_default_font()
	var dir := projection.direction_to_map(Vector3(0, 0, -1))
	var half := projection.get_half_size()
	var r := minf(half.x, half.y) if circular else (projection.clamp_to_edge(half + dir * 10000.0) - half).length()
	var at := half + dir * (r - 9.0)
	draw_circle(at, 7.0, Color(0.03, 0.05, 0.04, 0.9))
	if font != null:
		var fs := 11
		var sz := font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, at + Vector2(-sz.x * 0.5, sz.y * 0.32), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.9, 0.6))
