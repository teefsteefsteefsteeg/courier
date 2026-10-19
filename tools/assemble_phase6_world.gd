extends "res://tools/assemble_blender_region.gd"
## Creates connected level scenes using the Blender height field / actual newmap art.
const OUT := "res://scenes/phase6/"
const ART := "res://assets/generated/phase6/"
const BESTIARY := "res://assets/models/bestiary/"
var layout: Dictionary


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	layout=JSON.parse_string(FileAccess.get_file_as_string(ART+"world_layout.json"))
	_outdoors()
	_dungeon()
	_gateway()
	_maps()
	quit()


func surface_y(x: float,z: float) -> float:
	var step: float=layout["step"]
	var n: int=layout["grid"]
	var gx:=clampf(x/step+n*.5,0,n-.001)
	var gz:=clampf(z/step+n*.5,0,n-.001)
	var ix:=floori(gx);var iz:=floori(gz)
	var heights: Array=layout["heights"]
	return lerpf(lerpf(heights[iz][ix],heights[iz][ix+1],gx-ix),lerpf(heights[iz+1][ix],heights[iz+1][ix+1],gx-ix),gz-iz)


func environment(dungeon: bool) -> void:
	var node:=WorldEnvironment.new()
	var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color(.025,.035,.055) if dungeon else Color(.55,.69,.73)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color(.44,.53,.72) if dungeon else Color(.78,.85,.88)
	env.ambient_light_energy=.65 if dungeon else .6
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	env.glow_enabled=true
	env.glow_intensity=.4
	env.ssao_enabled=true
	env.ssao_radius=1.1
	env.ssao_intensity=1.2
	node.environment=env
	add(scene_root,node,"WorldEnvironment")
	if not dungeon:
		var sun:=DirectionalLight3D.new()
		sun.light_color=Color(1,.86,.67)
		sun.light_energy=1.0
		sun.shadow_enabled=true
		sun.directional_shadow_max_distance=130
		add(scene_root,sun,"LateAfternoonSun")
		sun.rotation_degrees=Vector3(-55,-25,0)


func location(parent: Node, id: StringName, display: String, at: Vector3, region: StringName) -> void:
	var node:=WorldLocation.new()
	node.location_id=id
	node.region_id=region
	node.display_name=display
	node.kind=WorldLocation.Kind.CLEARING
	node.discover_radius=8
	add(parent,node,String(id),at)


func spawn(parent: Node,title: String, at: Vector3) -> void:
	add(parent,Marker3D.new(),title,at)


func _outdoors() -> void:
	scene_root=Node3D.new()
	scene_root.name="RunewoodHighlands"
	scene_root.set_script(load("res://scripts/phase6/level.gd"))
	scene_root.set(&"region_id",&"runewood")
	environment(false)
	var terrain:=instance(scene_root,ART+"runewood_terrain.glb","Terrain")
	var solid:=StaticBody3D.new()
	add(scene_root,solid,"TerrainCollision")
	for mesh: MeshInstance3D in terrain.find_children("*","MeshInstance3D",true,false):
		if mesh.name.contains("stream"):continue
		var shape:=CollisionShape3D.new()
		shape.shape=mesh.mesh.create_trimesh_shape()
		add(solid,shape,"SculptedTerrain")
		shape.transform=mesh.transform
	instance(scene_root,ART+"runewood_newmap_dressing.glb","NewmapArt")
	for i in layout["solids"].size():
		var data: Dictionary=layout["solids"][i]
		var body:=StaticBody3D.new()
		add(scene_root,body,"ScenerySolid%03d"%i,Vector3(data["x"],data["y"],data["z"]))
		var shape:=CylinderShape3D.new()
		shape.radius=data["radius"]
		shape.height=3
		var collision:=CollisionShape3D.new()
		collision.shape=shape
		add(body,collision,"Trunk",Vector3.UP*1.5)
	# Bridge collider has smooth approaches; the supplied bridge remains the visual.
	for span: Array in [[-3.0,-1.5,surface_y(-8,-3),2.0],[-1.5,9.5,2.0,2.0],[9.5,11.0,2.0,surface_y(-8,11)]]:
		var bridge:=StaticBody3D.new()
		add(scene_root,bridge,"BridgeRamp"+str(scene_root.get_child_count()))
		var points:=PackedVector3Array()
		for x in [-9.9,-6.1]:
			points.append_array([Vector3(x,span[2]-.3,span[0]),Vector3(x,span[3]-.3,span[1]),Vector3(x,span[2],span[0]),Vector3(x,span[3],span[1])])
		var shape:=ConvexPolygonShape3D.new()
		shape.points=points
		var col:=CollisionShape3D.new()
		col.shape=shape
		add(bridge,col,"Deck")
	# Backup collision follows the natural mountain ring, behind the visible ridges.
	for i in 48:
		var a:=float(i)*TAU/48
		var wall:=box(scene_root,"MountainBoundary%02d"%i,Vector3(8,40,1),Vector3(cos(a)*56.5,15,sin(a)*56.5))
		wall.rotation.y=-a-PI/2
	var spawns:=Node3D.new();add(scene_root,spawns,"Spawns")
	spawn(spawns,"Arrival",Vector3(-40,surface_y(-40,36)+.25,36))
	spawn(spawns,"DungeonReturn",Vector3(29,surface_y(29,-30)+.25,-30))
	var return_passage:=prop(scene_root,"sentinel_rune_stone","ReturnPassage",Vector3(-42,surface_y(-42,38),38))
	interact(return_passage,"Willowmere", "Return to",Vector3(1.2,0,-1.2))
	var gate:=prop(scene_root,"runewood_dungeon_entrance","DungeonGate",Vector3(29,surface_y(29,-35),-35))
	interact(gate,"Sentinel Vault", "Descend into",Vector3(0,0,1.8))
	for x in [26.0,32.0]:
		prop(scene_root,"crypt_brazier","GateFlame"+str(x),Vector3(x,surface_y(x,-32),-32))
	for pos: Vector2 in [Vector2(-28,-12),Vector2(-24,-14),Vector2(20,-21)]:
		prop(scene_root,"crypt_pillar","RuinPillar"+str(scene_root.get_child_count()),Vector3(pos.x,surface_y(pos.x,pos.y),pos.y))
	prop(scene_root,"amethyst_cluster","RidgeCrystal",Vector3(20,surface_y(20,-20),-20))
	location(scene_root,&"runewood_arrival","Wayfarer's Crossing",Vector3(-40,1,36),&"runewood")
	location(scene_root,&"runewood_camp","Amberleaf Refuge",Vector3(-33,1,25),&"runewood")
	location(scene_root,&"runewood_bridge","Moonbrook Bridge",Vector3(-8,2,4),&"runewood")
	location(scene_root,&"runewood_ruins","The Broken Watch",Vector3(-27,5,-12),&"runewood")
	location(scene_root,&"runewood_vault","Sentinel Vault Entrance",Vector3(29,6,-33),&"runewood")
	pack(OUT+"runewood_outdoors.tscn")


func enemy(parent: Node,title: String,at: Vector3, boss: bool=false, imp: bool=false) -> void:
	var body:=CharacterBody3D.new()
	body.set_script(load("res://scripts/phase6/vault_boss.gd" if boss else "res://scripts/enemies/forest_slime.gd"))
	add(parent,body,title,at)
	var health:=CombatHealth.new()
	health.max_health=260 if boss else (32 if imp else 44)
	add(body,health,"Health")
	body.set(&"health",health)
	body.set(&"move_speed",2.3 if boss else 1.8)
	body.set(&"detection_radius",12.0 if boss else 6.0)
	body.set(&"death_free_delay",1.2)
	if not boss:
		body.set(&"contact_damage",7.0)
		body.set(&"attack_windup",.6)
		body.set(&"attack_cooldown",1.5)
	var capsule:=CapsuleShape3D.new()
	capsule.radius=.95 if boss else .45
	capsule.height=3.0 if boss else 1.7
	var col:=CollisionShape3D.new();col.shape=capsule
	add(body,col,"Body",Vector3.UP*(1.5 if boss else .85))
	var visual:=Node3D.new()
	visual.set_script(load("res://scripts/phase6/bestiary_visual.gd"))
	add(body,visual,"BestiaryVisual")
	visual.scale=Vector3.ONE*(3.0 if boss else (1.0 if imp else 1.35))
	var model:=instance(visual,BESTIARY+("Imp.glb" if imp else "Puglin.glb"),"ActualBestiaryModel")
	# Bestiary is authored facing +Z; the existing Enemy controller faces local -Z.
	model.rotation.y=PI
	body.add_to_group(&"phase6_enemy",true)


func _dungeon() -> void:
	var prototype: Node3D=(load("res://scenes/generated/runewood_region.tscn") as PackedScene).instantiate()
	scene_root=prototype.get_node("Dungeon") as Node3D
	prototype.remove_child(scene_root)
	for node in scene_root.find_children("*","",true,false):
		if node.owner==prototype:node.owner=scene_root
	prototype.free()
	scene_root.name="SentinelDungeon"
	scene_root.position=Vector3.ZERO
	scene_root.set_script(load("res://scripts/phase6/level.gd"))
	scene_root.set(&"region_id",&"sentinel_vault")
	scene_root.get_node("ReturnLanding/Interactable").display_name="Runewood Highlands"
	# Keep the new dungeon's geometry independent of the older prototype scene.
	for title in ["CryptZone","WestWall-2","WestWall2"]:
		var node:=scene_root.get_node_or_null(title)
		if node!=null:node.free()
	(scene_root.get_node("HeartAltar") as Node3D).position=Vector3(0,0,-29.5)
	for x in [-10,-14]:
		prop(scene_root,"crypt_floor_4m","SidePassageFloor"+str(x),Vector3(x,0,0))
		for z in [-2.5,2.5]:
			var wall:=prop(scene_root,"crypt_wall_4m","SideWall"+str(scene_root.get_child_count()),Vector3(x,0,z))
			if z>0:wall.scale.y=.24
	for x in [-22,-18]:
		for z in [-2,2]:
			prop(scene_root,"crypt_floor_4m","ReliquaryFloor"+str(scene_root.get_child_count()),Vector3(x,0,z))
		for z in [-4.0,4.0]:
			var wall:=prop(scene_root,"crypt_wall_4m","ReliquaryWall"+str(scene_root.get_child_count()),Vector3(x,0,z))
			if z>0:wall.scale.y=.24
	for z in [-2,2]:prop(scene_root,"crypt_wall_4m","ReliquaryWest"+str(z),Vector3(-24,0,z),PI/2)
	prop(scene_root,"crypt_brazier","ReliquaryFlame",Vector3(-22,0,-2))
	# Actual props from the other newmap pack dress the side crypt.
	instance(scene_root,"res://assets/models/newmap_props/Chest_Wood.gltf","NewmapChest",Vector3(-22,0,1))
	instance(scene_root,"res://assets/models/newmap_props/Vase_Rubble_Medium.gltf","NewmapRubble",Vector3(-20,0,-2))
	environment(true)
	for at: Vector3 in [Vector3(0,4,0),Vector3(-20,4,0),Vector3(0,4,-24)]:
		var fill:=OmniLight3D.new()
		fill.light_color=Color(.93,.83,.72)
		fill.light_energy=.9
		fill.omni_range=11
		add(scene_root,fill,"ReflectedTorchLight"+str(scene_root.get_child_count()),at)
	var spawns:=Node3D.new();add(scene_root,spawns,"Spawns")
	spawn(spawns,"Arrival",Vector3(0,2.4,15.5))
	location(scene_root,&"vault_entry","The Descent",Vector3(0,2,15),&"sentinel_vault")
	location(scene_root,&"vault_hall","Hall of Embers",Vector3(0,0,2),&"sentinel_vault")
	location(scene_root,&"vault_side","The Forgotten Reliquary",Vector3(-20,0,0),&"sentinel_vault")
	location(scene_root,&"vault_boss","Gorvath's Sanctuary",Vector3(0,0,-23.5),&"sentinel_vault")
	enemy(scene_root,"ImpGuard",Vector3(-3,0,1),false,true)
	enemy(scene_root,"PuglinGuard",Vector3(4,0,-4))
	enemy(scene_root,"ReliquaryImp",Vector3(-20,0,0),false,true)
	enemy(scene_root,"Boss",Vector3(0,0,-24),true)
	var bar:=CanvasLayer.new();bar.set_script(load("res://scripts/phase6/boss_health_bar.gd"))
	add(scene_root,bar,"BossHealthBar")
	pack(OUT+"sentinel_dungeon.tscn")


func _gateway() -> void:
	scene_root=Node3D.new();scene_root.name="Phase6Gateway"
	var gate:=prop(scene_root,"runewood_dungeon_entrance","Entrance",Vector3(33,0,-34))
	interact(gate,"Runewood Highlands", "Travel to",Vector3(0,0,1.8))
	for i in 8:
		var path:=prop(scene_root,"runewood_path_flags","Trail%02d"%i,Vector3(18+i*2.05,.025,-22-i*1.4))
		path.scale=Vector3(.62,.12,.62);path.rotation.y=-.6
	location(scene_root,&"runewood_gateway","Road to Runewood",Vector3(33,0,-31),&"village")
	pack(OUT+"village_gateway.tscn")


func _maps() -> void:
	for dungeon in [false,true]:
		var image:=Image.create(512,512,false,Image.FORMAT_RGB8)
		for y in 512:
			for x in 512:
				var p:=Vector2(x*.25-64,y*.25-64)
				var color:=Color(.3,.42,.23)
				if dungeon:
					color=Color(.045,.055,.075)
					if Rect2(-8,-8,16,16).has_point(p) or Rect2(-2,-16,4,8).has_point(p) or Rect2(-1.8,8,3.6,10).has_point(p) or p.distance_to(Vector2(0,-23.5))<7.7 or Rect2(-24,-4,8,8).has_point(p) or Rect2(-16,-2,8,4).has_point(p):color=Color(.43,.49,.55)
				else:
					color=color.lerp(Color(.37,.38,.33),clampf((surface_y(p.x,p.y)-5)/15,0,1))
					for road: String in ["path","side_path"]:
						var points: Array=layout[road]
						for i in points.size()-1:
							if p.distance_to(Geometry2D.get_closest_point_to_segment(p,Vector2(points[i][0],points[i][1]),Vector2(points[i+1][0],points[i+1][1])))<2.2:color=Color(.63,.47,.28)
					if absf(p.y-(4+2.4*sin((p.x+8)*.075)))<2:color=Color(.16,.42,.5)
				image.set_pixel(x,y,color)
		image.save_png(ART+("vault_map.png" if dungeon else "runewood_map.png"))
