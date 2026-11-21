class_name DotSaveStoreFile
extends DotSaveStore

## A folder of files, one per key. Works on desktop and mobile; in a browser `user://` is backed by IndexedDB, so it works there too. With [member atomic] a write goes to `<key>.tmp` and is renamed over the target.

const SUFFIX := ".sav"

var directory: String
var atomic: bool = true


func _init(p_directory: String = "user://saves", p_atomic: bool = true) -> void:
	directory = p_directory
	atomic = p_atomic


func _path(key: String) -> String:
	return directory.path_join(key + SUFFIX)


func read(key: String) -> DotResult:
	if not FileAccess.file_exists(_path(key)):
		return DotResult.fail(DotError.CODE_IO, "no save under '%s'" % key)
	var f := FileAccess.open(_path(key), FileAccess.READ)
	if f == null:
		return DotResult.fail(DotError.CODE_IO, "cannot open '%s'" % _path(key), error_string(FileAccess.get_open_error()))
	return DotResult.success(f.get_as_text())


func write(key: String, text: String) -> DotResult:
	var made := DirAccess.make_dir_recursive_absolute(directory)
	if made != OK:
		return DotResult.fail(DotError.CODE_IO, "cannot create '%s'" % directory, error_string(made))
	var target := _path(key)
	var dest := target + ".tmp" if atomic else target
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if f == null:
		return DotResult.fail(DotError.CODE_IO, "cannot write '%s'" % dest, error_string(FileAccess.get_open_error()))
	f.store_string(text)
	f.close()
	if atomic:
		var err := DirAccess.rename_absolute(dest, target)
		if err != OK:
			return DotResult.fail(DotError.CODE_IO, "cannot move '%s' into place" % dest, error_string(err))
	return DotResult.success(null)


func remove(key: String) -> DotResult:
	if FileAccess.file_exists(_path(key)):
		var err := DirAccess.remove_absolute(_path(key))
		if err != OK:
			return DotResult.fail(DotError.CODE_IO, "cannot delete '%s'" % _path(key), error_string(err))
	return DotResult.success(null)


func exists(key: String) -> bool:
	return FileAccess.file_exists(_path(key))


func keys() -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(directory):
		return out
	for f in DirAccess.get_files_at(directory):
		if f.ends_with(SUFFIX):
			out.append(f.trim_suffix(SUFFIX))
	return out
