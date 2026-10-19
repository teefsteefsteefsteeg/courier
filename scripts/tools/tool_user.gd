class_name ToolUser
extends Node
## Works the courier's equipped tool on the world (Phase 5H), added as the "ToolUser" child
## of the PlayerController. Started by interacting with a ToolTarget ([E]) or by the primary
## action with a tool in hand ([Space], CombatController.tool_use_requested): the focused
## target, else the nearest target for this tool in reach, else, for the fishing rod, open
## water in front of the courier.
##
## Before starting it checks the tool (the target's required_tool must be in hand), the
## distance (the target's reach), the courier's state (alive, on the ground, not dashing, no
## package in hand, in control) and the target itself (available, materials). While working
## the courier's input is paused; moving, dashing, Escape or taking damage cancel.
##
## Jobs: strokes x the tool clip; at each clip's impact moment (KayKitCharacter.TOOL_IMPACT)
## the target reacts, and at the last stroke's impact it pays out (ToolTarget.complete).
## Fishing: cast (the bobber lands at the cast's impact), wait for a bite, then press [E] or
## [Space] within bite_window to hook it; a quick hook improves the odds of a rare fish.
## Pressing before the bite or missing the window loses the fish. Steps run in
## _physics_process, so tests can drive them frame by frame.

signal action_started(target: ToolTarget, tool: ItemDefinition)
## A stroke landed: done of total.
signal action_progress(done: int, total: int)
signal action_finished(target: ToolTarget, completed: bool, message: String)
signal fishing_state_changed(state: FishState)
## Something to tell the player ("You need a Pickaxe", "+3 Wood"); kind is a
## QuestNotification kind (&"info", &"success", &"warning").
signal feedback(text: String, kind: StringName)

enum State { IDLE, WORKING, FISHING }
enum FishState { NONE, CASTING, WAITING, BITE, REELING }

const CAST_SPEED := 1.25
const REEL_SPEED := 1.4
## A hook within this fraction of the bite window counts as quick (rare-fish bonus).
const QUICK_HOOK := 0.5

@export var player: PlayerController
## Seconds from the bobber settling to the bite.
@export var bite_wait_min: float = 2.0
@export var bite_wait_max: float = 5.0
## Seconds to hook a bite before it gets away.
@export var bite_window: float = 1.1
## How far in front of the courier the line lands when fishing from a bank.
@export var cast_distance: float = 2.4
## Radius searched for a target when the primary action is used without one in focus.
@export var search_radius: float = 2.8

var state: State = State.IDLE
var fish_state: FishState = FishState.NONE
var target: ToolTarget = null
var rng := RandomNumberGenerator.new()
## The pond and the point the line was cast to (while fishing).
var fishing_pond: Pond = null
var cast_point: Vector3 = Vector3.ZERO
var bobber: Node3D = null
var line: MeshInstance3D = null

var _combat: CombatController
var _character: KayKitCharacter
var _carrier: PackageCarrier
var _inventory: CourierInventory
var _tool: ItemDefinition
var _stroke := 0
var _stroke_time := 0.0
var _stroke_length := 0.0
var _impact_at := 0.0
var _impact_done := false
var _result := ""
var _fish_time := 0.0
var _phase_length := 0.0
var _phase_impact := 0.0
var _caught := false
var _hook_quality := 0.0
var _locked := false


static func find_on(node: Node) -> ToolUser:
	if node == null:
		return null
	if node is ToolUser:
		return node
	for child in node.get_children():
		if child is ToolUser:
			return child
	return null


func _ready() -> void:
	if player == null:
		player = get_parent() as PlayerController
	if player == null:
		return
	_combat = CombatController.find_on(player)
	_carrier = PackageCarrier.find_on(player)
	var characters := player.find_children("*", "KayKitCharacter", true, false)
	_character = characters[0] as KayKitCharacter if not characters.is_empty() else null
	if _combat != null:
		_combat.tool_use_requested.connect(use_equipped_tool)
		if _combat.health != null:
			_combat.health.damaged.connect(func(_amount: float, _source: Vector3) -> void:
				if is_busy():
					cancel("Interrupted!"))


func get_inventory() -> CourierInventory:
	if _inventory == null and is_inside_tree():
		_inventory = CourierInventory.find(get_tree())
	return _inventory


func get_equipped_tool() -> ItemDefinition:
	var inventory := get_inventory()
	return inventory.get_equipped_tool() if inventory != null else null


func is_busy() -> bool:
	return state != State.IDLE


## Uses the tool in hand on whatever is in front (the primary action). Returns whether a
## job started.
func use_equipped_tool() -> bool:
	if is_busy():
		if state == State.FISHING:
			hook()
		return false
	var tool := get_equipped_tool()
	if tool == null:
		return false
	var focused := player.interaction.focused if player.interaction != null else null
	if focused != null and focused.get_parent() is ToolTarget:
		return begin(focused.get_parent() as ToolTarget)
	var nearest := find_target(tool.tool_type)
	if nearest != null:
		return begin(nearest)
	if tool.tool_type == ItemDefinition.ToolType.FISHING_ROD:
		return cast_from_bank()
	_say(_nothing_here_text(tool.tool_type), QuestNotification.KIND_WARNING)
	return false


## The nearest target for tool type within search_radius, preferring ones in front.
func find_target(type: ItemDefinition.ToolType) -> ToolTarget:
	var best: ToolTarget = null
	var best_score := INF
	var forward := player.facing.get_facing_direction() if player.facing != null else Vector3.FORWARD
	for node in get_tree().get_nodes_in_group(ToolTarget.GROUP):
		var candidate := node as ToolTarget
		if candidate.required_tool != type or not candidate.is_visible_in_tree():
			continue
		var to := candidate.get_reach_point() - player.global_position
		to.y = 0.0
		var distance := to.length()
		if distance > maxf(search_radius, candidate.reach):
			continue
		var score := distance - (forward.dot(to.normalized()) if distance > 0.01 else 1.0)
		if score < best_score:
			best_score = score
			best = candidate
	return best


## Starts working target. Says why (and returns false) when it cannot start.
func begin(new_target: ToolTarget) -> bool:
	if is_busy():
		return false
	var reason := get_block_reason(new_target)
	if not reason.is_empty():
		_say(reason, QuestNotification.KIND_WARNING)
		return false
	_tool = get_equipped_tool()
	if new_target is FishingSpot:
		var spot := new_target as FishingSpot
		return _start_fishing(spot.get_work_point(), spot.pond, spot)
	_start_work(new_target)
	return true


## Why target cannot be worked now ("" when it can).
func get_block_reason(new_target: ToolTarget) -> String:
	var courier_reason := _courier_block_reason()
	if not courier_reason.is_empty():
		return courier_reason
	if new_target == null:
		return "There is nothing to work here."
	var tool := get_equipped_tool()
	if tool == null or tool.tool_type != new_target.required_tool:
		var tool_name := ItemDefinition.tool_type_name(new_target.required_tool)
		var owned := get_inventory().find_owned_tool(new_target.required_tool) if get_inventory() != null else null
		if owned != null:
			return "Equip your %s first: put it on a quick slot or use Equipment [%s]." % [owned.display_name, InputHints.key_for(&"toggle_equipment")]
		return "You need a %s for that. The Toolwright at the Hill Smithy sells them." % tool_name
	if not new_target.is_available():
		return "%s: %s." % [new_target.display_name, new_target.get_unavailable_text()]
	if not is_in_reach(new_target):
		return "Get closer to the %s." % new_target.display_name
	var missing := new_target.check_requirements(self)
	if not missing.is_empty():
		return "%s %s: %s." % [new_target.verb, new_target.display_name, missing]
	return ""


## True when the courier can work target from here: its prompt is in range (the interaction
## overlap is the interaction range), or it is within the target's reach.
func is_in_reach(new_target: ToolTarget) -> bool:
	var detector := player.interaction
	if detector != null and new_target.interactable != null and detector.overlaps_area(new_target.interactable):
		return true
	var to := new_target.get_reach_point() - player.global_position
	return Vector2(to.x, to.z).length() <= new_target.reach


## Casts the rod into the water in front of the courier. Refused on dry land.
func cast_from_bank() -> bool:
	if is_busy():
		return false
	var reason := _courier_block_reason()
	var tool := get_equipped_tool()
	if reason.is_empty() and (tool == null or tool.tool_type != ItemDefinition.ToolType.FISHING_ROD):
		reason = "You need a Fishing rod in hand to fish."
	if not reason.is_empty():
		_say(reason, QuestNotification.KIND_WARNING)
		return false
	var point := get_bank_cast_point()
	var pond := find_water(point)
	if pond == null:
		_say("No open water in front of you. Face a pond to cast your line.", QuestNotification.KIND_WARNING)
		return false
	_tool = tool
	return _start_fishing(point, pond, null)


## Where a cast from the courier's position would land.
func get_bank_cast_point() -> Vector3:
	var forward := player.facing.get_facing_direction() if player.facing != null else Vector3.FORWARD
	return player.global_position + forward * cast_distance


## The pond or river whose open water contains point, or null (dry land). Water in a
## region that is not shown (the paused village while the courier is elsewhere, which
## shares coordinates with the other regions) never counts.
func find_water(point: Vector3) -> Pond:
	for node in get_tree().get_nodes_in_group(Pond.GROUP):
		if (node as Pond).is_visible_in_tree() and (node as Pond).is_open_water(point):
			return node as Pond
	return null


## Hooks a bite (the [E] / [Space] press while fishing).
func hook() -> void:
	if state != State.FISHING:
		return
	match fish_state:
		FishState.CASTING, FishState.WAITING:
			_end(false, "Too soon! The fish swam off.")
		FishState.BITE:
			_hook_quality = 1.0 - clampf(_fish_time / bite_window, 0.0, 1.0)
			_set_fish_state(FishState.REELING)
			_fish_time = 0.0
			_caught = false
			_phase_length = _clip_length(&"tool_reel", REEL_SPEED, 0.9)
			_phase_impact = _phase_length * KayKitCharacter.TOOL_IMPACT[&"tool_reel"]
			if _character != null:
				_character.play_once(&"tool_reel", REEL_SPEED)


## Stops the current job. A job that already paid out (its last stroke landed) just ends.
func cancel(message: String = "Stopped.") -> void:
	if not is_busy():
		return
	if (state == State.WORKING or (state == State.FISHING and _caught)) and not _result.is_empty():
		_end(true, _result)
		return
	if _character != null:
		_character.end_once()
	_end(false, message)


## Seconds of the bite window left, as a fraction (1 just after the bite, 0 when it is gone).
func get_bite_time_left() -> float:
	return 1.0 - clampf(_fish_time / bite_window, 0.0, 1.0) if fish_state == FishState.BITE else 0.0


## Strokes landed and needed in the current job.
func get_progress() -> Vector2i:
	return Vector2i(_stroke + (1 if _impact_done else 0), target.strokes) if state == State.WORKING and target != null else Vector2i.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if not is_busy():
		return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"combat_magic_bolt"):
		if state == State.FISHING:
			hook()
		get_viewport().set_input_as_handled()
		return
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right", &"combat_dash", &"ui_cancel"]:
		if event.is_action_pressed(action):
			cancel("Stopped fishing." if state == State.FISHING else "Stopped.")
			get_viewport().set_input_as_handled()
			return


func _physics_process(delta: float) -> void:
	if is_busy():
		if (target != null and not is_instance_valid(target)) or (state == State.FISHING and not is_instance_valid(fishing_pond)):
			cancel("The work site is no longer available.")
			return
		# Area overlap lists lag a teleport by a physics frame; an active job must
		# measure the courier's current position before it can pay an impact.
		var left_site := false
		if is_instance_valid(target):
			var offset := target.get_reach_point() - player.global_position
			left_site = Vector2(offset.x, offset.z).length() > target.reach
		if get_equipped_tool() != _tool or left_site:
			cancel("Stopped.")
			return
	match state:
		State.WORKING:
			_step_work(delta)
		State.FISHING:
			_step_fishing(delta)
	if line != null and bobber != null:
		_update_line()


# --- jobs (chop, mine, dig, repair) ---------------------------------------------------------

func _start_work(new_target: ToolTarget) -> void:
	target = new_target
	state = State.WORKING
	_stroke = 0
	_result = ""
	_lock()
	_face(target.get_work_point())
	action_started.emit(target, _tool)
	action_progress.emit(0, target.strokes)
	_begin_stroke()


func _begin_stroke() -> void:
	_stroke_time = 0.0
	_impact_done = false
	_stroke_length = _clip_length(target.action, target.stroke_speed, 0.8)
	_impact_at = _stroke_length * KayKitCharacter.TOOL_IMPACT.get(target.action, 0.5)
	if _character != null:
		_character.play_once(target.action, target.stroke_speed)


func _step_work(delta: float) -> void:
	_stroke_time += delta
	if not _impact_done and _stroke_time >= _impact_at:
		_impact_done = true
		target.on_stroke(self, _stroke)
		if _stroke == target.strokes - 1:
			# The result lands with the last stroke, not when the clip has finished.
			_result = target.complete(self)
			if _result.is_empty():
				_end(false, "%s: it didn't work out." % target.display_name)
				return
		action_progress.emit(_stroke + 1, target.strokes)
	if _stroke_time >= _stroke_length:
		_stroke += 1
		if _stroke >= target.strokes:
			_end(true, _result)
		else:
			_begin_stroke()


# --- fishing ---------------------------------------------------------------------------------

func _start_fishing(point: Vector3, pond: Pond, spot: FishingSpot) -> bool:
	if pond == null or not pond.is_open_water(point, 0.2):
		_say("No open water there. Face a pond to cast your line.", QuestNotification.KIND_WARNING)
		return false
	state = State.FISHING
	_result = ""
	_caught = false
	target = spot
	fishing_pond = pond
	cast_point = Vector3(point.x, pond.get_water_y(), point.z)
	_lock()
	_face(cast_point)
	_fish_time = 0.0
	_phase_length = _clip_length(&"tool_cast", CAST_SPEED, 0.9)
	_phase_impact = _phase_length * KayKitCharacter.TOOL_IMPACT[&"tool_cast"]
	_set_fish_state(FishState.CASTING)
	if _character != null:
		_character.play_once(&"tool_cast", CAST_SPEED)
	action_started.emit(spot, _tool)
	return true


func _step_fishing(delta: float) -> void:
	_fish_time += delta
	match fish_state:
		FishState.CASTING:
			if bobber == null and _fish_time >= _phase_impact:
				_spawn_bobber()
			if _fish_time >= _phase_length:
				_set_fish_state(FishState.WAITING)
				_fish_time = 0.0
				_phase_length = rng.randf_range(bite_wait_min, maxf(bite_wait_min, bite_wait_max))
		FishState.WAITING:
			_float_bobber(0.015, 3.0)
			if _fish_time >= _phase_length:
				_set_fish_state(FishState.BITE)
				_fish_time = 0.0
				_say("A bite! Press [%s] to hook it!" % InputHints.key_for(&"interact"), QuestNotification.KIND_INFO)
		FishState.BITE:
			_float_bobber(0.04, 22.0, -0.05)
			if _fish_time >= bite_window:
				_end(false, "It got away...")
		FishState.REELING:
			if bobber != null:
				bobber.global_position = bobber.global_position.lerp(_rod_tip(), minf(delta * 4.0, 1.0))
			if not _caught and _fish_time >= _phase_impact:
				_caught = true
				_result = _land_fish()
			if _fish_time >= _phase_length:
				_end(not _result.is_empty(), _result)


func _land_fish() -> String:
	var spot := target as FishingSpot
	var bonus := spot.catch_bonus if spot != null else 1.0
	var quick := _hook_quality >= QUICK_HOOK
	if quick:
		bonus *= 2.0
	var fish := fishing_pond.pick_fish(rng, bonus) if fishing_pond != null else null
	var inventory := get_inventory()
	if fish == null or inventory == null or inventory.add_material(fish, 1) <= 0:
		return ""
	var service := GatheringService.find(get_tree())
	if service != null:
		service.add_count(&"fish")
	return "Caught a %s!%s" % [fish.display_name, " Quick hook!" if quick else ""]


func _set_fish_state(new_state: FishState) -> void:
	fish_state = new_state
	fishing_state_changed.emit(new_state)


func _spawn_bobber() -> void:
	bobber = Node3D.new()
	bobber.name = "FishingBobber"
	var top := MeshInstance3D.new()
	var top_mesh := SphereMesh.new()
	top_mesh.radius = 0.07
	top_mesh.height = 0.14
	top_mesh.material = _flat_material(Color(0.86, 0.16, 0.12))
	top.mesh = top_mesh
	top.position.y = 0.04
	bobber.add_child(top)
	var bottom := MeshInstance3D.new()
	var bottom_mesh := SphereMesh.new()
	bottom_mesh.radius = 0.065
	bottom_mesh.height = 0.11
	bottom_mesh.material = _flat_material(Color(0.95, 0.95, 0.9))
	bottom.mesh = bottom_mesh
	bobber.add_child(bottom)
	_world_root().add_child(bobber)
	bobber.global_position = cast_point
	line = MeshInstance3D.new()
	line.name = "FishingLine"
	var line_mesh := CylinderMesh.new()
	line_mesh.top_radius = 0.008
	line_mesh.bottom_radius = 0.008
	line_mesh.height = 1.0
	line_mesh.radial_segments = 4
	line_mesh.rings = 1
	line_mesh.material = _flat_material(Color(0.92, 0.92, 0.85))
	line.mesh = line_mesh
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world_root().add_child(line)
	_splash(cast_point)


func _float_bobber(amplitude: float, rate: float, offset: float = 0.0) -> void:
	if bobber != null:
		bobber.global_position = cast_point + Vector3.UP * (offset + sin(_fish_time * rate) * amplitude)


func _update_line() -> void:
	var tip := _rod_tip()
	var end := bobber.global_position + Vector3.UP * 0.08
	var span := end - tip
	var length := span.length()
	if length < 0.01:
		return
	var y := span / length
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	line.global_transform = Transform3D(Basis(x, y * length, z), tip + span * 0.5)


## The end of the rod (its "Tip" marker), or above the hand without one.
func _rod_tip() -> Vector3:
	var held := _character.get_held_item_node() if _character != null else null
	if held != null:
		var tip := held.find_child("Tip", true, false) as Node3D
		return tip.global_position if tip != null else held.global_position + Vector3.UP
	return player.global_position + Vector3.UP * 1.6


func _splash(at: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.12
	mesh.outer_radius = 0.16
	mesh.material = _flat_material(Color(0.9, 0.97, 1.0, 0.8))
	ring.mesh = mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world_root().add_child(ring)
	ring.global_position = at + Vector3.UP * 0.02
	var tween := ring.create_tween()
	tween.tween_property(ring, ^"scale", Vector3(4, 1, 4), 0.6)
	tween.tween_callback(ring.queue_free)


func _clear_fishing_props() -> void:
	for node in [bobber, line]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	bobber = null
	line = null


# --- shared ----------------------------------------------------------------------------------

func _courier_block_reason() -> String:
	if player == null or not player.input_enabled:
		return "You're busy right now."
	if _combat != null and _combat.health != null and _combat.health.is_dead():
		return "Not while knocked out."
	if _combat != null and _combat.is_dashing():
		return "Not while dashing."
	if not player.is_on_floor():
		return "Land first."
	if _carrier != null and _carrier.is_carrying():
		return "Put the package down first [%s]: your hands are full." % InputHints.key_for(&"drop_package")
	return ""


func _end(completed: bool, message: String) -> void:
	var finished := target if is_instance_valid(target) else null
	_clear_fishing_props()
	state = State.IDLE
	if fish_state != FishState.NONE:
		_set_fish_state(FishState.NONE)
	target = null
	fishing_pond = null
	_result = ""
	_unlock()
	action_finished.emit(finished, completed, message)
	if not message.is_empty():
		_say(message, QuestNotification.KIND_SUCCESS if completed else QuestNotification.KIND_WARNING)


func _lock() -> void:
	if player.input_enabled:
		player.input_enabled = false
		_locked = true


func _unlock() -> void:
	if _locked:
		_locked = false
		player.input_enabled = true


func _face(point: Vector3) -> void:
	if player.facing == null or player.facing.visual_root == null:
		return
	var to := point - player.global_position
	if Vector2(to.x, to.z).length() > 0.05:
		player.facing.visual_root.rotation.y = FacingComponent.yaw_for_direction(to)


func _clip_length(action: StringName, speed: float, fallback: float) -> float:
	var length := _character.get_action_length(action, speed) if _character != null else 0.0
	return length if length > 0.0 else fallback


func _say(text: String, kind: StringName) -> void:
	feedback.emit(text, kind)


func _world_root() -> Node:
	return player.get_parent() if player.get_parent() != null else get_tree().root


static func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


static func _nothing_here_text(type: ItemDefinition.ToolType) -> String:
	match type:
		ItemDefinition.ToolType.WOOD_AXE:
			return "No marked tree in reach. Look for trees with a white blaze (the Woodcutters' Grove, or along the Runewood road)."
		ItemDefinition.ToolType.PICKAXE:
			return "No ore rock in reach. Look for grey rocks with ore veins (the old quarry, or the Runewood hillsides)."
		ItemDefinition.ToolType.SHOVEL:
			return "No soft soil in reach. Look for dark, muddy patches by water."
		ItemDefinition.ToolType.HAMMER, ItemDefinition.ToolType.TROWEL:
			return "Nothing here needs repairing."
	return "Nothing to use that on here."
