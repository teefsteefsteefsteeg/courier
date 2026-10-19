class_name UISettings
extends RefCounted
## Player UI preferences, saved to user://ui_settings.cfg. A settings menu (not built
## yet) toggles them with set_value(); HUD widgets read them every frame, so a change
## applies immediately.
##   UISettings.set_value(UISettings.SHOW_MOVEMENT_GUIDE, false)

const PATH := "user://ui_settings.cfg"
const SECTION := "hud"
## Movement key guide (WASD) in the gameplay HUD.
const SHOW_MOVEMENT_GUIDE := "show_movement_guide"
## Glow, sparkles and aura of enhanced weapons and armor (EnhancementVisuals). Cosmetic
## only: hiding them keeps every enhancement bonus.
const SHOW_ENHANCEMENT_VFX := "show_enhancement_vfx"
const DEFAULTS := {
	SHOW_MOVEMENT_GUIDE: true,
	SHOW_ENHANCEMENT_VFX: true,
}

static var _config: ConfigFile = null
## Set false (tests) to change values without writing the file.
static var persist: bool = true


static func get_value(key: String) -> Variant:
	return _load().get_value(SECTION, key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant) -> void:
	_load().set_value(SECTION, key, value)
	if persist:
		var error := _config.save(PATH)
		if error != OK:
			push_warning("UISettings: could not save %s (%s)" % [PATH, error_string(error)])


static func show_movement_guide() -> bool:
	return bool(get_value(SHOW_MOVEMENT_GUIDE))


static func show_enhancement_vfx() -> bool:
	return bool(get_value(SHOW_ENHANCEMENT_VFX))


## Forgets the cached file so the next read reloads it (tests).
static func reload() -> void:
	_config = null


static func _load() -> ConfigFile:
	if _config == null:
		_config = ConfigFile.new()
		if FileAccess.file_exists(PATH):
			_config.load(PATH)
	return _config
