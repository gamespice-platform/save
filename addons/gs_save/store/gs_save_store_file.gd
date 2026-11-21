class_name GSSaveStoreFile
extends GSSaveStore

## A folder of files, one per key. Works on desktop and mobile; in a browser `user://` is backed by IndexedDB, so it works there too.
##
## Writes go through [method GSPaths.write_text]: a temporary file renamed over the target (with [member atomic]), and the browser's IndexedDB flushed, because a write that is only in the tab's memory is gone when the tab closes. A key is a file name, so it is held to [method valid_key]: anything else fails with a reason instead of reaching outside the folder. A file that cannot be read can be moved aside with [method set_aside] (never deleted) so one bad file costs one slot.

const SUFFIX := ".sav"
const ASIDE := ".corrupt"
const CHANNEL := "save.file"

var directory: String
var atomic: bool = true
## Most files the folder may hold; 0 is unlimited. A write of a new key past it fails with CODE_QUOTA.
var max_files: int = 0
## The ending of every file; [code].sav[/code] by default. A store that keeps another family's files (profiles, settings) sets its own, and [method keys] lists only files ending in it.
var suffix: String = SUFFIX
## What an unreadable file is renamed to, appended to its name; see [method set_aside].
var aside_suffix: String = ASIDE
## Decides which keys are usable; empty means [method valid_key]. A caller whose keys are made safe elsewhere (a hash, a scoped id) passes its own rule, taking a String and returning a bool.
var key_check: Callable = Callable()


func _init(p_directory: String = "user://saves", p_atomic: bool = true) -> void:
	directory = p_directory
	atomic = p_atomic


## A key is 1 to 96 of a-z, 0-9, underscore, dash and dot, and does not start with a dot.
static func valid_key(key: String) -> bool:
	if key.is_empty() or key.length() > 96 or key.begins_with("."):
		return false
	for c in key:
		if not (c >= "a" and c <= "z" or c >= "0" and c <= "9" or c == "_" or c == "-" or c == "."):
			return false
	return true


## The path a key lives at, without checking the key.
func path_for(key: String) -> String:
	return directory.path_join(key + suffix)


func _path(key: String) -> String:
	return directory.path_join(key + suffix)


func _usable(key: String) -> bool:
	return valid_key(key) if key_check.is_null() else bool(key_check.call(key))


func _gate(key: String) -> GSResult:
	if not _usable(key):
		return GSResult.fail(GSError.CODE_INVALID, "'%s' is not a usable save key (a-z 0-9 _ - . , no leading dot)" % key if key_check.is_null() else "'%s' is not a usable key" % key)
	return GSResult.success(null)


func read(key: String) -> GSResult:
	var gate := _gate(key)
	if not gate.ok:
		return gate
	if not FileAccess.file_exists(_path(key)):
		return GSResult.fail(GSError.CODE_IO, "no save under '%s'" % key)
	var f := FileAccess.open(_path(key), FileAccess.READ)
	if f == null:
		return GSResult.fail(GSError.CODE_IO, "cannot open '%s'" % _path(key), error_string(FileAccess.get_open_error()))
	return GSResult.success(f.get_as_text())


func write(key: String, text: String) -> GSResult:
	var gate := _gate(key)
	if not gate.ok:
		return gate
	if max_files > 0 and not exists(key) and keys().size() >= max_files:
		return GSResult.fail(GSError.CODE_QUOTA, "the save folder already holds %d files, max_files is %d" % [keys().size(), max_files])
	var written := GSPaths.write_text(_path(key), text, atomic)
	if not written.ok:
		return written.wrap("cannot write the save '%s'" % key)
	return GSResult.success(null)


func remove(key: String) -> GSResult:
	var gate := _gate(key)
	if not gate.ok:
		return gate
	if FileAccess.file_exists(_path(key)):
		var err := DirAccess.remove_absolute(_path(key))
		if err != OK:
			return GSResult.fail(GSError.CODE_IO, "cannot delete '%s'" % _path(key), error_string(err))
		# A removal is a write too: unflushed, the file returns on the next browser load.
		GSWeb.sync_filesystem()
	return GSResult.success(null)


func exists(key: String) -> bool:
	return _usable(key) and FileAccess.file_exists(_path(key))


func keys() -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(directory):
		return out
	for f in DirAccess.get_files_at(directory):
		if f.ends_with(suffix):
			out.append(f.trim_suffix(suffix))
	return out


## Moves an unreadable save to `<key>.sav.corrupt` (or the [member suffix] and [member aside_suffix] set) so it stays on disk for a person to recover and the slot can be written again. Fails when there is nothing to move.
func set_aside(key: String) -> GSResult:
	var gate := _gate(key)
	if not gate.ok:
		return gate
	if not FileAccess.file_exists(_path(key)):
		return GSResult.fail(GSError.CODE_IO, "no save under '%s'" % key)
	var target := _path(key) + aside_suffix
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
	var err := DirAccess.rename_absolute(_path(key), target)
	if err != OK:
		return GSResult.fail(GSError.CODE_IO, "cannot set '%s' aside" % key, error_string(err))
	GSWeb.sync_filesystem()
	GSLog.warn(CHANNEL, "a save was set aside", {"key": key, "to": target})
	return GSResult.success(target)
