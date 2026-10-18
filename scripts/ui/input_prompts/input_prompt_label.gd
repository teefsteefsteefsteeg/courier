class_name InputPromptLabel
extends Control
## Draws a hint Label's "[Key] text" with pixel-art keycaps, e.g. "[E] Talk   [Escape] Close".
##
## Attach with InputPromptLabel.attach(label). The Label keeps its text (code and tests
## still read and write label.text; key names come from the InputMap via InputHints), and
## only its own glyphs are hidden (self_modulate) while this overlay draws the same line
## with icons. Text without "[Key]" tokens is left to the Label. The overlay copies the
## Label's font size, colours and alignment, follows text changes, and grows the Label's
## minimum height so containers make room for the 32 px keycaps. Text in a wrapping
## Label keeps wrapping within the Label's width.

const NODE_NAME := &"InputPromptOverlay"
## Space added after a segment that ends with two or more spaces (hint groups).
const GROUP_GAP := 14.0

var label: Label = null
## Keycaps currently shown (read by tests).
var keycaps: Array[Control] = []
var _content: VBoxContainer = null
var _shown_key := ""
var _label_alpha: float = 1.0
var _label_min_height: float = 0.0


## Adds (or returns the existing) overlay on label.
static func attach(target: Label) -> InputPromptLabel:
	var existing := target.get_node_or_null(NodePath(NODE_NAME)) as InputPromptLabel
	if existing != null:
		return existing
	var overlay := InputPromptLabel.new()
	overlay.name = NODE_NAME
	target.add_child(overlay)
	return overlay


func _ready() -> void:
	label = get_parent() as Label
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if label != null:
		_label_alpha = label.self_modulate.a
		_label_min_height = label.custom_minimum_size.y
	set_process(label != null)


func _process(_delta: float) -> void:
	var key := "%s|%s|%d|%d" % [label.text, label.get_theme_color(&"font_color").to_html(), label.horizontal_alignment, label.get_theme_font_size(&"font_size")]
	if key != _shown_key:
		_shown_key = key
		rebuild()
	if _content != null:
		_layout()


## True while the overlay draws the label (its text has at least one key token).
func is_active() -> bool:
	return _content != null


func rebuild() -> void:
	keycaps.clear()
	if _content != null:
		_content.queue_free()
		_content = null
	var lines := parse(label.text)
	var has_key := lines.any(func(line: Array) -> bool: return line.any(func(s: Dictionary) -> bool: return s.has("key")))
	if not has_key:
		label.self_modulate.a = _label_alpha
		label.custom_minimum_size.y = _label_min_height
		return
	var font_size := label.get_theme_font_size(&"font_size")
	_content = VBoxContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override(&"separation", 2)
	for line in lines:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override(&"separation", 6)
		match label.horizontal_alignment:
			HORIZONTAL_ALIGNMENT_CENTER: row.alignment = BoxContainer.ALIGNMENT_CENTER
			HORIZONTAL_ALIGNMENT_RIGHT: row.alignment = BoxContainer.ALIGNMENT_END
		for segment: Dictionary in line:
			if segment.has("key"):
				var key_name: String = segment["key"]
				var texture := InputPromptIcons.texture_for_key_name(key_name)
				var keycap: Control = InputPrompt.make_icon(texture) if texture != null else InputPrompt.make_fallback_keycap(key_name, 1, font_size)
				keycap.set_meta(&"key", key_name)
				keycaps.append(keycap)
				row.add_child(keycap)
			else:
				row.add_child(_text_part(segment["text"]))
			if segment.get("gap", false):
				var spacer := Control.new()
				spacer.custom_minimum_size.x = GROUP_GAP
				row.add_child(spacer)
		# Only the row's last text part takes the spare width (and wraps); earlier parts
		# stay at their natural size so "[J] Journal  [M] Map" keeps its spacing.
		var texts := row.get_children().filter(func(c: Node) -> bool: return c is Label)
		for i in texts.size() - 1:
			var part := texts[i] as Label
			part.autowrap_mode = TextServer.AUTOWRAP_OFF
			part.size_flags_horizontal = Control.SIZE_FILL
		_content.add_child(row)
	add_child(_content)
	label.self_modulate.a = 0.0
	_layout()


## Splits text into lines of segments: {key: "E"} for "[E]" tokens that name a key (or
## "?" for an unbound action), {text: "..."} otherwise; gap marks a wide space after.
static func parse(text: String) -> Array:
	var lines: Array = []
	var token := RegEx.create_from_string("\\[([^\\[\\]]+)\\]")
	for line_text in text.split("\n"):
		var segments: Array = []
		var at := 0
		for match_ in token.search_all(line_text):
			var key_name := match_.get_string(1)
			if key_name != "?" and OS.find_keycode_from_string(key_name) == KEY_NONE:
				continue
			_add_text(segments, line_text.substr(at, match_.get_start() - at))
			segments.append({"key": key_name})
			at = match_.get_end()
		_add_text(segments, line_text.substr(at))
		lines.append(segments)
	return lines


static func _add_text(segments: Array, part: String) -> void:
	var wide := part.ends_with("  ")
	var trimmed := part.strip_edges()
	if not trimmed.is_empty():
		segments.append({"text": trimmed, "gap": wide})
	elif wide and not segments.is_empty():
		segments[-1]["gap"] = true


func _text_part(part: String) -> Label:
	var text_label := Label.new()
	text_label.text = part
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_label.add_theme_font_size_override(&"font_size", label.get_theme_font_size(&"font_size"))
	text_label.add_theme_font_override(&"font", label.get_theme_font(&"font"))
	text_label.add_theme_color_override(&"font_color", label.get_theme_color(&"font_color"))
	text_label.add_theme_color_override(&"font_outline_color", label.get_theme_color(&"font_outline_color"))
	text_label.add_theme_constant_override(&"outline_size", label.get_theme_constant(&"outline_size"))
	if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		# Wrapping labels keep wrapping: the text takes the row's remaining width.
		text_label.autowrap_mode = label.autowrap_mode
		text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return text_label


func _layout() -> void:
	var needed := _content.get_combined_minimum_size()
	var min_height := maxf(_label_min_height, needed.y)
	if not is_equal_approx(label.custom_minimum_size.y, min_height):
		label.custom_minimum_size.y = min_height
	position = Vector2.ZERO
	size = label.size
	var width := label.size.x if label.autowrap_mode != TextServer.AUTOWRAP_OFF else maxf(label.size.x, needed.x)
	var x := 0.0
	match label.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER: x = (label.size.x - width) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT: x = label.size.x - width
	_content.position = Vector2(x, maxf(0.0, (label.size.y - needed.y) * 0.5))
	_content.size = Vector2(width, needed.y)
