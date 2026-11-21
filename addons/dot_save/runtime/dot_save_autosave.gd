class_name DotSaveAutosave
extends Node

## Keeps one slot written without the game thinking about it. The game calls [method mark_dirty] when something worth saving changed; the node writes the payload that [member provider] returns every [member DotSaveConfig.autosave_seconds] while dirty, and once more when the game closes or is paused. A clean document is never rewritten, so an idle player costs nothing: while clean the node does not process at all.

## An autosave or flush finished.
signal saved(slot: String)
## A write failed. The document stays dirty and is retried at the next interval.
signal failed(slot: String, error: DotResult)

var slots: DotSaveSlots
var slot: String = "auto"
## Returns the Dictionary to save. Called only when a write is due.
var provider: Callable = Callable()

var _dirty: bool = false
var _since: float = 0.0


## Wires the node to [param p_slots] and [param p_slot] and starts it idle.
func setup(p_slots: DotSaveSlots, p_slot: String, p_provider: Callable) -> void:
	slots = p_slots
	slot = p_slot
	provider = p_provider
	set_process(false)


func is_dirty() -> bool:
	return _dirty


## Something changed. Starts the interval clock on the first change after a save.
func mark_dirty() -> void:
	if _dirty:
		return
	_dirty = true
	_since = 0.0
	set_process(slots != null and slots.config.autosave_seconds > 0.0)


## Writes now if dirty. The value is the write's result, or a success with null when there was nothing to write.
func flush() -> DotResult:
	if not _dirty:
		return DotResult.success(null)
	if slots == null or not provider.is_valid():
		return DotResult.fail(DotError.CODE_STATE, "autosave is not set up")
	var r := slots.save(slot, provider.call(), int(Time.get_unix_time_from_system()))
	if r.ok:
		_dirty = false
		set_process(false)
		saved.emit(slot)
	else:
		failed.emit(slot, r)
	return r


func _process(delta: float) -> void:
	_since += delta
	if _since >= slots.config.autosave_seconds:
		_since = 0.0
		flush()


func _notification(what: int) -> void:
	if slots == null or not slots.config.save_on_exit:
		return
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_PREDELETE:
		if _dirty and provider.is_valid():
			flush()
