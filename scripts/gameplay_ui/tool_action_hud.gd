class_name ToolActionHUD
extends PanelContainer
## Bottom-centre panel for tool jobs (Phase 5H), driven by the courier's ToolUser:
## - working (chop, mine, dig, repair): "Chopping · Marked Tree", a stroke progress bar and
##   how to stop;
## - fishing: the cast, "Waiting for a bite...", then "Bite! [E] Hook it" with a bar that
##   empties over the bite window, then "Reeling in...";
## - idle with the rod in hand and open water ahead: "[Space] Cast your line".
## ToolUser feedback (refusals, results) goes to the quest toasts (QuestNotification).

const THEME := preload("res://scenes/gameplay/ui/gameplay_ui_theme.tres")
const GOLD := Color(1, 0.84, 0.3)
const VERBS := {&"tool_chop": "Chopping", &"tool_mine": "Mining", &"tool_dig": "Digging",
	&"tool_hammer": "Repairing", &"tool_trowel": "Re-setting"}

@export var player: PlayerController
@export var notifier: QuestNotification

var title_label: Label
var status_label: Label
var bar: ProgressBar
var hint_label: Label
var user: ToolUser = null
var _prompt_suppressed := false
var _prompt: InteractionPrompt = null


func _ready() -> void:
	theme = THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	_bind.call_deferred()


func _bind() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group(CombatController.PLAYER_GROUP) as PlayerController
	user = ToolUser.find_on(player)
	if user == null:
		return
	user.feedback.connect(func(text: String, kind: StringName) -> void:
		if notifier != null:
			notifier.push_message(text, kind))


func _process(_delta: float) -> void:
	if user == null:
		visible = false
		return
	# The "[E] Chop Marked Tree" prompt would repeat this panel while the job runs.
	if user.is_busy() != _prompt_suppressed:
		_prompt_suppressed = user.is_busy()
		var prompt := _find_prompt()
		if prompt != null:
			prompt.set_suppressed(_prompt_suppressed)
	match user.state:
		ToolUser.State.WORKING:
			_show_work()
		ToolUser.State.FISHING:
			_show_fishing()
		_:
			_show_idle()


func _show_work() -> void:
	var target := user.target
	var progress := user.get_progress()
	title_label.text = "%s · %s" % [VERBS.get(target.action, "Working"), target.display_name]
	status_label.text = "Stroke %d of %d" % [mini(progress.x + 1, progress.y), progress.y] if progress.x < progress.y else "Done!"
	bar.visible = true
	bar.max_value = progress.y
	bar.value = progress.x
	_set_stop_hint()
	visible = true


func _show_fishing() -> void:
	title_label.text = "Fishing · %s" % (user.target.display_name if user.target != null else "Willowmere Pond")
	bar.visible = false
	match user.fish_state:
		ToolUser.FishState.CASTING:
			status_label.text = "Casting..."
		ToolUser.FishState.WAITING:
			status_label.text = "Waiting for a bite... don't pull too soon"
		ToolUser.FishState.BITE:
			status_label.text = "A bite! [%s] Hook it now!" % InputHints.key_for(&"interact")
			bar.visible = true
			bar.max_value = 1.0
			bar.value = user.get_bite_time_left()
		ToolUser.FishState.REELING:
			status_label.text = "Reeling in..."
	_set_stop_hint()
	visible = true


func _show_idle() -> void:
	var tool := user.get_equipped_tool()
	if tool == null or tool.tool_type != ItemDefinition.ToolType.FISHING_ROD or not player.input_enabled \
			or user.find_water(user.get_bank_cast_point()) == null:
		visible = false
		return
	title_label.text = "Open water ahead"
	status_label.text = "[%s] Cast your line" % InputHints.key_for(&"combat_magic_bolt")
	bar.visible = false
	hint_label.visible = false
	visible = true


func _find_prompt() -> InteractionPrompt:
	if _prompt == null or not is_instance_valid(_prompt):
		var scene := get_tree().current_scene
		var found: Array[Node] = []
		if scene != null:
			found = scene.find_children("*", "InteractionPrompt", true, false)
		_prompt = found[0] as InteractionPrompt if not found.is_empty() else null
	return _prompt


func _set_stop_hint() -> void:
	hint_label.visible = true
	hint_label.text = "[%s] Stop" % InputHints.key_for(&"ui_cancel")


func _build() -> void:
	custom_minimum_size = Vector2(420, 0)
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 4)
	add_child(body)
	title_label = Label.new()
	title_label.add_theme_font_size_override(&"font_size", 20)
	title_label.add_theme_color_override(&"font_color", GOLD)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title_label)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(status_label)
	InputPromptLabel.attach(status_label)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	body.add_child(bar)
	hint_label = Label.new()
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override(&"font_size", 14)
	hint_label.add_theme_color_override(&"font_color", Color(0.75, 0.75, 0.85))
	body.add_child(hint_label)
	InputPromptLabel.attach(hint_label)
