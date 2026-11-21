class_name DotSaveMigrations
extends RefCounted

## Versioned upgrade steps. A step turns a payload of version N into one of version N+1; [method upgrade] chains them. A gap in the chain fails loudly rather than loading a half-understood save.

var _steps: Dictionary = {}


## Register the step from [param from_version] to the next. Returns false if one is already there.
func add(from_version: int, step: Callable) -> bool:
	if _steps.has(from_version) or not step.is_valid():
		return false
	_steps[from_version] = step
	return true


func has_step(from_version: int) -> bool:
	return _steps.has(from_version)


## Walk [param payload] from [param from_version] up to [param to_version]. Each step takes a Dictionary and returns a Dictionary.
func upgrade(payload: Dictionary, from_version: int, to_version: int) -> DotResult:
	if from_version > to_version:
		return DotResult.fail(DotError.CODE_VERSION, "save is version %d, newer than this build's %d" % [from_version, to_version])
	var data := payload.duplicate(true)
	var v := from_version
	while v < to_version:
		if not _steps.has(v):
			return DotResult.fail(DotError.CODE_VERSION, "no migration from save version %d" % v)
		var out: Variant = (_steps[v] as Callable).call(data)
		if not (out is Dictionary):
			return DotResult.fail(DotError.CODE_INVALID, "migration from version %d did not return a Dictionary" % v)
		data = out
		v += 1
	return DotResult.success(data)
