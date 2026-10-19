extends CanvasLayer
## Courier status HUD (top-left): circular portrait with the rank badge, rank title,
## ruby health bar, sapphire Package Shield energy bar, golden reputation (EXP) bar
## towards the next courier rank, and the magic bolt / dash readiness chips.
##
## Values are pushed in by the combat visual adapter (or the showcase preview), as in
## Phase 4: set_health, set_bolt_cooldown / start_bolt_cooldown, set_dash_state /
## start_dash_cooldown, set_shield_state. Progression comes from the CourierWallet
## (found by group) or set_progression. The bars show exact values; changes animate on
## top of them: lost health or shield leaves a pale chip that drains away, healing
## flashes the restored segment, reputation slides the EXP bar, and a rank-up pulses the
## badge. Layout uses containers anchored to the top-left and scales down on small screens.
## Phase 8: real MP and rage bars from CourierVitals (found by group): MP drains with staff
## bolts and the Arcane Storm and regenerates; rage fills with hits and glows with "[ultimate
## key] READY" when the +5 weapon's ultimate can be released (WeaponUltimates.is_ready()). Active
## food and potion buffs show as icons with their seconds left.

const BOLT_COLOR := Color(0.7, 0.5, 1.0)
const DASH_COLOR := Color(0.45, 0.85, 1.0)
const SHIELD_LOW_COLOR := Color(1.0, 0.45, 0.2)
const DIM_COLOR := Color(0.35, 0.35, 0.4)
const GOLD := Color(0.83, 0.68, 0.38)
const GOLD_BRIGHT := Color(1.0, 0.86, 0.5)
const IVORY := Color(0.96, 0.92, 0.84)
const PANEL_COLOR := Color(0.11, 0.085, 0.07, 0.9)
const TRACK_COLOR := Color(0.05, 0.04, 0.035, 0.95)
const PORTRAIT := preload("res://assets/ui/hud/courier_portrait.png")
const CIRCLE_MASK := preload("res://assets/shaders/circle_mask.gdshader")
## Height (px of the logical viewport) at which the HUD is drawn at full size.
const FULL_SCALE_HEIGHT := 820.0
const MIN_SCALE := 0.72
const MARGIN := 16.0

@export var auto_animate := true
## Courier name shown above the bars; empty = the courier's rank title.
@export var display_name := ""

var panel: PanelContainer
var portrait: TextureRect
## The animated courier shown in the portrait (Phase 8).
var live_portrait: AnimatedPortrait
var level_badge: PanelContainer
var level_label: Label
var name_label: Label
var health_bar: ProgressBar
var health_label: Label
var health_trail: ProgressBar
var heal_flash: ColorRect
var shield_bar: ProgressBar
var shield_label: Label
var shield_trail: ProgressBar
var exp_bar: ProgressBar
var exp_label: Label
var bolt_bar: ProgressBar
var bolt_label: Label
var dash_bar: ProgressBar
var dash_label: Label
var mana_bar: ProgressBar
var mana_label: Label
var rage_bar: ProgressBar
var rage_label: Label
## Active buffs: one icon + seconds label each.
var buff_row: HBoxContainer

var health_current := 100.0
var health_max := 100.0
var bolt_remaining := 0.0
var bolt_total := 1.0
var dash_ready := true
var dashing := false
var dash_remaining := 0.0
var dash_total := 1.0
var stamina := -1.0
var stamina_max := 100.0
var stamina_cost := 0.0
var shield_active := false
var shield_durability := 0.0
var rank := 0
var rank_title := "Novice Courier"
var rank_progress := 0.0
var reputation := 0
var reputation_to_next := 0
var mana_current := 100.0
var mana_max := 100.0
var rage_current := 0.0
var rage_max := 100.0
var ultimate_ready := false

var _local_bolt_timer := false
var _local_dash_timer := false
var _damage_flash := 0.0
var _heal_flash := 0.0
var _heal_from := 0.0
var _heal_to := 0.0
var _badge_pulse := 0.0
var _low_pulse := 0.0
var _exp_shown := 0.0
var _wallet: CourierWallet = null
var _vitals: CourierVitals = null
var _rage_pulse := 0.0
var _rage_fill: StyleBoxTexture
var _combat: CombatController = null
var _bind_left := 0.0
var _health_fill: StyleBoxTexture
var _shield_fill: StyleBoxTexture
var _bolt_fill: StyleBoxFlat
var _dash_fill: StyleBoxFlat


func _ready() -> void:
	layer = 6
	_ensure_built()
	_refresh()


func _process(delta: float) -> void:
	if auto_animate:
		advance(delta)
	_bind_services(delta)
	_layout()


# --- pushed values -------------------------------------------------------------

func set_health(current: float, maximum: float) -> void:
	_ensure_built()
	var new_max := maxf(maximum, 0.001)
	var new_current := clampf(current, 0.0, new_max)
	if new_current < health_current:
		_damage_flash = 1.0
		if live_portrait != null:
			live_portrait.react_damage()
	elif new_current > health_current + 0.01 * new_max:
		_heal_from = health_current / new_max
		_heal_to = new_current / new_max
		_heal_flash = 1.0
	if live_portrait != null:
		live_portrait.set_health_ratio(new_current / new_max)
	health_max = new_max
	health_current = new_current
	health_trail.max_value = health_max
	if health_trail.value < health_current or not auto_animate:
		health_trail.value = health_current
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


## Real dash stamina from the CombatController. Once known, the Dash chip's bar shows it
## and the label reads "Dash: Tired" while a dash cannot be afforded.
func set_stamina(current: float, maximum: float, dash_cost: float = 0.0) -> void:
	_ensure_built()
	stamina_max = maxf(maximum, 0.001)
	stamina = clampf(current, 0.0, stamina_max)
	stamina_cost = dash_cost
	_refresh()


func has_dash_stamina() -> bool:
	return stamina < 0.0 or stamina >= stamina_cost


## durability: 0..1 ratio, or the controller's raw durability (above 1). Raw values are
## divided by the courier's shield maximum when the CombatController is known, otherwise
## read as a percentage (the standalone preview).
func set_shield_state(active: bool, durability: float) -> void:
	_ensure_built()
	var ratio := durability
	if durability > 1.0:
		var maximum := _combat.shield_max_durability if _combat != null else 100.0
		ratio = durability / maxf(maximum, 0.001)
	shield_active = active
	shield_durability = clampf(ratio, 0.0, 1.0)
	if shield_trail.value < shield_durability or not auto_animate:
		shield_trail.value = shield_durability
	_refresh()


## Courier rank (0-based), its title, and reputation progress towards the next rank.
func set_progression(new_rank: int, title: String, progress: float, value: int, to_next: int) -> void:
	_ensure_built()
	if new_rank > rank:
		_badge_pulse = 1.0
	rank = new_rank
	rank_title = title
	rank_progress = clampf(progress, 0.0, 1.0)
	reputation = value
	reputation_to_next = to_next
	if not auto_animate:
		_exp_shown = rank_progress
	_refresh()


## Real MP from CourierVitals.
func set_mana(current: float, maximum: float) -> void:
	_ensure_built()
	mana_max = maxf(maximum, 0.001)
	mana_current = clampf(current, 0.0, mana_max)
	_refresh()


## Real rage from CourierVitals; ready = the held weapon's ultimate can be released now.
func set_rage(current: float, maximum: float, ready: bool = ultimate_ready) -> void:
	_ensure_built()
	rage_max = maxf(maximum, 0.001)
	rage_current = clampf(current, 0.0, rage_max)
	ultimate_ready = ready
	_refresh()


func advance(delta: float) -> void:
	var changed := false
	if ultimate_ready:
		_rage_pulse = fmod(_rage_pulse + delta * 4.0, TAU)
		changed = true
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
	# Damage chips hold for a beat, then drain; bigger chips drain faster.
	if health_trail != null and health_trail.value > health_current and _damage_flash < 0.6:
		var gap := health_trail.value - health_current
		health_trail.value = maxf(health_current, health_trail.value - delta * maxf(gap * 2.2, health_max * 0.15))
	if shield_trail != null and shield_trail.value > shield_durability:
		var shield_gap := shield_trail.value - shield_durability
		shield_trail.value = maxf(shield_durability, shield_trail.value - delta * maxf(shield_gap * 2.2, 0.15))
	if _heal_flash > 0.0:
		_heal_flash = maxf(0.0, _heal_flash - delta * 1.6)
		changed = true
	if _badge_pulse > 0.0:
		_badge_pulse = maxf(0.0, _badge_pulse - delta * 0.8)
		changed = true
	if health_current <= health_max * 0.25 and health_current > 0.0:
		_low_pulse = fmod(_low_pulse + delta * 2.2, TAU)
		changed = true
	elif _low_pulse != 0.0:
		_low_pulse = 0.0
		changed = true
	if not is_equal_approx(_exp_shown, rank_progress):
		_exp_shown = move_toward(_exp_shown, rank_progress, delta * 0.8)
		changed = true
	if changed:
		_refresh()


func is_bolt_ready() -> bool:
	return bolt_remaining <= 0.0


# --- services --------------------------------------------------------------------

## Finds the CourierWallet (rank and reputation) and the courier's CombatController
## (shield maximum) once they exist; retries once a second.
func _bind_services(delta: float) -> void:
	_poll_vitals()
	if _wallet != null and _combat != null and _vitals != null:
		return
	_bind_left -= delta
	if _bind_left > 0.0 or not is_inside_tree():
		return
	_bind_left = 1.0
	if _wallet == null:
		_wallet = CourierWallet.find(get_tree())
		if _wallet != null:
			_wallet.reputation_changed.connect(func(_v, _d): _pull_progression())
			_wallet.rank_changed.connect(func(_n, _o): _pull_progression())
			_pull_progression()
	if _combat == null:
		_combat = CombatController.find_on(get_tree().get_first_node_in_group(CombatController.PLAYER_GROUP))
		if _combat != null:
			set_shield_state(_combat.is_shield_active(), _combat.get_shield_durability())
	if _vitals == null:
		_vitals = CourierVitals.find(get_tree())
		if _vitals != null:
			_vitals.mana_changed.connect(set_mana)
			_vitals.buffs_changed.connect(_rebuild_buffs)
			set_mana(_vitals.get_mana(), _vitals.max_mana)
			_rebuild_buffs()


## Rage, the ultimate's readiness and the buffs' seconds change every frame: polled.
func _poll_vitals() -> void:
	if _vitals == null or not is_instance_valid(_vitals):
		return
	var ultimates := WeaponUltimates.find(get_tree())
	var ready := ultimates != null and ultimates.is_ready()
	if not is_equal_approx(_vitals.get_rage(), rage_current) or ready != ultimate_ready:
		set_rage(_vitals.get_rage(), _vitals.max_rage, ready)
	for i in mini(buff_row.get_child_count(), _vitals.buffs.size()):
		var label := buff_row.get_child(i).get_node(^"Time") as Label
		label.text = "%ds" % ceili(float(_vitals.buffs[i]["remaining"]))


func _rebuild_buffs() -> void:
	for child in buff_row.get_children():
		buff_row.remove_child(child)
		child.queue_free()
	if _vitals == null:
		return
	for buff in _vitals.buffs:
		var item := buff["item"] as ConsumableItem
		var chip := HBoxContainer.new()
		chip.name = String(buff["id"])
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_theme_constant_override(&"separation", 2)
		chip.tooltip_text = "%s: %s" % [buff["name"], ", ".join(item.get_effect_lines())]
		var icon := TextureRect.new()
		icon.texture = item.icon
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(20, 20)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(icon)
		var time := _label(11, Color(0.86, 1.0, 0.8))
		time.name = "Time"
		chip.add_child(time)
		buff_row.add_child(chip)
	buff_row.visible = buff_row.get_child_count() > 0


func _pull_progression() -> void:
	if _wallet != null:
		set_progression(_wallet.get_rank(), _wallet.get_rank_title(), _wallet.get_rank_progress(), _wallet.reputation, _wallet.get_reputation_to_next_rank())


# --- view ----------------------------------------------------------------------

func _refresh() -> void:
	if panel == null:
		return
	health_bar.max_value = health_max
	health_bar.value = health_current
	health_label.text = "HP %d / %d" % [roundi(health_current), roundi(health_max)]
	var low := health_current <= health_max * 0.25
	var glow := maxf(_damage_flash * 0.5, (0.5 + 0.5 * sin(_low_pulse)) * 0.35 if low else 0.0)
	_health_fill.modulate_color = Color.WHITE.lerp(Color(1.6, 1.35, 1.35), glow)
	health_label.add_theme_color_override(&"font_color", Color(1.0, 0.78, 0.74) if low else IVORY)
	# The live portrait flushes red with a hit and pulses red while health is low.
	if portrait != null:
		var red := maxf(_damage_flash * 0.75, (0.5 + 0.5 * sin(_low_pulse)) * 0.45 if low else 0.0)
		portrait.self_modulate = Color.WHITE.lerp(Color(1.0, 0.45, 0.42), red)
	heal_flash.visible = _heal_flash > 0.0
	if heal_flash.visible:
		var track := heal_flash.get_parent() as Control
		heal_flash.position = Vector2(track.size.x * _heal_from, 1)
		heal_flash.size = Vector2(track.size.x * maxf(_heal_to - _heal_from, 0.0), track.size.y - 2)
		heal_flash.color = Color(1.0, 0.95, 0.75, 0.55 * _heal_flash)

	shield_bar.value = shield_durability
	var shield_tint := Color.WHITE if shield_active else Color(0.62, 0.66, 0.78)
	if shield_durability < 0.25:
		shield_tint = shield_tint.lerp(SHIELD_LOW_COLOR, 0.55)
	_shield_fill.modulate_color = shield_tint
	if shield_active:
		shield_label.text = "Shield: %d%%" % roundi(shield_durability * 100.0)
	elif shield_durability <= 0.0:
		shield_label.text = "Shield: Broken"
	else:
		shield_label.text = "Shield: Off"

	mana_bar.max_value = mana_max
	mana_bar.value = mana_current
	mana_label.text = "MP %d / %d" % [roundi(mana_current), roundi(mana_max)]
	rage_bar.max_value = rage_max
	rage_bar.value = rage_current
	rage_label.text = "Rage %d · %s READY" % [roundi(rage_current), InputHints.key_for(&"weapon_ultimate")] if ultimate_ready else "Rage %d" % roundi(rage_current)
	var rage_glow := (0.5 + 0.5 * sin(_rage_pulse)) * 0.6 if ultimate_ready else 0.0
	_rage_fill.modulate_color = Color.WHITE.lerp(Color(1.7, 1.45, 1.1), rage_glow)
	rage_label.add_theme_color_override(&"font_color", GOLD_BRIGHT if ultimate_ready else IVORY)

	var bolt_ratio := 1.0 - bolt_remaining / bolt_total
	bolt_bar.value = bolt_ratio
	bolt_label.text = "Bolt: Ready" if is_bolt_ready() else "Bolt: %.1fs" % bolt_remaining
	_bolt_fill.bg_color = BOLT_COLOR if is_bolt_ready() else BOLT_COLOR.lerp(DIM_COLOR, 0.5)
	bolt_label.add_theme_color_override(&"font_color", IVORY if is_bolt_ready() else Color(0.72, 0.7, 0.68))

	if dashing:
		dash_bar.value = 0.0
		dash_label.text = "Dash: Dashing"
	elif not dash_ready:
		dash_bar.value = 1.0 - dash_remaining / dash_total
		dash_label.text = "Dash: %.1fs" % dash_remaining
	elif not has_dash_stamina():
		dash_label.text = "Dash: Tired"
	else:
		dash_bar.value = 1.0
		dash_label.text = "Dash: Ready"
	if stamina >= 0.0:
		dash_bar.value = stamina / stamina_max
	var can_dash := dash_ready and has_dash_stamina()
	_dash_fill.bg_color = DASH_COLOR if can_dash else DASH_COLOR.lerp(DIM_COLOR, 0.5)
	dash_label.add_theme_color_override(&"font_color", IVORY if can_dash else Color(0.72, 0.7, 0.68))

	name_label.text = display_name if not display_name.is_empty() else rank_title
	level_label.text = str(rank + 1)
	exp_bar.value = _exp_shown
	exp_label.text = ("Rep %d / %d" % [reputation, reputation + reputation_to_next]) if reputation_to_next > 0 else ("Rep %d · max" % reputation)
	exp_label.tooltip_text = "%d reputation to the next rank" % reputation_to_next if reputation_to_next > 0 else "Top courier rank"
	var pulse := sin(_badge_pulse * PI) * _badge_pulse
	level_badge.scale = Vector2.ONE * (1.0 + 0.3 * pulse)
	level_label.add_theme_color_override(&"font_color", GOLD_BRIGHT.lerp(Color.WHITE, _badge_pulse * 0.7))


## Anchored top-left at MARGIN; scales down when the logical viewport is short.
func _layout() -> void:
	if panel == null:
		return
	var view := panel.get_viewport_rect().size
	panel.scale = Vector2.ONE * clampf(view.y / FULL_SCALE_HEIGHT, MIN_SCALE, 1.0)
	level_badge.pivot_offset = level_badge.size * 0.5


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
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = MARGIN
	panel.offset_top = MARGIN
	panel.grow_horizontal = Control.GROW_DIRECTION_END
	panel.grow_vertical = Control.GROW_DIRECTION_END
	var bg := StyleBoxFlat.new()
	bg.bg_color = PANEL_COLOR
	bg.border_color = GOLD.darkened(0.15)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(10)
	bg.content_margin_left = 10
	bg.content_margin_right = 14
	bg.content_margin_top = 9
	bg.content_margin_bottom = 9
	bg.shadow_color = Color(0, 0, 0, 0.45)
	bg.shadow_size = 6
	bg.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override(&"panel", bg)
	root.add_child(panel)

	var content := HBoxContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override(&"separation", 12)
	panel.add_child(content)
	content.add_child(_build_portrait())

	var column := VBoxContainer.new()
	column.name = "Bars"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.custom_minimum_size = Vector2(272, 0)
	column.add_theme_constant_override(&"separation", 4)
	content.add_child(column)

	name_label = _label(17, GOLD_BRIGHT)
	name_label.name = "Name"
	name_label.clip_text = true
	column.add_child(name_label)
	var divider := TextureRect.new()
	divider.name = "Divider"
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.texture = _fade_line()
	divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	divider.stretch_mode = TextureRect.STRETCH_SCALE
	divider.custom_minimum_size = Vector2(0, 1)
	column.add_child(divider)

	var health := _add_bar(column, "Health", 20.0, _gradient([Color(1.0, 0.42, 0.42), Color(0.78, 0.1, 0.16), Color(0.46, 0.03, 0.08)]), Color(1.0, 0.86, 0.82, 0.9), 14)
	health_bar = health[0]
	health_label = health[1]
	health_trail = health[2]
	_health_fill = health[3]
	heal_flash = ColorRect.new()
	heal_flash.name = "HealFlash"
	heal_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heal_flash.visible = false
	var health_stack := health_bar.get_parent() as Control
	health_stack.add_child(heal_flash)
	health_stack.move_child(heal_flash, health_label.get_index())

	var shield := _add_bar(column, "PackageShield", 14.0, _gradient([Color(0.55, 0.78, 1.0), Color(0.16, 0.42, 0.9), Color(0.06, 0.17, 0.5)]), Color(0.82, 0.9, 1.0, 0.85), 12)
	shield_bar = shield[0]
	shield_label = shield[1]
	shield_trail = shield[2]
	_shield_fill = shield[3]
	shield_bar.max_value = 1.0
	shield_trail.max_value = 1.0

	# MP and rage side by side under the shield.
	var resources := HBoxContainer.new()
	resources.name = "Resources"
	resources.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resources.add_theme_constant_override(&"separation", 6)
	column.add_child(resources)
	var mana := _add_bar(resources, "Mana", 14.0, _gradient([Color(0.62, 0.62, 1.0), Color(0.32, 0.26, 0.92), Color(0.15, 0.1, 0.5)]), Color(0.85, 0.85, 1.0, 0.85), 11)
	mana_bar = mana[0]
	mana_label = mana[1]
	(mana_bar.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rage := _add_bar(resources, "Rage", 14.0, _gradient([Color(1.0, 0.72, 0.3), Color(0.92, 0.36, 0.08), Color(0.55, 0.14, 0.03)]), Color(1.0, 0.85, 0.7, 0.85), 11)
	rage_bar = rage[0]
	rage_label = rage[1]
	_rage_fill = rage[3]
	(rage_bar.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL

	exp_bar = _thin_bar("Reputation", 6.0, _track_style(2), _gradient([Color(1.0, 0.92, 0.6), Color(0.86, 0.62, 0.2), Color(0.56, 0.36, 0.08)]))
	exp_bar.max_value = 1.0
	column.add_child(exp_bar)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_theme_constant_override(&"separation", 10)
	column.add_child(footer)
	var bolt := _add_chip(footer, "MagicBolt", BOLT_COLOR)
	bolt_bar = bolt[0]
	bolt_label = bolt[1]
	_bolt_fill = bolt[2]
	var dash := _add_chip(footer, "Dash", DASH_COLOR)
	dash_bar = dash[0]
	dash_label = dash[1]
	_dash_fill = dash[2]
	exp_label = _label(12, Color(0.86, 0.78, 0.6))
	exp_label.name = "ReputationLabel"
	exp_label.clip_text = true
	exp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exp_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	exp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(exp_label)
	bolt_bar.max_value = 1.0
	dash_bar.max_value = 1.0
	buff_row = HBoxContainer.new()
	buff_row.name = "Buffs"
	buff_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buff_row.add_theme_constant_override(&"separation", 8)
	buff_row.visible = false
	column.add_child(buff_row)


## Circular portrait in a thin gold ring, with the rank badge on its lower right.
func _build_portrait() -> Control:
	var frame := Control.new()
	frame.name = "Portrait"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.custom_minimum_size = Vector2(84, 84)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ring := Panel.new()
	ring.name = "Ring"
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ring_style := StyleBoxFlat.new()
	ring_style.bg_color = Color(0.2, 0.14, 0.1)
	ring_style.border_color = GOLD
	ring_style.set_border_width_all(2)
	ring_style.set_corner_radius_all(42)
	ring_style.anti_aliasing = true
	ring_style.shadow_color = Color(0, 0, 0, 0.5)
	ring_style.shadow_size = 3
	ring.add_theme_stylebox_override(&"panel", ring_style)
	frame.add_child(ring)
	portrait = TextureRect.new()
	portrait.name = "Image"
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Phase 8: a live render of the courier (AnimatedPortrait); the still is the fallback.
	live_portrait = AnimatedPortrait.new()
	live_portrait.name = "LivePortrait"
	frame.add_child(live_portrait)
	portrait.texture = live_portrait.get_texture() if live_portrait != null else PORTRAIT
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.offset_left = 3
	portrait.offset_top = 3
	portrait.offset_right = -3
	portrait.offset_bottom = -3
	var mask := ShaderMaterial.new()
	mask.shader = CIRCLE_MASK
	portrait.material = mask
	frame.add_child(portrait)

	level_badge = PanelContainer.new()
	level_badge.name = "LevelBadge"
	level_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.16, 0.1, 0.07)
	badge_style.border_color = GOLD_BRIGHT
	badge_style.set_border_width_all(2)
	badge_style.set_corner_radius_all(14)
	badge_style.anti_aliasing = true
	level_badge.add_theme_stylebox_override(&"panel", badge_style)
	level_badge.custom_minimum_size = Vector2(28, 28)
	level_badge.position = Vector2(60, 58)
	level_badge.size = Vector2(28, 28)
	frame.add_child(level_badge)
	level_label = _label(15, GOLD_BRIGHT)
	level_label.name = "Level"
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_badge.add_child(level_label)
	return frame


## A bar with a dark gold-edged track, a pale damage trail behind the fill, a soft top
## highlight and the value text over it. Returns [bar, label, trail, fill style].
func _add_bar(parent: Container, bar_name: String, height: float, fill_texture: Texture2D, trail_color: Color, font_size: int) -> Array:
	var stack := Control.new()
	stack.name = bar_name
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.custom_minimum_size = Vector2(0, height)
	parent.add_child(stack)
	var trail := _thin_bar("Trail", height, _track_style(), null, trail_color)
	trail.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(trail)
	var fill := StyleBoxTexture.new()
	fill.texture = fill_texture
	var bar := _thin_bar("Bar", height, StyleBoxEmpty.new(), null)
	bar.add_theme_stylebox_override(&"fill", fill)
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(bar)
	var shine := ColorRect.new()
	shine.name = "Shine"
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shine.color = Color(1, 1, 1, 0.1)
	shine.set_anchors_preset(Control.PRESET_TOP_WIDE)
	shine.offset_left = 2
	shine.offset_right = -2
	shine.offset_top = 1
	shine.offset_bottom = maxf(2.0, roundf(height * 0.3))
	stack.add_child(shine)
	var label := _label(font_size, IVORY)
	label.name = "Label"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 8
	label.offset_right = -8
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stack.add_child(label)
	return [bar, label, trail, fill]


## Small readiness chip: a label over a 3 px cooldown bar. Returns [bar, label, fill].
func _add_chip(parent: Container, chip_name: String, color: Color) -> Array:
	var chip := VBoxContainer.new()
	chip.name = chip_name
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_constant_override(&"separation", 1)
	parent.add_child(chip)
	var label := _label(12, IVORY)
	label.name = "Label"
	label.custom_minimum_size = Vector2(78, 0)
	chip.add_child(label)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	var bar := _thin_bar("Bar", 3.0, _track_style(1), null)
	bar.add_theme_stylebox_override(&"fill", fill)
	chip.add_child(bar)
	return [bar, label, fill]


func _thin_bar(bar_name: String, height: float, background: StyleBox, fill_texture: Texture2D, fill_color := Color.WHITE) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = bar_name
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.step = 0.0
	bar.custom_minimum_size = Vector2(0, height)
	bar.add_theme_stylebox_override(&"background", background)
	if fill_texture != null:
		var fill := StyleBoxTexture.new()
		fill.texture = fill_texture
		bar.add_theme_stylebox_override(&"fill", fill)
	else:
		var flat := StyleBoxFlat.new()
		flat.bg_color = fill_color
		flat.set_corner_radius_all(3)
		bar.add_theme_stylebox_override(&"fill", flat)
	return bar


func _track_style(radius := 4) -> StyleBoxFlat:
	var track := StyleBoxFlat.new()
	track.bg_color = TRACK_COLOR
	track.border_color = GOLD.darkened(0.45)
	track.set_border_width_all(1)
	track.set_corner_radius_all(radius)
	return track


## Horizontal antique-gold line that fades out to the right (divider under the name).
static func _fade_line() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(GOLD, 0.85), Color(GOLD, 0.35), Color(GOLD, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 1
	return texture


## Vertical gradient texture (top to bottom) for a glossy bar fill.
static func _gradient(colors: Array[Color]) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray(colors)
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	texture.width = 4
	texture.height = 32
	return texture


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color(0.04, 0.03, 0.02))
	label.add_theme_constant_override(&"outline_size", 4)
	return label
