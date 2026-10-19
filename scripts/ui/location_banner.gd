class_name LocationBanner
extends CanvasLayer
## Announces places in a framed banner near the top centre (fade in / hold / fade out):
## - First discovery of a location (once per save, from the ExplorationService):
##   "LOCATION DISCOVERED" over the name.
## - Entering a LocationZone again: just the name and subtitle. A zone that was announced
##   less than reentry_cooldown seconds ago is not announced again, so walking along a
##   zone boundary never spams banners.
## - Notices such as "TELEPORT UNLOCKED" (show_notice).
## Names come from the shared location registry (WorldLocation) when a zone has a
## location_id. When zones overlap, the highest-priority one the player is inside is the
## current location. The open quest journal hides the whole layer.

signal location_changed(zone: LocationZone)

const GROUP := &"location_banner"
## Small glyph per WorldLocation.Kind (town, guild, shop, forest, clearing, portal).
const KIND_ICONS := ["⌂", "✉", "⚖", "♣", "✿", "✦"]

@export_range(0.05, 3.0, 0.05, "suffix:s") var fade_in_time: float = 0.4
@export_range(0.1, 10.0, 0.1, "suffix:s") var hold_time: float = 2.4
@export_range(0.05, 3.0, 0.05, "suffix:s") var fade_out_time: float = 0.9
## A zone is not announced again within this many seconds of its last banner.
@export_range(0.0, 60.0, 0.5, "suffix:s") var reentry_cooldown: float = 8.0

@onready var banner: Control = %Banner
@onready var header_label: Label = %HeaderLabel
@onready var icon_label: Label = %Icon
@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel

var current_zone: LocationZone = null
## What the banner showed last: &"location", &"discovery" or &"notice".
var last_style: StringName = &""
var _inside: Array[LocationZone] = []
var _tween: Tween
var _shown_at: Dictionary[StringName, int] = {}
var _important_until := 0
var _service: ExplorationService = null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	banner.modulate.a = 0.0
	add_to_group(QuestJournal.HIDDEN_WHILE_OPEN_GROUP)
	get_tree().node_added.connect(_on_node_added)
	for zone in get_tree().get_nodes_in_group(LocationZone.GROUP):
		_watch(zone as LocationZone)
	_bind_service.call_deferred()


func _bind_service() -> void:
	_service = ExplorationService.find(get_tree())
	if _service != null and not _service.location_discovered.is_connected(_on_location_discovered):
		_service.location_discovered.connect(_on_location_discovered)


func _watch(zone: LocationZone) -> void:
	if zone.player_entered.is_connected(_on_zone_entered):
		return
	zone.player_entered.connect(_on_zone_entered)
	zone.player_exited.connect(_on_zone_exited)


func _on_node_added(node: Node) -> void:
	if node is LocationZone:
		_watch(node)


func _on_zone_entered(zone: LocationZone) -> void:
	if not _inside.has(zone):
		_inside.append(zone)
	_update_current()


func _on_zone_exited(zone: LocationZone) -> void:
	_inside.erase(zone)
	_update_current()


func _update_current() -> void:
	var best: LocationZone = null
	for zone in _inside:
		if is_instance_valid(zone) and (best == null or zone.zone_priority > best.zone_priority):
			best = zone
	if best == current_zone or best == null:
		return
	current_zone = best
	location_changed.emit(best)
	var key := best.location_id if best.location_id != &"" else StringName(best.display_name)
	var now := Time.get_ticks_msec()
	# A discovery or notice is still on screen: let it finish.
	if now < _important_until:
		_shown_at[key] = now
		return
	if _shown_at.has(key) and now - _shown_at[key] < int(reentry_cooldown * 1000.0):
		return
	_shown_at[key] = now
	var location := _service.get_location(best.location_id) if _service != null and best.location_id != &"" else null
	if location != null:
		_show(&"location", "", location.display_name, location.subtitle, KIND_ICONS[location.kind])
	else:
		show_location(best.display_name, best.subtitle)


func _on_location_discovered(location: WorldLocation) -> void:
	_shown_at[location.location_id] = Time.get_ticks_msec()
	if location.kind == WorldLocation.Kind.PORTAL and _service != null and _service.is_portal_active(location.location_id):
		return
	show_discovery(location.display_name, location.subtitle, KIND_ICONS[location.kind])


## Normal entry banner: the place name and an optional subtitle.
func show_location(title: String, subtitle: String = "") -> void:
	_show(&"location", "", title, subtitle, "◆")


## First-discovery banner: "LOCATION DISCOVERED" over the name.
func show_discovery(title: String, subtitle: String = "", icon: String = "◆") -> void:
	_show(&"discovery", "LOCATION DISCOVERED", title, subtitle, icon)


## A framed notice with a header line, e.g. ("TELEPORT UNLOCKED", "Willowmere Portal").
func show_notice(header: String, title: String, subtitle: String = "") -> void:
	_show(&"notice", header, title, subtitle, "✦")


func _show(style: StringName, header: String, title: String, subtitle: String, icon: String) -> void:
	last_style = style
	header_label.text = header
	header_label.visible = not header.is_empty()
	icon_label.text = icon
	title_label.text = title
	subtitle_label.text = subtitle
	subtitle_label.visible = not subtitle.is_empty()
	var total := fade_in_time + hold_time + fade_out_time
	_important_until = Time.get_ticks_msec() + int(total * 1000.0) if style != &"location" else 0
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(banner, ^"modulate:a", 1.0, fade_in_time)
	_tween.tween_interval(hold_time)
	_tween.tween_property(banner, ^"modulate:a", 0.0, fade_out_time)
