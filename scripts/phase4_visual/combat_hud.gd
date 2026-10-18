extends CanvasLayer
## Compact Phase 4 combat HUD (bottom-left): health, magic bolt cooldown, dash
## readiness and package-shield state. Self-contained; it does not touch the
## shared gameplay HUD. Values are pushed in by the combat visual adapter (or
## the showcase preview). Cooldowns can be pushed exactly (set_bolt_cooldown)
## or estimated locally (start_bolt_cooldown / start_dash_cooldown + advance).

const HEALTH_COLOR := Color(0.85, 0.25, 0.3)
const BOLT_COLOR := Color(0.7, 0.5, 1.0)
const DASH_COLOR := Color(0.45, 0.95, 1.0)
const SHIELD_COLOR := Color(0.4, 0.95, 0.85)
const SHIELD_LOW_COLOR := Color(1.0, 0.45, 0.2)
const DIM_COLOR := Color(0.35, 0.35, 0.4)

@export var auto_animate := true

var panel: PanelContainer
var health_bar: ProgressBar
var health_label: Label
var bolt_bar: ProgressBar
var bolt_label: Label
var dash_bar: ProgressBar
var dash_label: Label
var shield_bar: ProgressBar
var shield_label: Label

var health_current := 100.0
var health_max := 100.0
var bolt_remaining := 0.0
var bolt_total := 1.0
var dash_ready := true
var dashing := false
var dash_remaining := 0.0
var dash_total := 1.0
var shield_active := false
var shield_durability := 0.0

var _local_bolt_timer := false
var _local_dash_timer := false
var _damage_flash := 0.0


func _ready() -> void:
	layer = 6
	_ensure_built()
	_refresh()


func _process(delta: float) -> void:
	if auto_animate:
		advance(delta)


# --- pushed values -------------------------------------------------------------

func set_health(current: float, maximum: float) -> void:
	_ensure_built()
	if current < health_current:
		_damage_flash = 1.0
	health_max = maxf(maximum, 0.001)
	health_current = clampf(current, 0.0, health_max)
	_refresh()


## Exact cooldown from gameplay. remaining <= 0 means ready.
func set_bolt_cooldown(remaining: float, total: float) -> void:
	_ensure_built()
	_local_bolt_timer = false
	bolt_total = maxf(total, 0.001)
	bolt_remaining = clampf(remaining, 0.0, bolt_total)
	_refresh()


func start_bolt_cooldown(total: float) -> void:
	set_bolt_cooldown(total, total)
	_local_bolt_timer = true


func set_dash_state(is_ready: bool, is_dashing := false, remaining := 0.0, total := 1.0) -> void:
	_ensure_built()
	_local_dash_timer = false
	dash_ready = is_ready and not is_dashing
	dashing = is_dashing
	dash_total = maxf(total, 0.001)
	dash_remaining = 0.0 if dash_ready else clampf(remaining, 0.0, dash_total)
	_refresh()


func start_dash_cooldown(total: float) -> void:
	set_dash_state(false, false, total, total)
	_local_dash_timer = true


## durability: 0..1 ratio (values above 1 are treated as percent).
func set_shield_state(active: bool, durability: float) -> void:
	_ensure_built()
	var ratio := durability / 100.0 if durability > 1.0 else durability
	shield_active = active
	shield_durability = clampf(ratio, 0.0, 1.0)
	_refresh()


func advance(delta: float) -> void:
	var changed := false
	if _local_bolt_timer and bolt_remaining > 0.0:
		bolt_remaining = maxf(0.0, bolt_remaining - delta)
		changed = true
	if _local_dash_timer and not dash_ready:
		dash_remaining = maxf(0.0, dash_remaining - delta)
		if dash_remaining <= 0.0:
			dash_ready = true
			_local_dash_timer = false
		changed = true
	if _damage_flash > 0.0:
		_damage_flash = maxf(0.0, _damage_flash - delta * 3.0)
		changed = true
	if changed:
		_refresh()


func is_bolt_ready() -> bool:
	return bolt_remaining <= 0.0


# --- view ----------------------------------------------------------------------

func _refresh() -> void:
	if panel == null:
		return
	health_bar.max_value = health_max
	health_bar.value = health_current
	health_label.text = "HP %d / %d" % [roundi(health_current), roundi(health_max)]
	_set_fill(health_bar, HEALTH_COLOR.lerp(Color.WHITE, _damage_flash * 0.6))

	var bolt_ratio := 1.0 - bolt_remaining / bolt_total
	bolt_bar.value = bolt_ratio
	bolt_label.text = "Bolt: Ready" if is_bolt_ready() else "Bolt: %.1fs" % bolt_remaining
	_set_fill(bolt_bar, BOLT_COLOR if is_bolt_ready() else BOLT_COLOR.lerp(DIM_COLOR, 0.5))

	if dashing:
		dash_bar.value = 0.0
		dash_label.text = "Dash: Dashing"
	elif dash_ready:
		dash_bar.value = 1.0
		dash_label.text = "Dash: Ready"
	else:
		dash_bar.value = 1.0 - dash_remaining / dash_total
		dash_label.text = "Dash: %.1fs" % dash_remaining
	_set_fill(dash_bar, DASH_COLOR if dash_ready else DASH_COLOR.lerp(DIM_COLOR, 0.5))

	shield_bar.value = shield_durability if shield_active else 0.0
	if shield_active:
		shield_label.text = "Shield: %d%%" % roundi(shield_durability * 100.0)
	elif shield_durability <= 0.0:
		shield_label.text = "Shield: Broken"
	else:
		shield_label.text = "Shield: Off"
	_set_fill(shield_bar, SHIELD_LOW_COLOR.lerp(SHIELD_COLOR, shield_durability))


func _set_fill(bar: ProgressBar, color: Color) -> void:
	var fill := bar.get_theme_stylebox(&"fill") as StyleBoxFlat
	if fill != null:
		fill.bg_color = color


func _ensure_built() -> void:
	if panel != null:
		return
	var root := Control.new()
	root.name = "CombatHUDRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	panel = PanelContainer.new()
	panel.name = "CombatPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 16.0
	panel.offset_top = -168.0
	panel.offset_right = 296.0
	panel.offset_bottom = -16.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.08, 0.1, 0.78)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(10)
	panel.add_theme_stylebox_override(&"panel", bg)
	root.add_child(panel)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override(&"separation", 4)
	panel.add_child(rows)

	var health := _add_row(rows, "Health", HEALTH_COLOR, 14.0)
	health_bar = health[0]
	health_label = health[1]
	var bolt := _add_row(rows, "MagicBolt", BOLT_COLOR, 8.0)
	bolt_bar = bolt[0]
	bolt_label = bolt[1]
	var dash := _add_row(rows, "Dash", DASH_COLOR, 8.0)
	dash_bar = dash[0]
	dash_label = dash[1]
	var shield := _add_row(rows, "PackageShield", SHIELD_COLOR, 8.0)
	shield_bar = shield[0]
	shield_label = shield[1]
	bolt_bar.max_value = 1.0
	dash_bar.max_value = 1.0
	shield_bar.max_value = 1.0


func _add_row(parent: Container, row_name: String, color: Color, bar_height: float) -> Array:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override(&"separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.name = "Label"
	label.custom_minimum_size = Vector2(118, 0)
	label.add_theme_font_size_override(&"font_size", 14)
	label.add_theme_color_override(&"font_color", Color(0.92, 0.94, 0.96))
	row.add_child(label)

	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.custom_minimum_size = Vector2(0, bar_height)
	bar.step = 0.0
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.15, 0.16, 0.2, 0.9)
	back.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override(&"background", back)
	bar.add_theme_stylebox_override(&"fill", fill)
	row.add_child(bar)
	return [bar, label]
