class_name DotSaveStoreMemory
extends DotSaveStore

## A store in a Dictionary: tests, a server that never persists, and the fallback when nothing else is allowed.

var _data: Dictionary = {}


func read(key: String) -> DotResult:
	if not _data.has(key):
		return DotResult.fail(DotError.CODE_IO, "no save under '%s'" % key)
	return DotResult.success(_data[key])


func write(key: String, text: String) -> DotResult:
	_data[key] = text
	return DotResult.success(null)


func remove(key: String) -> DotResult:
	_data.erase(key)
	return DotResult.success(null)


func exists(key: String) -> bool:
	return _data.has(key)


func keys() -> PackedStringArray:
	return PackedStringArray(_data.keys())


func set_aside(key: String) -> DotResult:
	if not _data.has(key):
		return DotResult.fail(DotError.CODE_IO, "no save under '%s'" % key)
	var to := key + ".corrupt"
	_data[to] = _data[key]
	_data.erase(key)
	return DotResult.success(to)
