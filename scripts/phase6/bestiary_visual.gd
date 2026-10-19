extends Node3D
## Actual Bestiary skeletons have no animation clips. These are explicitly limited
## procedural bone poses: breathing, limb swing, attack windup, recoil and a death fall.
var enemy: Enemy
var skeleton: Skeleton3D
var phase := 0.0
var hit_left := 0.0
var base_scale := Vector3.ONE
var meshes: Array[Node] = []
var flash: StandardMaterial3D
var base_poses: Dictionary[int,Quaternion]={}


func _ready() -> void:
	enemy = get_parent() as Enemy
	base_scale = scale
	var rigs := find_children("*","Skeleton3D",true,false)
	skeleton = rigs[0] as Skeleton3D if not rigs.is_empty() else null
	if skeleton!=null:
		for i in skeleton.get_bone_count():base_poses[i]=skeleton.get_bone_pose_rotation(i)
	meshes = find_children("*","MeshInstance3D",true,false)
	flash = StandardMaterial3D.new()
	flash.albedo_color = Color(1,.18,.06,.45)
	flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if enemy != null:
		enemy.health.damaged.connect(func(_a: float,_p: Vector3) -> void: hit_left=.18)


func _process(delta: float) -> void:
	if enemy == null: return
	phase += delta
	hit_left = maxf(hit_left-delta,0)
	for item: MeshInstance3D in meshes:
		item.material_overlay = flash if hit_left>0 else null
	if enemy.is_dead():
		rotation.z = lerpf(rotation.z,-1.4,minf(delta*4,1))
		position.y = lerpf(position.y,.12,minf(delta*4,1))
		return
	var moving := Vector2(enemy.velocity.x,enemy.velocity.z).length()>.2
	var swing := sin(phase*9)*.32 if moving else sin(phase*2)*.035
	position.y = absf(sin(phase*4))*.04
	if skeleton == null: return
	pose("thigh_l",Vector3(swing,0,0))
	pose("thigh_r",Vector3(-swing,0,0))
	pose("spine_01",Vector3(sin(phase*2)*.035,0,0))
	pose("Head",Vector3(0,sin(phase)*.04,0))
	pose("upperarm_l",Vector3(-swing*.6,0,-.8))
	pose("upperarm_r",Vector3(-1.05 if enemy.state==Enemy.State.WINDUP else swing*.6,0,.8))


func pose(bone: String, angles: Vector3) -> void:
	var index := skeleton.find_bone(bone)
	if index>=0:
		var rest:=skeleton.get_bone_global_rest(index).basis.get_rotation_quaternion()
		var delta:=rest.inverse()*Quaternion.from_euler(angles)*rest
		skeleton.set_bone_pose_rotation(index,base_poses[index]*delta)
