class_name PackageStatusHUD
extends Control
## Self-contained temperature / instability readout for one package. Bind any
## PackageInstance with bind_package(); features are detected through
## PackageStatusProbe, so rows only appear for status the package exposes and
## the whole widget hides when there is nothing to show. Updates on the
## package's change signals, falling back to per-frame polling without them.
## Warnings animate: CAUTION pulses the warning line, CRITICAL flashes the
## panel red and shakes it on escalation.

signal warning_level_changed(level: int)

const TEMPERATURE_SAFE_COLOR := Color(0.95, 0.7, 0.3)
const TEMPERATURE_COLD_COLOR := Color(0.4, 0.7, 1.0)
const TEMPERATURE_HOT_COLOR := Color(1.0, 0.3, 0.12)
const STABLE_COLOR := Color(0.4, 0.9, 0.5)
const UNSTABLE_COLOR := Color(1.0, 0.25, 0.2)
const CAUTION_TEXT_COLOR := Color(1.0, 0.85, 0.35)
const CRITICAL_TEXT_COLOR := Color(1.0, 0.35, 0.28)
const CRITICAL_PANEL_TINT := Color(1.0, 0.55, 0.5)

## Hide the widget when the bound package exposes neither feature.
@export var auto_hide := true
@export var shake_pixels := 5.0

@onready var _panel: PanelContainer = $Panel
@onready var _title: Label = $Panel/Rows/Title
@onready var _temperature_row: Control = $Panel/Rows/TemperatureRow
@onready var _temperature_bar: ProgressBar = $Panel/Rows/TemperatureRow/Bar
@onready var _safe_band: ColorRect = $Panel/Rows/TemperatureRow/Bar/SafeBand
@onready var _temperature_value: Label = $Panel/Rows/TemperatureRow/Value
@onready var _instability_row: Control = $Panel/Rows/InstabilityRow
@onready var _instability_bar: ProgressBar = $Panel/Rows/InstabilityRow/Bar
@onready var _instability_value: Label = $Panel/Rows/InstabilityRow/Value
@onready var _warning_label: Label = $Panel/Rows/Warning

var probe := PackageStatusProbe.new()

var _warning_level: int = PackageStatusProbe.WarningLevel.NONE
var _warning_text := ""
var _temperature_fill: StyleBoxFlat
var _instability_fill: StyleBoxFlat
var _pulse_tween: Tween
var _shake_tween: Tween
var _panel_rest := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_temperature_fill = _own_fill(_temperature_bar)
	_instability_fill = _own_fill(_instability_bar)
	_panel_rest = _panel.position
	probe.status_changed.connect(refresh)
	refresh()


func _process(_delta: float) -> void:
	if probe.needs_polling():
		probe.poll()


func bind_package(package: Object) -> void:
	probe.bind(package)
	refresh()


func unbind_package() -> void:
	probe.unbind()
	refresh()


func get_bound_package() -> Object:
	return probe.target if probe.is_bound() else null


func get_warning_level() -> int:
	return _warning_level


func get_warning_text() -> String:
	return _warning_text


func is_temperature_shown() -> bool:
	return _temperature_row.visible


func is_instability_shown() -> bool:
	return _instability_row.visible


func is_warning_animating() -> bool:
	return _pulse_tween != null and _pulse_tween.is_valid()


func refresh() -> void:
	if not is_node_ready():
		return
	var show_temperature := probe.has_temperature()
	var show_instability := probe.has_instability()
	visible = show_temperature or show_instability or not auto_hide
	_title.text = probe.get_display_name()
	_temperature_row.visible = show_temperature
	_instability_row.visible = show_instability
	if show_temperature:
		_refresh_temperature()
	if show_instability:
		_refresh_instability()
	_set_warning(probe.get_warning_level() if probe.is_bound() else PackageStatusProbe.WarningLevel.NONE)


func _refresh_temperature() -> void:
	var limits := probe.get_temperature_limits()
	var safe := probe.get_safe_temperature_range()
	var span := limits.y - limits.x
	_temperature_bar.value = probe.get_temperature_ratio()
	_safe_band.set_anchor(SIDE_LEFT, (safe.x - limits.x) / span, false, false)
	_safe_band.set_anchor(SIDE_RIGHT, (safe.y - limits.x) / span, false, false)
	var bias := probe.get_temperature_bias()
	if bias >= 0.0:
		_temperature_fill.bg_color = TEMPERATURE_SAFE_COLOR.lerp(TEMPERATURE_HOT_COLOR, bias)
	else:
		_temperature_fill.bg_color = TEMPERATURE_SAFE_COLOR.lerp(TEMPERATURE_COLD_COLOR, -bias)
	_temperature_value.text = "%d°" % roundi(probe.get_temperature())


func _refresh_instability() -> void:
	var ratio := probe.get_instability_ratio()
	_instability_bar.value = ratio
	_instability_fill.bg_color = STABLE_COLOR.lerp(UNSTABLE_COLOR, ratio)
	_instability_value.text = "%d%%" % roundi(ratio * 100.0)


func _build_warning_text() -> String:
	var parts := PackedStringArray()
	var bias := probe.get_temperature_bias()
	if bias >= PackageStatusProbe.CRITICAL_TEMPERATURE_DANGER:
		parts.append("OVERHEATING!")
	elif bias > 0.0:
		parts.append("Too warm")
	elif bias <= -PackageStatusProbe.CRITICAL_TEMPERATURE_DANGER:
		parts.append("FREEZING!")
	elif bias < 0.0:
		parts.append("Too cold")
	var ratio := probe.get_instability_ratio()
	if ratio >= PackageStatusProbe.CRITICAL_INSTABILITY:
		parts.append("VOLATILE!")
	elif ratio >= PackageStatusProbe.CAUTION_INSTABILITY:
		parts.append("Unstable")
	return " | ".join(parts)


func _set_warning(level: int) -> void:
	_warning_text = _build_warning_text() if level != PackageStatusProbe.WarningLevel.NONE else ""
	_warning_label.text = _warning_text
	_warning_label.visible = level != PackageStatusProbe.WarningLevel.NONE
	if level == _warning_level:
		return
	_warning_level = level
	_play_warning_animation()
	warning_level_changed.emit(level)


func _play_warning_animation() -> void:
	_stop_warning_animation()
	if not is_inside_tree():
		return
	match _warning_level:
		PackageStatusProbe.WarningLevel.CAUTION:
			_warning_label.add_theme_color_override(&"font_color", CAUTION_TEXT_COLOR)
			_pulse_tween = create_tween().set_loops()
			_pulse_tween.tween_property(_warning_label, "modulate:a", 0.4, 0.5).set_trans(Tween.TRANS_SINE)
			_pulse_tween.tween_property(_warning_label, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
		PackageStatusProbe.WarningLevel.CRITICAL:
			_warning_label.add_theme_color_override(&"font_color", CRITICAL_TEXT_COLOR)
			_pulse_tween = create_tween().set_loops()
			_pulse_tween.tween_property(_panel, "modulate", CRITICAL_PANEL_TINT, 0.18)
			_pulse_tween.tween_property(_panel, "modulate", Color.WHITE, 0.18)
			_shake_tween = create_tween()
			for i in 6:
				var direction := 1.0 if i % 2 == 0 else -1.0
				_shake_tween.tween_property(_panel, "position:x", _panel_rest.x + direction * shake_pixels, 0.04)
			_shake_tween.tween_property(_panel, "position:x", _panel_rest.x, 0.04)


func _stop_warning_animation() -> void:
	for tween: Tween in [_pulse_tween, _shake_tween]:
		if tween != null and tween.is_valid():
			tween.kill()
	_pulse_tween = null
	_shake_tween = null
	_panel.modulate = Color.WHITE
	_panel.position = _panel_rest
	_warning_label.modulate = Color.WHITE


static func _own_fill(bar: ProgressBar) -> StyleBoxFlat:
	var fill := bar.get_theme_stylebox(&"fill")
	var own: StyleBoxFlat = fill.duplicate() as StyleBoxFlat if fill is StyleBoxFlat else StyleBoxFlat.new()
	bar.add_theme_stylebox_override(&"fill", own)
	return own
