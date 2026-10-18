extends Node3D
## Phase 4 visual-only enemy base: procedural idle / move / hit / death animation.
## Owns no gameplay state. Drive it directly (play_idle, play_move, play_hit,
## play_death) or bind it to a gameplay CombatHealth node with bind_health():
##   damaged(amount, source_position) -> play_hit(source_position)
##   died()                           -> play_death()
## Animation is advanced from _process, or manually via advance(delta) when
## auto_animate is false (deterministic tests).

signal state_changed(new_state: int, old_state: int)
signal hit_played(source_position: Vector3)
signal death_finished

enum State { IDLE, MOVE, HIT, DEAD }

const Lowpoly := preload("res://scripts/phase4_visual/lowpoly.gd")

@export var auto_animate := true
@export var hit_duration := 0.35
@export var death_duration := 0.9
@export var flash_color := Color(1.0, 1.0, 1.0)
@export var knockback_distance := 0.35

var state: State = State.IDLE
var anim_time := 0.0  ## seconds in the current state
var total_time := 0.0
var flash_amount := 0.0
var knockback_dir := Vector3.ZERO
var body: Node3D  ## animated pivot; all creature parts hang below it
var triangle_count := 0

var _resume_state: State = State.IDLE
var _materials: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []
var _death_emitted := false
var _bound_health: Node


func _ready() -> void:
	if body == null:
		body = Node3D.new()
		body.name = "Body"
		add_child(body)
		_build()
		triangle_count = Lowpoly.count_triangles(self)
	_apply_pose()


func _process(delta: float) -> void:
	if auto_animate:
		advance(delta)


# --- public API ----------------------------------------------------------------

func advance(delta: float) -> void:
	total_time += delta
	anim_time += delta
	if state == State.HIT and anim_time >= hit_duration:
		_set_state(_resume_state)
	elif state == State.DEAD and anim_time >= death_duration and not _death_emitted:
		_death_emitted = true
		visible = false
		death_finished.emit()
	flash_amount = maxf(0.0, flash_amount - delta * 5.0)
	_apply_pose()
	_apply_flash()


func play_idle() -> void:
	_request_loop_state(State.IDLE)


func play_move() -> void:
	_request_loop_state(State.MOVE)


## source_position is a world position; Vector3.INF means "no direction".
func play_hit(source_position: Vector3 = Vector3.INF) -> void:
	if state == State.DEAD:
		return
	if state != State.HIT:
		_resume_state = state
	flash_amount = 1.0
	knockback_dir = Vector3.ZERO
	if source_position.is_finite():
		var here := global_position if is_inside_tree() else position
		var away := here - source_position
		away.y = 0.0
		if away.length_squared() > 0.0001:
			knockback_dir = away.normalized()
	_set_state(State.HIT)
	hit_played.emit(source_position)


func play_death() -> void:
	if state == State.DEAD:
		return
	flash_amount = 1.0
	_set_state(State.DEAD)


## Restores a dead or hit enemy to idle (used by the showcase respawn).
func reset_visual() -> void:
	_death_emitted = false
	visible = true
	flash_amount = 0.0
	knockback_dir = Vector3.ZERO
	_resume_state = State.IDLE
	_set_state(State.IDLE)
	_apply_pose()
	_apply_flash()


func is_dead() -> bool:
	return state == State.DEAD


func get_state_name() -> String:
	return State.keys()[state]


## Opportunistic gameplay adapter: connects to a CombatHealth-like node by
## signal name. Returns true if at least one signal was connected.
func bind_health(health: Node) -> bool:
	unbind_health()
	if health == null:
		return false
	var bound := false
	if health.has_signal(&"damaged"):
		health.connect(&"damaged", _on_health_damaged)
		bound = true
	if health.has_signal(&"died"):
		health.connect(&"died", _on_health_died)
		bound = true
	if bound:
		_bound_health = health
	return bound


func unbind_health() -> void:
	if _bound_health != null and is_instance_valid(_bound_health):
		if _bound_health.is_connected(&"damaged", _on_health_damaged):
			_bound_health.disconnect(&"damaged", _on_health_damaged)
		if _bound_health.is_connected(&"died", _on_health_died):
			_bound_health.disconnect(&"died", _on_health_died)
	_bound_health = null


func get_bound_health() -> Node:
	return _bound_health


# --- subclass hooks ------------------------------------------------------------

## Build creature parts below `body`. Use _track() on materials that should flash.
func _build() -> void:
	pass


## Pose `body` (and parts) from state / anim_time / total_time.
func _apply_pose() -> void:
	pass


# --- internals -----------------------------------------------------------------

func _track(mat: StandardMaterial3D) -> StandardMaterial3D:
	_materials.append(mat)
	_base_colors.append(mat.albedo_color)
	return mat


func _apply_flash() -> void:
	for i in _materials.size():
		var base := _base_colors[i]
		var c := base.lerp(flash_color, flash_amount * 0.85)
		c.a = _materials[i].albedo_color.a
		_materials[i].albedo_color = c


func _request_loop_state(target: State) -> void:
	if state == State.DEAD:
		return
	if state == State.HIT:
		_resume_state = target
		return
	if state != target:
		_set_state(target)


func _set_state(new_state: State) -> void:
	var old := state
	state = new_state
	anim_time = 0.0
	if old != new_state:
		state_changed.emit(new_state, old)


func _hit_progress() -> float:
	return clampf(anim_time / maxf(hit_duration, 0.001), 0.0, 1.0)


func _death_progress() -> float:
	return clampf(anim_time / maxf(death_duration, 0.001), 0.0, 1.0)


func _on_health_damaged(_amount, source_position) -> void:
	var src: Vector3 = source_position if source_position is Vector3 else Vector3.INF
	play_hit(src)


func _on_health_died() -> void:
	play_death()
