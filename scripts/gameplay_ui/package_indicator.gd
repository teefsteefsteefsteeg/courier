class_name PackageIndicator
extends Control
## Shows which package the player carries and its integrity.

@export var carrier: PackageCarrier

@onready var name_label: Label = %PackageName
@onready var integrity_label: Label = %PackageIntegrity
@onready var hint_label: Label = %PackageHint

var _package: PackageInstance = null


func _ready() -> void:
	visible = false
	if carrier != null:
		bind_carrier(carrier)


func bind_carrier(new_carrier: PackageCarrier) -> void:
	carrier = new_carrier
	if not carrier.carried_package_changed.is_connected(_on_package_changed):
		carrier.carried_package_changed.connect(_on_package_changed)
	_on_package_changed(carrier.get_package())


func _on_package_changed(package: PackageInstance) -> void:
	if _package != null and _package.integrity_changed.is_connected(_on_integrity_changed):
		_package.integrity_changed.disconnect(_on_integrity_changed)
	_package = package
	visible = package != null
	if package == null:
		return
	package.integrity_changed.connect(_on_integrity_changed)
	name_label.text = "Carrying: %s" % package.definition.package_name
	hint_label.text = "[%s] Drop" % _key_text(&"drop_package")
	_on_integrity_changed(package.integrity, package.integrity)


func _on_integrity_changed(value: float, _old: float) -> void:
	integrity_label.text = "Integrity: %d%%" % roundi(value / maxf(_package.definition.integrity, 0.001) * 100.0)


func _key_text(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			return OS.get_keycode_string(key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode)
	return "?"
