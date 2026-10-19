extends Node3D
@export var region_id: StringName = &"runewood"


func _ready() -> void:
	_bind.call_deferred()


func _bind() -> void:
	var router:=get_tree().get_first_node_in_group(&"phase6_router")
	if router==null:return
	if region_id==&"runewood":
		$ReturnPassage/Interactable.interacted.connect(func(p: Node)->void:router.travel(&"village",&"Arrival",p))
		$DungeonGate/Interactable.interacted.connect(func(p: Node)->void:router.travel(&"sentinel_vault",&"Arrival",p))
	else:
		$ReturnLanding/Interactable.interacted.connect(func(p: Node)->void:router.travel(&"runewood",&"DungeonReturn",p))
		var boss:=get_node("Boss") as Enemy
		if SaveGame.find(get_tree()).world_progress.get("sentinel_defeated",false):
			boss.health.apply_damage(boss.health.max_health,Vector3.ZERO)
