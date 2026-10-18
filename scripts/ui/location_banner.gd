class_name LocationBanner
extends CanvasLayer
## Announces the player's current LocationZone ("Willowmere Post Office") with a
## fade in / hold / fade out at the top of the screen. When zones overlap, the
## highest-priority one the player is inside is the current location. The open
## quest journal hides the whole layer.

signal location_changed(zone: LocationZone)

@export_range(0.05, 3.0, 0.05, "suffix:s") var fade_in_time: float = 0.4
@export_range(0.1, 10.0, 0.1, "suffix:s") var hold_time: float = 2.4
@export_range(0.05, 3.0, 0.05, "suffix:s") var fade_out_time: float = 0.9

@onready var banner: Control = %Banner
@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel

var current_zone: LocationZone = null
var _inside: Array[LocationZone] = []
var _tween: Tween


func _ready() -> void:
	banner.modulate.a = 0.0
	add_to_group(QuestJournal.HIDDEN_WHILE_OPEN_GROUP)
	get_tree().node_added.connect(_on_node_added)
	for zone in get_tree().get_nodes_in_group(LocationZone.GROUP):
		_watch(zone as LocationZone)


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
	show_location(best.display_name, best.subtitle)
	location_changed.emit(best)


func show_location(title: String, subtitle: String = "") -> void:
	title_label.text = title
	subtitle_label.text = subtitle
	subtitle_label.visible = not subtitle.is_empty()
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(banner, ^"modulate:a", 1.0, fade_in_time)
	_tween.tween_interval(hold_time)
	_tween.tween_property(banner, ^"modulate:a", 0.0, fade_out_time)
