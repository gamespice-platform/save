class_name GSSaveStoreMemory
extends GSSaveStore

## A store in a Dictionary: tests, a server that never persists, and the fallback when nothing else is allowed.

var _data: Dictionary = {}


func read(key: String) -> GSResult:
	if not _data.has(key):
		return GSResult.fail(GSError.CODE_IO, "no save under '%s'" % key)
	return GSResult.success(_data[key])


func write(key: String, text: String) -> GSResult:
	_data[key] = text
	return GSResult.success(null)


func remove(key: String) -> GSResult:
	_data.erase(key)
	return GSResult.success(null)


func exists(key: String) -> bool:
	return _data.has(key)


func keys() -> PackedStringArray:
	return PackedStringArray(_data.keys())


func set_aside(key: String) -> GSResult:
	if not _data.has(key):
		return GSResult.fail(GSError.CODE_IO, "no save under '%s'" % key)
	var to := key + ".corrupt"
	_data[to] = _data[key]
	_data.erase(key)
	return GSResult.success(to)
