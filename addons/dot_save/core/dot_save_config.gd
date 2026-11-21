class_name GSSaveConfig
extends GSConfig

## Every tunable of the save system. `cfg/addon/dot_save/*.yml`, `DOT_SAVE_*` and `--save-*` layer over these defaults. A zero in a limit means unlimited.

const ADDON := "dot-save"

## Master switch: off, every save and load fails with a state error instead of silently doing nothing.
@export var enabled: bool = true

@export_group("Document")
## The document version this build writes. Older saves are migrated up to it on load.
@export_range(1, 1000, 1) var current_version: int = 1
## Write a sha256 over the payload and check it on load.
@export var checksum: bool = true
## Largest accepted document in bytes; 0 is unlimited.
@export_range(0, 1048576, 1024) var max_bytes: int = 0

@export_group("Slots")
## The most slots a player may hold; 0 is unlimited.
@export_range(0, 100, 1) var max_slots: int = 0
## Keep the previous document of a slot as a backup and fall back to it when the newest is damaged.
@export var keep_backup: bool = true

## When both copies of a slot are damaged, move the newest aside as `.corrupt` (never delete it) so the slot can be written again.
@export var set_aside_damaged: bool = true

@export_group("Autosave")
## Seconds between autosaves of a dirty document; 0 saves only when asked (flush, exit, pause).
@export_range(0.0, 3600.0, 1.0) var autosave_seconds: float = 0.0
## Save a dirty document when the game closes or is paused (a phone, a hidden browser tab).
@export var save_on_exit: bool = true

@export_group("Files")
## The most files the file store holds; 0 is unlimited.
@export_range(0, 100000, 1) var max_files: int = 0
## Where the file store writes.
@export var directory: String = "user://saves"
## Write to a temporary file and rename it over the target, so a crash never leaves half a save.
@export var atomic_writes: bool = true


func env_prefix() -> String:
	return "DOT_SAVE_"


func cli_prefix() -> String:
	return "--save-"


func validate() -> GSResult:
	if current_version < 1:
		return GSResult.fail(GSError.CODE_INVALID, "save current_version %d is below 1" % current_version)
	if max_bytes < 0 or max_slots < 0:
		return GSResult.fail(GSError.CODE_INVALID, "save limits cannot be negative (0 is unlimited)")
	if max_files < 0 or autosave_seconds < 0.0:
		return GSResult.fail(GSError.CODE_INVALID, "save max_files and autosave_seconds cannot be negative (0 is off or unlimited)")
	if directory.is_empty():
		return GSResult.fail(GSError.CODE_INVALID, "save directory is empty")
	return GSResult.success(self)


## Defaults, then `cfg/addon/dot_save/*.yml`, then environment and command line.
static func from_files() -> GSResult:
	var cfg := GSSaveConfig.new()
	var files := GSAddonConfig.load_dir(ADDON)
	if not files.ok:
		return files
	cfg.apply_dictionary(files.value as Dictionary, "yml")
	return cfg.load_layered()
