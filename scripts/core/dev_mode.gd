class_name DevMode
extends RefCounted
## Development/test conveniences (e.g. starting gold) are on for debug builds run with a
## real window: playing from the editor or a debug export. They are off in release
## exports and in headless runs (automated tests and CI keep the shipped rules).
## Override per run with the user arguments `-- --dev` or `-- --no-dev`.


static func is_enabled() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--no-dev"):
		return false
	if args.has("--dev"):
		return true
	return OS.is_debug_build() and DisplayServer.get_name() != "headless"
