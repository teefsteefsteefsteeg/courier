extends SceneTree
## End-to-end real physics and combat validation, optionally rendered by running without
## --headless. Never damages enemies directly: kills use existing live Magic Bolt attacks.
var passed:=0
var failed:=0
var level: Node3D
var player: PlayerController
var combat: CombatController
var router: Node
var render:=false
var shots:="res://docs/validation/phase6-newmap"
var boss: Enemy
var attacks: Array[StringName]=[]
var _saw_hp_drop:=false


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool,text: String) -> void:
	if ok:passed+=1;print("P6 PASS ",text)
	else:failed+=1;printerr("P6 FAIL ",text)


func frames(n: int=8) -> void:
	for i in n:await physics_frame
	await process_frame


func key(action: StringName) -> void:
	var event:=InputEventAction.new();event.action=action;event.pressed=true
	Input.parse_input_event(event);Input.flush_buffered_events()
	await frames(2)
	event=event.duplicate() as InputEventAction;event.pressed=false
	Input.parse_input_event(event);Input.flush_buffered_events()
	await frames(4)


func steer(direction: Vector3) -> void:
	var flat:=direction;flat.y=0
	flat=flat.normalized() if flat.length()>1 else flat
	for pair in [[&"move_right",&"move_left",flat.dot(player.camera_relative_direction(Vector2.RIGHT))],[&"move_back",&"move_forward",flat.dot(player.camera_relative_direction(Vector2.DOWN))]]:
		Input.action_release(pair[0]);Input.action_release(pair[1])
		if float(pair[2])>.05:Input.action_press(pair[0],float(pair[2]))
		elif float(pair[2])<-.05:Input.action_press(pair[1],-float(pair[2]))


func walk(to: Vector3,limit: int=800) -> bool:
	var ok:=false
	for i in limit:
		var delta:=to-player.global_position;delta.y=0
		if delta.length()<.45:ok=true;break
		steer(delta.normalized())
		await physics_frame
	steer(Vector3.ZERO)
	await frames(5)
	print("P6 WALK ",to," -> ",player.global_position," ok=",ok)
	return ok


func shot(title: String,zoom: float=16) -> void:
	if not render:return
	var rig:=level.get_node("IsoCameraRig") as IsoCameraRig
	rig.max_zoom_size=110
	rig.set_zoom(zoom);rig.snap_to_target()
	await frames(10)
	await RenderingServer.frame_post_draw
	var error:=root.get_texture().get_image().save_png(shots.path_join(title+".png"))
	check(error==OK,"rendered gameplay capture "+title)


func shoot(enemy: Enemy,limit: int=450) -> bool:
	for i in limit:
		if not is_instance_valid(enemy) or enemy.is_dead():return true
		var direction:=enemy.global_position-player.global_position
		player.facing.visual_root.rotation.y=FacingComponent.yaw_for_direction(direction)
		combat.try_attack(direction)
		await physics_frame
	return is_instance_valid(enemy) and enemy.is_dead()


func _run() -> void:
	render=DisplayServer.get_name()!="headless"
	root.size=Vector2i(1600,900)
	DirAccess.make_dir_recursive_absolute(shots)
	level=(load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	(level.get_node("GameplayServices/SaveGame") as SaveGame).enabled=false
	root.add_child(level);current_scene=level
	await frames(25)
	player=level.get_node("Player") as PlayerController
	combat=CombatController.find_on(player)
	router=level.get_node("Phase6Router")
	var player_id:=player.get_instance_id()
	var inventory:=CourierInventory.find(self)
	var inventory_id:=inventory.get_instance_id()
	var quests:=QuestManager.find(self)
	quests.accept_quest(&"q001_first_delivery")
	var quest_snapshot: Dictionary=quests.get_state(&"q001_first_delivery").to_dict() if quests.get_state(&"q001_first_delivery")!=null else {}
	combat.health.apply_damage(7)
	# Phase 8 HP regeneration would heal while walking to the vault: off, so the check below
	# sees only what the transition does to HP.
	CourierVitals.find(self).hp_regen_per_second=0.0
	combat._stamina=47
	combat._stamina_regen_wait=20
	var hp:=combat.health.get_health()
	var wallet:=CourierWallet.find(self)
	var gold:=wallet.gold
	var portal:=TeleportPortal.find(self,&"willowmere_portal")
	ExplorationService.find(self).activate_portal(portal.portal_id)
	player.teleport_to(Vector3(33,.15,-31.5))
	await frames(15)
	check(player.interaction.focused==level.get_node("Phase6Gateway/Entrance/Interactable"),"existing world has reachable Runewood passage")
	await key(&"interact")
	await frames(15)
	check(router.region_id==&"runewood" and router.active_level.scene_file_path.ends_with("runewood_outdoors.tscn"),"E loads the separate outdoor level scene")
	if router.region_id!=&"runewood":_finish();return
	check(player.get_instance_id()==player_id and inventory.get_instance_id()==inventory_id,"transition keeps the same player and inventory objects")
	check(get_nodes_in_group(CombatController.PLAYER_GROUP).size()==1,"exactly one player exists after scene transition")
	check(combat.health.get_health()==hp and combat.get_stamina()==47,"HP and stamina are preserved across transition")
	check(player.is_on_floor() and player.input_enabled,"new map arrival has safe solid ground and working controls")
	check(ExplorationService.find(self).region_id==&"runewood","new map uses its own saved fog grid")
	var outdoor:=router.active_level as Node3D
	if render:
		var rig:=level.get_node("IsoCameraRig") as IsoCameraRig
		var focus:=Marker3D.new();outdoor.add_child(focus);focus.position=Vector3(0,5,0)
		rig.target=focus;rig.camera.position.z=120;rig.camera.far=320
		await shot("01_newmap_overview",106)
		rig.target=player;rig.camera.position.z=40;rig.camera.far=150;focus.queue_free()
	for point: Vector3 in [Vector3(-30,0,21),Vector3(-18,0,13),Vector3(-8,0,11),Vector3(-8,0,-3)]:
		check(await walk(point),"walk main road / bridge to %s"%point)
	await shot("02_moonbrook_bridge_and_valley",25)
	var delivery_huds := level.find_children("DeliveryHUD","CanvasLayer",true,false)
	check(not delivery_huds.is_empty() and float(delivery_huds[0].get("alert_remaining"))<=0,"persistent HUD damage notices expire while village simulation is paused")
	check(ExplorationService.find(self).is_discovered(&"runewood_bridge"),"landmark discovery follows exploration")
	for point: Vector3 in [Vector3(1,0,-9),Vector3(-15,0,-15),Vector3(-27,0,-9)]:
		check(await walk(point),"optional ruin path reaches %s"%point)
	await shot("03_broken_watch_landmark",22)
	check(ExplorationService.find(self).is_discovered(&"runewood_ruins"),"optional landmark discovered")
	for point: Vector3 in [Vector3(-15,0,-15),Vector3(1,0,-9),Vector3(15,0,-18),Vector3(27,0,-27),Vector3(29,0,-32)]:
		check(await walk(point),"explore elevated path to %s"%point)
	await shot("04_dungeon_entrance",18)
	await key(&"interact")
	await frames(15)
	check(router.region_id==&"sentinel_vault" and router.active_level.scene_file_path.ends_with("sentinel_dungeon.tscn"),"entrance interaction loads separate dungeon scene")
	if router.region_id!=&"sentinel_vault":_finish();return
	var dungeon:=router.active_level as Node3D
	check(player.get_instance_id()==player_id and inventory.get_instance_id()==inventory_id,"dungeon transition retains session identity")
	check(combat.health.get_health()==hp,"entering dungeon preserves HP")
	check(await walk(Vector3(0,0,5.5)),"walk down physical underground stairway")
	await shot("05_dungeon_interior",20)
	var imp:=dungeon.get_node("ImpGuard") as Enemy
	var pug:=dungeon.get_node("PuglinGuard") as Enemy
	check(not imp.find_children("*","Skeleton3D",true,false).is_empty(),"normal monster is actual rigged Bestiary Imp")
	await shot("06_bestiary_guards",11)
	check(await shoot(imp),"defeat Bestiary Imp through live existing projectile combat")
	check(await shoot(pug),"defeat Bestiary Puglin through live existing projectile combat")
	check(await walk(Vector3(0,0,0)),"cross cleared chamber")
	check(await walk(Vector3(-20,0,0)),"side corridor leads to a second explorable chamber")
	var side_imp:=dungeon.get_node("ReliquaryImp") as Enemy
	check(await shoot(side_imp),"defeat separate reliquary encounter")
	await shot("07_reliquary_chamber",17)
	check(await walk(Vector3(0,0,0)),"return from side chamber")
	check(await walk(Vector3(0,0,-19)),"reach final boss arena through corridor")
	boss=dungeon.get_node("Boss") as Enemy
	boss.telegraphed.connect(func(kind: StringName)->void:attacks.append(kind))
	var bar:=dungeon.get_node("BossHealthBar")
	for i in 250:
		if boss.state==Enemy.State.WINDUP:break
		await physics_frame
	await frames(3)
	check(boss.engaged and bar.panel.visible,"boss detects courier and shows encounter-only HP bar")
	check(bar.hp.text=="260 / 260","boss bar binds real maximum/current HP")
	await shot("08_boss_telegraph_and_health_bar",20)
	var before_hit:=combat.health.get_health()
	for i in 300:
		if boss.attack_number>=1:break
		await physics_frame
	check(combat.health.get_health()<before_hit,"telegraphed mace attack damages through existing CombatHealth")
	for i in 350:
		if boss.attack_kind==&"rune_eruption" and boss.state==Enemy.State.WINDUP:break
		await physics_frame
	check(boss.attack_kind==&"rune_eruption","boss uses a distinct delayed ranged attack")
	await shot("09_boss_rune_attack",20)
	check(await walk(Vector3(0,0,-14)),"courier can retreat from the boss arena")
	check(not boss.engaged and not bar.panel.visible,"boss HP bar hides when leaving the arena")
	check(await walk(Vector3(0,0,-19)),"courier can re-enter the encounter")
	# Kite with real movement while existing Magic Bolts fly and collide. No direct HP writes.
	for i in 2400:
		if boss.is_dead():break
		var away:=player.global_position-boss.global_position;away.y=0
		var desired:=Vector3.ZERO
		if boss.state==Enemy.State.WINDUP:
			if boss.attack_kind==&"rune_eruption":desired=Vector3(0,0,2.5) if player.global_position.z<-21 else Vector3(0,0,-2.5)
			elif away.length()<4.2:desired=away.normalized()
		var next:=player.global_position+desired
		if next.x<-5 or next.x>5:desired.x=0
		if next.z<-28.3 or next.z>-17.2:desired.z=0
		steer(desired)
		combat.try_attack(boss.global_position-player.global_position)
		if not _saw_hp_drop and boss.health.get_health()<boss.health.max_health:
			_saw_hp_drop=true
			await shot("10_boss_damaged_hp",20)
		await physics_frame
	steer(Vector3.ZERO)
	check(_saw_hp_drop and boss.is_dead(),"boss is defeatable with existing live player attacks")
	check(boss.attack_number>=2,"both boss attacks resolved")
	await frames(30)
	check(not bar.panel.visible,"boss bar hides after victory")
	check(wallet.gold==gold+300 and SaveGame.find(self).world_progress.get("sentinel_defeated",false),"victory awards 300 gold once and persists completion flag")
	check(not router.claim_victory() and wallet.gold==gold+300,"victory reward cannot be claimed twice")
	await shot("11_boss_victory",20)
	check(await walk(Vector3(0,0,0)),"return from defeated boss arena")
	check(await walk(Vector3(0,0,15.5)),"climb stairs to dungeon exit")
	await key(&"interact");await frames(15)
	check(router.region_id==&"runewood","dungeon exit returns to outdoor map")
	# Return route is cached, not reconstructed. Use it to get back to the original world.
	check(router.active_level==outdoor,"outdoor map instance survives dungeon visit")
	for point: Vector3 in [Vector3(27,0,-27),Vector3(15,0,-18),Vector3(1,0,-9),Vector3(-8,0,-3),Vector3(-8,0,11),Vector3(-18,0,13),Vector3(-30,0,21),Vector3(-40,0,36)]:
		check(await walk(point),"walk return road to %s"%point)
	await key(&"interact");await frames(15)
	check(router.region_id==&"village","outdoor return passage restores original world")
	check(TeleportPortal.find(self,&"willowmere_portal").is_active(),"existing teleport activation preserved")
	check(player.get_instance_id()==player_id and inventory.get_instance_id()==inventory_id,"complete trip never duplicates player or inventory")
	if not quest_snapshot.is_empty():check(quests.get_state(&"q001_first_delivery").to_dict()==quest_snapshot,"in-progress quest preserved throughout the adventure")
	await shot("12_return_to_willowmere",16)
	ExplorationService.find(self).activate_portal(&"whisperwood_portal")
	var travel:=FastTravel.find(self)
	check(travel.travel(&"willowmere_portal",&"whisperwood_portal"),"existing portal fast travel still starts after the round trip")
	for i in 180:
		if not travel.travelling:break
		await physics_frame
	check(player.global_position.distance_to(TeleportPortal.find(self,&"whisperwood_portal").get_arrival_position())<3.5 and player.input_enabled,"existing fast travel reaches forest portal with controls restored")
	_finish()


func _finish() -> void:
	steer(Vector3.ZERO)
	root.remove_child(level);level.free()
	print("=== Phase 6 new map: %d passed, %d failed ==="%[passed,failed])
	quit(failed)
