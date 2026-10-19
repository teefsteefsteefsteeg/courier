extends Enemy
## Two readable attacks: close mace sweep and delayed ranged rune eruptions. Both
## strike through CombatHealth, so the existing dash/shield interception remains valid.
signal telegraphed(kind: StringName)
signal attack_resolved(kind: StringName)
@export var boss_name := "Gorvath, Keeper of the Hollow"
var engaged := false
var attack_kind: StringName = &"mace_sweep"
var attack_number := 0
var aim := Vector3.ZERO
var _rings: Array[Node3D] = []
var _ring_points: Array[Vector3] = []
var _home := Vector3.ZERO


func _ready() -> void:
	super()
	_home=global_position
	add_to_group(&"phase6_boss")
	add_to_group(&"phase6_enemy")
	free_on_death=false
	health.died.connect(_victory)


func in_arena(p: Node3D) -> bool:
	return p != null and absf(p.global_position.y-global_position.y)<4 and p.global_position.z < -15.8 and absf(p.global_position.x)<8


func _update_behaviour(_delta: float, p: Node3D) -> Vector3:
	if not is_target_alive(p) or not in_arena(p):
		engaged=false
		_clear_rings()
		if state != State.IDLE: set_state(State.IDLE)
		return Vector3.ZERO
	if not engaged:
		engaged=true
		set_state(State.CHASE)
	match state:
		State.IDLE:
			set_state(State.CHASE)
		State.CHASE:
			if _attack_cooldown_left>0: return Vector3.ZERO
			attack_kind=&"mace_sweep" if attack_number%2==0 else &"rune_eruption"
			# First show the close attack even to a ranged opponent; no unavoidable hit.
			if attack_kind==&"mace_sweep" and horizontal_distance_to(p)>3.2:
				return horizontal_direction_to(p)*move_speed
			aim=p.global_position
			_begin_tell()
			set_state(State.WINDUP)
		State.WINDUP:
			if state_time>=1.15:
				_resolve(p)
				attack_number+=1
				_attack_cooldown_left=1.5
				set_state(State.RECOVER)
		State.RECOVER:
			if _attack_cooldown_left<=0: set_state(State.CHASE)
	return Vector3.ZERO


func _begin_tell() -> void:
	_clear_rings()
	if attack_kind==&"mace_sweep":
		_ring_points=[global_position]
	else:
		_ring_points=[aim,aim+Vector3(2.5,0,0),aim+Vector3(-2.5,0,0)]
	for point in _ring_points:
		var ring:=MeshInstance3D.new()
		var mesh:=TorusMesh.new()
		var radius:=3.4 if attack_kind==&"mace_sweep" else 1.65
		mesh.inner_radius=radius-.10
		mesh.outer_radius=radius
		mesh.rings=32
		mesh.ring_segments=6
		var mat:=StandardMaterial3D.new()
		mat.albedo_color=Color(1,.13,.035)
		mat.emission_enabled=true
		mat.emission=Color(1,.16,.025)
		mat.emission_energy_multiplier=2
		mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material=mat
		ring.mesh=mesh
		get_parent().add_child(ring)
		ring.global_position=Vector3(point.x,.09,point.z)
		_rings.append(ring)
	telegraphed.emit(attack_kind)


func _resolve(p: Node3D) -> void:
	var landed:=false
	for point in _ring_points:
		var radius:=3.4 if attack_kind==&"mace_sweep" else 1.65
		if Vector2(p.global_position.x-point.x,p.global_position.z-point.z).length()<=radius:
			if not landed:
				strike(p,16 if attack_kind==&"mace_sweep" else 13)
				landed=true
	for ring in _rings:
		if not is_instance_valid(ring):continue
		var tween:=ring.create_tween()
		tween.tween_property(ring,^"scale",Vector3(1.1,5,1.1),.15)
		tween.tween_callback(ring.queue_free)
	_rings.clear()
	_ring_points.clear()
	attack_resolved.emit(attack_kind)


func _clear_rings() -> void:
	for node in _rings:
		if is_instance_valid(node):node.queue_free()
	_rings.clear()
	_ring_points.clear()


func _victory() -> void:
	engaged=false
	_clear_rings()
	var router:=get_tree().get_first_node_in_group(&"phase6_router")
	if router!=null:router.claim_victory()


func _exit_tree() -> void:
	_clear_rings()
