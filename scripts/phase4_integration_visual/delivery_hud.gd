extends CanvasLayer
## Phase 4 integration delivery HUD. Self-contained; it does not touch the
## shared gameplay HUD or the Phase 4 combat HUD (bottom-left).
##   Top-right quest tracker: title, objective, state chip, distance to the
##     drop-off with a lime -> gold progress strip, and nearby threat count.
##   Top-centre package banner: persistent warnings from the bound package
##     (temperature / instability via PackageStatusProbe, plus integrity) and
##     transient alerts pushed by the encounter ("Package hit! -15",
##     "Shield absorbed the hit", "Shield broken!"). Alerts take priority while
##     they last; CRITICAL pulses red.
## Values are pushed in by the encounter presentation; animation runs from
## _process or manually via advance(delta) when auto_animate is false.

signal warning_level_changed(level: int)
signal alert_shown(text: String, level: int)

const Probe := preload("res://scripts/phase3_visual/package_status_probe.gd")
const LEVEL_NONE := 0  ## matches PackageStatusProbe.WarningLevel
const LEVEL_CAUTION := 1
const LEVEL_CRITICAL := 2
const CAUTION_INTEGRITY := 0.5
const CRITICAL_INTEGRITY := 0.25
const INFO_COLOR := Color(0.45, 0.95, 0.85)
const CAUTION_COLOR := Color(1.0, 0.82, 0.3)
const CRITICAL_COLOR := Color(1.0, 0.36, 0.3)
const PROGRESS_START := Color(0.55, 1.0, 0.35)
const PROGRESS_END := Color(1.0, 0.85, 0.3)
const QUEST_COLORS := {
	&"available": Color(0.4, 0.85, 1.0),
	&"active": Color(1.0, 0.85, 0.3),
	&"complete": Color(0.45, 1.0, 0.5),
	&"failed": Color(1.0, 0.35, 0.3),
}

@export var auto_animate := true
@export var alert_duration := 1.6
@export var arrive_radius := 2.5
## Live village uses GameplayHUD's authoritative active-quest tracker.
@export var use_shared_quest_tracker := false

var probe := Probe.new()
var quest_title := "Forest Delivery"
var objective_text := ""
var quest_state: StringName = &"active"
var distance := -1.0
var route_length := -1.0
var threats := 0
var warning_level := LEVEL_NONE
var warning_text := ""
var alert_text := ""
var alert_level := LEVEL_NONE
var alert_remaining := 0.0

var tracker_panel: PanelContainer
var title_label: Label
var state_label: Label
var objective_label: Label
var distance_label: Label
var threat_label: Label
var progress_bar: ProgressBar
var banner_panel: PanelContainer
var banner_label: Label

var _banner_style: StyleBoxFlat
var _progress_fill: StyleBoxFlat
var _has_quest := false  ## tracker stays hidden until a quest or route exists
var _package_signal := &""
var _package_callable := Callable()
var _time := 0.0


func _init() -> void:
	probe.status_changed.connect(_update_warning)


func _ready() -> void:
	layer = 7
	_ensure_built()
	_refresh_tracker()
	_update_warning()


func _process(delta: float) -> void:
	if auto_animate:
		advance(delta)


# --- quest tracker -------------------------------------------------------------

func set_quest(title: String, objective: String) -> void:
	_ensure_built()
	quest_title = title
	objective_text = objective
	_has_quest = true
	_refresh_tracker()


func set_quest_state(state: StringName) -> void:
	_ensure_built()
	quest_state = state
	_refresh_tracker()


## meters < 0 hides the distance row. total is the full route length.
func set_distance(meters: float, total := -1.0) -> void:
	_ensure_built()
	distance = meters
	if total > 0.0:
		route_length = total
	_refresh_tracker()


func set_threats(count: int) -> void:
	_ensure_built()
	threats = maxi(count, 0)
	_refresh_tracker()


func get_progress_ratio() -> float:
	if quest_state == &"complete":
		return 1.0
	if distance < 0.0 or route_length <= 0.0:
		return 0.0
	return clampf(1.0 - distance / route_length, 0.0, 1.0)


func get_distance_text() -> String:
	_ensure_built()
	return distance_label.text


# --- package -------------------------------------------------------------------

func bind_package(package: Object) -> void:
	unbind_package()
	if package == null:
		return
	probe.bind(package)
	if package.has_signal(&"damaged"):
		var args := _signal_arg_count(package, &"damaged")
		_package_signal = &"damaged"
		_package_callable = _on_package_damaged.unbind(args - 1) if args > 1 else _on_package_damaged
		if args == 0:
			_package_callable = _on_package_damaged.bind(0.0)
		package.connect(_package_signal, _package_callable)
	_update_warning()


func unbind_package() -> void:
	var package: Object = probe.target if probe.is_bound() else null
	if package != null and _package_signal != &"" and package.is_connected(_package_signal, _package_callable):
		package.disconnect(_package_signal, _package_callable)
	_package_signal = &""
	_package_callable = Callable()
	probe.unbind()
	_update_warning()


func get_bound_package() -> Object:
	return probe.target if probe.is_bound() else null


## Called on every courier hit while carrying. shielded hits read as info.
func notify_package_hit(amount: float, shielded: bool) -> void:
	if shielded:
		show_alert("Shield absorbed the hit", LEVEL_NONE)
	elif amount > 0.0:
		show_alert("Package hit! -%d" % roundi(amount), LEVEL_CRITICAL)
	else:
		show_alert("Package jolted!", LEVEL_CAUTION)


func show_alert(text: String, level := LEVEL_CAUTION) -> void:
	_ensure_built()
	alert_text = text
	alert_level = level
	alert_remaining = alert_duration
	_refresh_banner()
	alert_shown.emit(text, level)


func get_warning_level() -> int:
	return warning_level


func get_warning_text() -> String:
	return warning_text


func get_alert_text() -> String:
	return alert_text if alert_remaining > 0.0 else ""


## Text currently on the banner (alert first, then the persistent warning).
func get_banner_text() -> String:
	_ensure_built()
	return banner_label.text if banner_panel.visible else ""


func is_banner_visible() -> bool:
	return banner_panel != null and banner_panel.visible


func advance(delta: float) -> void:
	_time += delta
	if probe.needs_polling():
		probe.poll()
	if alert_remaining > 0.0:
		alert_remaining = maxf(0.0, alert_remaining - delta)
		if alert_remaining <= 0.0:
			alert_text = ""
	_refresh_banner()


# --- view ----------------------------------------------------------------------

func _update_warning() -> void:
	var level := _compute_level()
	warning_text = _build_warning_text() if level != LEVEL_NONE else ""
	if level != warning_level:
		warning_level = level
		warning_level_changed.emit(level)
	_refresh_banner()


func _compute_level() -> int:
	if not probe.is_bound():
		return LEVEL_NONE
	var level := probe.get_warning_level()
	if probe.has_integrity():
		var r := probe.get_integrity_ratio()
		if r <= CRITICAL_INTEGRITY:
			level = LEVEL_CRITICAL
		elif r <= CAUTION_INTEGRITY:
			level = maxi(level, LEVEL_CAUTION)
	return level


func _build_warning_text() -> String:
	if not probe.is_bound():
		return ""
	var parts := PackedStringArray()
	var bias := probe.get_temperature_bias()
	if bias >= Probe.CRITICAL_TEMPERATURE_DANGER:
		parts.append("OVERHEATING!")
	elif bias > 0.0:
		parts.append("Too warm")
	elif bias <= -Probe.CRITICAL_TEMPERATURE_DANGER:
		parts.append("FREEZING!")
	elif bias < 0.0:
		parts.append("Too cold")
	var instability := probe.get_instability_ratio()
	if instability >= Probe.CRITICAL_INSTABILITY:
		parts.append("VOLATILE!")
	elif instability >= Probe.CAUTION_INSTABILITY:
		parts.append("Unstable")
	if probe.has_integrity():
		var r := probe.get_integrity_ratio()
		if r <= CRITICAL_INTEGRITY:
			parts.append("BREAKING! %d%%" % roundi(r * 100.0))
		elif r <= CAUTION_INTEGRITY:
			parts.append("Damaged %d%%" % roundi(r * 100.0))
	if parts.is_empty():
		return ""
	return "%s: %s" % [probe.get_display_name(), " | ".join(parts)]


func _refresh_banner() -> void:
	if banner_panel == null:
		return
	var alerting := alert_remaining > 0.0 and alert_text != ""
	var text := alert_text if alerting else warning_text
	var level := alert_level if alerting else warning_level
	banner_panel.visible = text != ""
	banner_label.text = text
	if text == "":
		return
	var color := CRITICAL_COLOR if level == LEVEL_CRITICAL else (CAUTION_COLOR if level == LEVEL_CAUTION else INFO_COLOR)
	var k := 0.5 + 0.5 * sin(_time * 10.0) if level == LEVEL_CRITICAL else 0.0
	_banner_style.bg_color = color.darkened(0.75).lerp(color.darkened(0.45), k)
	_banner_style.border_color = color
	banner_label.add_theme_color_override(&"font_color", color.lightened(0.35))
	banner_panel.modulate.a = minf(1.0, alert_remaining * 4.0) if alerting else 1.0


func _refresh_tracker() -> void:
	if tracker_panel == null:
		return
	tracker_panel.visible = not use_shared_quest_tracker and quest_state != &"hidden" and (_has_quest or distance >= 0.0)
	var state_color: Color = QUEST_COLORS.get(quest_state, QUEST_COLORS[&"active"])
	title_label.text = quest_title
	title_label.add_theme_color_override(&"font_color", state_color.lightened(0.2))
	state_label.text = String(quest_state).capitalize()
	state_label.add_theme_color_override(&"font_color", state_color)
	objective_label.text = objective_text
	objective_label.visible = objective_text != ""
	if quest_state == &"complete":
		distance_label.text = "Delivered!"
	elif quest_state == &"failed":
		distance_label.text = "Delivery failed"
	elif distance < 0.0:
		distance_label.text = ""
	elif distance <= arrive_radius:
		distance_label.text = "Arrived - hand over the package"
	else:
		distance_label.text = "%d m to drop-off" % roundi(distance)
	distance_label.visible = distance_label.text != ""
	var ratio := get_progress_ratio()
	progress_bar.value = ratio
	progress_bar.visible = route_length > 0.0 or quest_state == &"complete"
	_progress_fill.bg_color = PROGRESS_START.lerp(PROGRESS_END, ratio) if quest_state != &"failed" else CRITICAL_COLOR
	threat_label.text = "Threats nearby: %d" % threats
	threat_label.visible = threats > 0


func _ensure_built() -> void:
	if tracker_panel != null:
		return
	var root := Control.new()
	root.name = "DeliveryHUDRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	tracker_panel = PanelContainer.new()
	tracker_panel.name = "QuestTracker"
	tracker_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tracker_panel.anchor_left = 1.0
	tracker_panel.anchor_right = 1.0
	tracker_panel.offset_left = -316.0
	tracker_panel.offset_top = 16.0
	tracker_panel.offset_right = -16.0
	tracker_panel.offset_bottom = 136.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.1, 0.07, 0.8)
	bg.border_color = Color(0.55, 1.0, 0.35, 0.6)
	bg.border_width_left = 3
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(10)
	tracker_panel.add_theme_stylebox_override(&"panel", bg)
	root.add_child(tracker_panel)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override(&"separation", 3)
	tracker_panel.add_child(rows)
	var header := HBoxContainer.new()
	header.name = "Header"
	rows.add_child(header)
	title_label = _label(header, "Title", 17)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state_label = _label(header, "State", 13)
	objective_label = _label(rows, "Objective", 14)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	distance_label = _label(rows, "Distance", 14)
	progress_bar = ProgressBar.new()
	progress_bar.name = "RouteProgress"
	progress_bar.show_percentage = false
	progress_bar.max_value = 1.0
	progress_bar.step = 0.0
	progress_bar.custom_minimum_size = Vector2(0, 8)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.15, 0.18, 0.15, 0.9)
	back.set_corner_radius_all(3)
	_progress_fill = StyleBoxFlat.new()
	_progress_fill.bg_color = PROGRESS_START
	_progress_fill.set_corner_radius_all(3)
	progress_bar.add_theme_stylebox_override(&"background", back)
	progress_bar.add_theme_stylebox_override(&"fill", _progress_fill)
	rows.add_child(progress_bar)
	threat_label = _label(rows, "Threats", 13)
	threat_label.add_theme_color_override(&"font_color", Color(1.0, 0.6, 0.5))

	banner_panel = PanelContainer.new()
	banner_panel.name = "PackageBanner"
	banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_panel.anchor_left = 0.5
	banner_panel.anchor_right = 0.5
	banner_panel.offset_left = -240.0
	banner_panel.offset_right = 240.0
	banner_panel.offset_top = 132.0
	banner_panel.offset_bottom = 174.0
	_banner_style = StyleBoxFlat.new()
	_banner_style.bg_color = CAUTION_COLOR.darkened(0.75)
	_banner_style.border_color = CAUTION_COLOR
	_banner_style.set_border_width_all(2)
	_banner_style.set_corner_radius_all(8)
	_banner_style.set_content_margin_all(8)
	banner_panel.add_theme_stylebox_override(&"panel", _banner_style)
	root.add_child(banner_panel)
	banner_label = _label(banner_panel, "Text", 18)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_panel.visible = false


func _label(parent: Control, label_name: String, size: int) -> Label:
	var label := Label.new()
	label.name = label_name
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", Color(0.92, 0.95, 0.9))
	parent.add_child(label)
	return label


func _on_package_damaged(amount) -> void:
	var value := float(amount) if (amount is float or amount is int) else 0.0
	show_alert("Package damaged! -%d" % roundi(value) if value > 0.0 else "Package damaged!", LEVEL_CRITICAL)


static func _signal_arg_count(target: Object, signal_name: StringName) -> int:
	for info: Dictionary in target.get_signal_list():
		if StringName(info["name"]) == signal_name:
			return (info["args"] as Array).size()
	return 0
