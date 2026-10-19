extends CanvasLayer
## Direct binding to the boss CombatHealth. Only the fill is smoothed; the text is real HP.
var boss: Enemy
var panel: PanelContainer
var bar: ProgressBar
var caption: Label
var hp: Label


func _ready() -> void:
	layer=18
	panel=PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left=-285
	panel.offset_right=285
	panel.offset_top=18
	panel.offset_bottom=98
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(.065,.035,.045,.97)
	style.border_color=Color(.72,.53,.22)
	style.set_border_width_all(2)
	style.set_corner_radius_all(7)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override(&"panel",style)
	add_child(panel)
	var body:=VBoxContainer.new()
	panel.add_child(body)
	caption=Label.new()
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override(&"font_color",Color(.96,.78,.43))
	caption.add_theme_font_size_override(&"font_size",22)
	body.add_child(caption)
	bar=ProgressBar.new()
	bar.show_percentage=false
	bar.custom_minimum_size=Vector2(0,18)
	var bg:=StyleBoxFlat.new()
	bg.bg_color=Color(.12,.04,.045)
	bg.set_border_width_all(1)
	bg.border_color=Color(.55,.37,.13)
	bar.add_theme_stylebox_override(&"background",bg)
	var fill:=StyleBoxFlat.new()
	fill.bg_color=Color(.65,.055,.09)
	bar.add_theme_stylebox_override(&"fill",fill)
	body.add_child(bar)
	hp=Label.new()
	hp.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hp.add_theme_font_size_override(&"font_size",13)
	body.add_child(hp)
	boss=get_parent().get_node_or_null("Boss") as Enemy
	if boss!=null:
		bar.max_value=boss.health.max_health
		bar.value=boss.health.get_health()
		caption.text=boss.boss_name
	panel.visible=false


func _process(delta: float) -> void:
	var active: bool=is_instance_valid(boss) and not boss.is_dead() and boss.engaged
	panel.visible=active
	if not active:return
	bar.value=move_toward(bar.value,boss.health.get_health(),boss.health.max_health*delta*1.2)
	hp.text="%d / %d"%[ceili(boss.health.get_health()),int(boss.health.max_health)]
	var banner:=get_tree().get_first_node_in_group(LocationBanner.GROUP) as LocationBanner
	if banner!=null and banner.banner!=null:banner.banner.modulate.a=0
