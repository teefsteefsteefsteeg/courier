extends SceneTree
## Fast save-compatibility and independent-region fog regression tests.
var passed:=0
var failed:=0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String)->void:
	if ok:passed+=1;print("PASS ",label)
	else:failed+=1;printerr("FAIL ",label)

func _run()->void:
	var exploration:=ExplorationService.new()
	root.add_child(exploration)
	exploration.reveal_around(Vector2(30,30),4)
	exploration.activate_portal(&"willowmere_portal")
	check(exploration.is_explored(Vector2(30,30)),"village fog revealed before travel")
	exploration.set_region(&"runewood")
	check(not exploration.is_explored(Vector2(30,30)),"new region begins with independent fog")
	exploration.reveal_around(Vector2(-40,36),6)
	exploration.discover(&"runewood_camp")
	exploration.set_region(&"sentinel_vault")
	check(not exploration.is_explored(Vector2(-40,36)),"dungeon has an independent fog grid")
	exploration.reveal_around(Vector2(0,-24),5)
	var saved:=exploration.to_dict()
	exploration.from_dict({})
	check(exploration.region_id==&"village" and is_zero_approx(exploration.get_explored_ratio()),"legacy exploration saves load as fresh village fog")
	exploration.from_dict(saved)
	check(exploration.region_id==&"sentinel_vault" and exploration.is_explored(Vector2(0,-24)),"active dungeon fog survives save/load")
	exploration.set_region(&"runewood")
	check(exploration.is_explored(Vector2(-40,36)) and not exploration.is_explored(Vector2(30,30)),"outdoor fog restored without leaking village cells")
	exploration.set_region(&"village")
	check(exploration.is_explored(Vector2(30,30)),"return restores original village fog")
	check(exploration.is_discovered(&"runewood_camp") and exploration.is_portal_active(&"willowmere_portal"),"global discovery and existing portal activations survive all transitions")
	var old:=WorldLocation.new();old.location_id=&"old";old.region_id=&"village"
	root.add_child(old);exploration.register_location(old)
	var region:=WorldLocation.new();region.location_id=&"new";region.region_id=&"runewood"
	root.add_child(region);exploration.register_location(region)
	check(exploration.get_locations().has(old) and not exploration.get_locations().has(region),"surface map excludes other region landmarks")
	exploration.set_region(&"runewood")
	check(exploration.get_locations().has(region) and not exploration.get_locations().has(old),"new map excludes village landmarks")
	var save:=SaveGame.new();save.enabled=false
	root.add_child(save)
	await process_frame
	save.world_progress["sentinel_defeated"]=true
	var data:=save.to_dict()
	save.world_progress.clear()
	save.from_dict(data)
	check(save.world_progress.get("sentinel_defeated",false),"one-time boss victory flag survives save serialization")
	save.from_dict({})
	check(save.world_progress.is_empty(),"legacy saves begin without a boss reward claimed")
	root.remove_child(save);save.free()
	root.remove_child(old);old.free();root.remove_child(region);region.free()
	root.remove_child(exploration);exploration.free()
	await process_frame
	print("=== Phase 6 world state: %d passed, %d failed ==="%[passed,failed])
	quit(failed)
