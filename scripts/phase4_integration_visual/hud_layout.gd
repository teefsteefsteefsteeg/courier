extends RefCounted
## Screen-corner stacking for Phase 4 visual HUD panels, so they never sit on
## top of the shared gameplay HUD (wallet + quest tracker, top-right) or of
## each other. Nothing outside this folder is modified: foreign panels are only
## measured.
##
## A visual-owned panel opts in with set_stack_priority(). When it docks it
## avoids every visible top-right-anchored Control on any visible CanvasLayer,
## except other opted-in panels with an equal or higher priority. Lower
## priority docks first, so the order is deterministic:
##   gameplay HUD (not opted in, always avoided)
##   PRIORITY_MINIMAP   minimap
##   PRIORITY_TRACKER   Phase 4 delivery tracker

const META_PRIORITY := &"hud_stack_priority"
const PRIORITY_MINIMAP := 10
const PRIORITY_TRACKER := 20
const MARGIN := 12.0
const GAP := 10.0


static func set_stack_priority(control: Control, priority: int) -> void:
	control.set_meta(META_PRIORITY, priority)


static func get_stack_priority(control: Control) -> int:
	return int(control.get_meta(META_PRIORITY, -1))


## True for a Control positioned by its own anchors at the top-right corner
## (anchors left/right = 1, top/bottom = 0), i.e. not laid out by a Container.
static func is_top_right_panel(control: Control) -> bool:
	if control.get_parent() is Container:
		return false
	return control.anchor_left >= 0.99 and control.anchor_right >= 0.99 \
		and control.anchor_top <= 0.01 and control.anchor_bottom <= 0.01


## Lowest screen y (plus GAP) of the top-right panels `control` must avoid,
## or MARGIN when the corner is free. Pass the panel being docked.
static func reserved_top_right_bottom(control: Control) -> float:
	if control == null or not control.is_inside_tree():
		return MARGIN
	var own := get_stack_priority(control)
	var screen_right := control.get_viewport().get_visible_rect().size.x
	var bottom := MARGIN
	for layer: Node in control.get_tree().root.find_children("*", "CanvasLayer", true, false):
		var canvas := layer as CanvasLayer
		if not canvas.visible:
			continue
		for node: Node in canvas.find_children("*", "Control", true, false):
			var other := node as Control
			if other == control or control.is_ancestor_of(other) or other.is_ancestor_of(control):
				continue
			if not other.is_visible_in_tree() or not is_top_right_panel(other):
				continue
			var priority := get_stack_priority(other)
			if priority >= 0 and (own < 0 or priority >= own):
				continue
			var rect := canvas.get_transform() * other.get_global_rect()
			if rect.size.y <= 0.0 or rect.end.x < screen_right * 0.5:
				continue
			bottom = maxf(bottom, rect.end.y + GAP)
	return bottom


## Moves a top-right panel of the given height below the reserved area,
## keeping its right edge MARGIN px from the screen edge. Returns the top y.
static func dock_top_right(control: Control, width: float, height: float) -> float:
	var top := reserved_top_right_bottom(control)
	place_top_right(control, width, height, top)
	return top


## Anchors a panel to the top-right corner at an explicit top y (use this to
## ease towards the value from reserved_top_right_bottom()).
static func place_top_right(control: Control, width: float, height: float, top: float) -> void:
	control.anchor_left = 1.0
	control.anchor_right = 1.0
	control.anchor_top = 0.0
	control.anchor_bottom = 0.0
	control.offset_right = -MARGIN
	control.offset_left = -MARGIN - width
	control.offset_top = top
	control.offset_bottom = top + height
