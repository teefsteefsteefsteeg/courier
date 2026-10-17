@tool
class_name Signpost
extends StaticBody3D
## Wooden signpost whose board text is set per instance.

@export var text: String = "Signpost":
	set(value):
		text = value
		if is_node_ready():
			_apply_text()


func _ready() -> void:
	_apply_text()


func _apply_text() -> void:
	for label: Label3D in [$Board/FrontText, $Board/BackText]:
		label.text = text
