extends Control
## Legend for the full world map: the same icons the map draws (player arrow, objective,
## villager, enemy, town, guild hall, shop, forest, portal) and the fog of war, each with
## its name, in a compact two-column panel.

const View = preload("res://scripts/phase4_integration_visual/minimap_view.gd")
const ROW_HEIGHT := 20.0
const COLUMN_WIDTH := 150.0
const ENTRIES := [
	["player", "You"], ["objective", "Objective"], ["npc", "Villager"], ["enemy", "Enemy"], ["fog", "Unexplored"],
	["town", "Town"], ["guild", "Guild hall"], ["shop", "Shop"], ["forest", "Forest"], ["portal", "Teleport portal"],
]
const KINDS := {&"town": 0, &"guild": 1, &"shop": 2, &"forest": 3, &"portal": 5}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rows := ceili(ENTRIES.size() / 2.0)
	custom_minimum_size = Vector2(COLUMN_WIDTH * 2.0 + 20.0, rows * ROW_HEIGHT + 14.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.055, 0.045, 0.88))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.83, 0.68, 0.38, 0.8), false, 1.0)
	var font := get_theme_default_font()
	var rows := ceili(ENTRIES.size() / 2.0)
	for i in ENTRIES.size():
		var column := i / rows
		var row := i % rows
		var p := Vector2(18.0 + column * COLUMN_WIDTH, 16.0 + row * ROW_HEIGHT)
		_draw_icon(StringName(ENTRIES[i][0]), p)
		if font != null:
			draw_string(font, p + Vector2(16, 5), ENTRIES[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.93, 0.89, 0.8))


func _draw_icon(entry: StringName, p: Vector2) -> void:
	var ink := Color(0.03, 0.05, 0.04, 0.9)
	match entry:
		&"player":
			var tri := PackedVector2Array([p + Vector2(0, -7), p + Vector2(5.5, 5), p + Vector2(0, 2.5), p + Vector2(-5.5, 5)])
			draw_colored_polygon(tri, View.KIND_COLORS[&"player"])
		&"objective":
			var d := PackedVector2Array([p + Vector2(0, -6), p + Vector2(6, 0), p + Vector2(0, 6), p + Vector2(-6, 0)])
			draw_colored_polygon(d, View.KIND_COLORS[&"objective"])
		&"npc":
			draw_circle(p, 5.0, ink)
			draw_circle(p, 4.0, View.KIND_COLORS[&"npc"])
		&"enemy":
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, 5), p + Vector2(-5, -4), p + Vector2(5, -4)]), View.KIND_COLORS[&"enemy"])
		&"fog":
			draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), ExplorationService.FOG_HIDDEN)
			draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Color(0.5, 0.45, 0.4), false, 1.0)
		_:
			View.draw_location_icon(self, KINDS.get(entry, 0), p, 5.5)
