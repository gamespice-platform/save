class_name DotSaveSlots
extends RefCounted

## Named save slots over any [DotSaveStore]: write a payload, load it back migrated to the current version, keep one backup and fall back to it when the newest copy is damaged. Plain object, no node: a game owns one per player.

const BACKUP := ".bak"

## A slot was written. [param bytes] is the size of the document.
signal saved(slot: String, bytes: int)
## A slot was read; [param from_backup] says the newest copy was damaged.
signal loaded(slot: String, from_backup: bool)
## Both copies of a slot were damaged and the newest was set aside (when the store can).
signal damaged(slot: String, reason: String)

var config: DotSaveConfig
var store: DotSaveStore
var migrations := DotSaveMigrations.new()


func _init(p_store: DotSaveStore, p_config: DotSaveConfig = null) -> void:
	store = p_store
	config = p_config if p_config != null else DotSaveConfig.new()


## A slot id is 1 to 64 of a-z, 0-9, underscore and dash, so it is safe as a file name everywhere.
static func valid_id(slot: String) -> bool:
	if slot.is_empty() or slot.length() > 64:
		return false
	for c in slot:
		if not (c >= "a" and c <= "z" or c >= "0" and c <= "9" or c == "_" or c == "-"):
			return false
	return true


func slots() -> PackedStringArray:
	var out := PackedStringArray()
	for k in store.keys():
		if not k.ends_with(BACKUP):
			out.append(k)
	out.sort()
	return out


func save(slot: String, payload: Dictionary, saved_at: int = 0) -> DotResult:
	var gate := _gate(slot)
	if not gate.ok:
		return gate
	if config.max_slots > 0 and not store.exists(slot) and slots().size() >= config.max_slots:
		return DotResult.fail(DotError.CODE_QUOTA, "already %d slots, max_slots is %d" % [slots().size(), config.max_slots])
	var enc := DotSaveDocument.encode(payload, config.current_version, config, saved_at)
	if not enc.ok:
		return enc
	if config.keep_backup and store.exists(slot):
		var old := store.read(slot)
		if old.ok:
			var kept := store.write(slot + BACKUP, old.value)
			if not kept.ok:
				return kept
	var written := store.write(slot, enc.value)
	if written.ok:
		saved.emit(slot, (enc.value as String).length())
	return written


## The payload of [param slot], migrated to the current version. A damaged newest copy falls back to the backup; the result's value is {payload, version, saved_at, from_backup}.
func load_slot(slot: String) -> DotResult:
	var gate := _gate(slot)
	if not gate.ok:
		return gate
	var first := _load_key(slot)
	if first.ok:
		first.value["from_backup"] = false
		loaded.emit(slot, false)
		return first
	if config.keep_backup and store.exists(slot + BACKUP):
		var second := _load_key(slot + BACKUP)
		if second.ok:
			second.value["from_backup"] = true
			loaded.emit(slot, true)
			return second
	if config.set_aside_damaged and first.code() != DotError.CODE_IO and store.exists(slot):
		store.set_aside(slot)
		damaged.emit(slot, str(first.error))
	return first


## What [param slot] holds without migrating it: {version, saved_at, bytes, current}. `current` is false when a migration is due. Fails like [method load_slot], and does not fall back to the backup.
func info(slot: String) -> DotResult:
	var gate := _gate(slot)
	if not gate.ok:
		return gate
	var raw := store.read(slot)
	if not raw.ok:
		return raw
	var dec := DotSaveDocument.decode(raw.value, config)
	if not dec.ok:
		return dec
	var d: Dictionary = dec.value
	return DotResult.success({
		"version": d["version"], "saved_at": d["saved_at"],
		"bytes": (raw.value as String).length(), "current": d["version"] == config.current_version,
	})


## Copies [param from] over [param to] byte for byte (no migration, checksum untouched). Refuses to overwrite unless [param overwrite].
func copy_slot(from: String, to: String, overwrite: bool = false) -> DotResult:
	var a := _gate(from)
	if not a.ok:
		return a
	var b := _gate(to)
	if not b.ok:
		return b
	if store.exists(to) and not overwrite:
		return DotResult.fail(DotError.CODE_STATE, "slot '%s' already exists" % to)
	var raw := store.read(from)
	if not raw.ok:
		return raw
	if config.max_slots > 0 and not store.exists(to) and slots().size() >= config.max_slots:
		return DotResult.fail(DotError.CODE_QUOTA, "already %d slots, max_slots is %d" % [slots().size(), config.max_slots])
	return store.write(to, raw.value)


## Makes the backup the current copy again (the player's "undo the last save"). Fails when there is no backup.
func restore_backup(slot: String) -> DotResult:
	var gate := _gate(slot)
	if not gate.ok:
		return gate
	var raw := store.read(slot + BACKUP)
	if not raw.ok:
		return raw
	return store.write(slot, raw.value)


func delete(slot: String) -> DotResult:
	var gate := _gate(slot)
	if not gate.ok:
		return gate
	store.remove(slot + BACKUP)
	return store.remove(slot)


func _gate(slot: String) -> DotResult:
	if not config.enabled:
		return DotResult.fail(DotError.CODE_STATE, "saving is disabled")
	if not valid_id(slot):
		return DotResult.fail(DotError.CODE_INVALID, "slot id '%s' is not 1-64 of a-z 0-9 _ -" % slot)
	return DotResult.success(null)


func _load_key(key: String) -> DotResult:
	var raw := store.read(key)
	if not raw.ok:
		return raw
	var dec := DotSaveDocument.decode(raw.value, config)
	if not dec.ok:
		return dec
	var d: Dictionary = dec.value
	var up := migrations.upgrade(d["payload"], d["version"], config.current_version)
	if not up.ok:
		return up
	return DotResult.success({"payload": up.value, "version": config.current_version, "saved_at": d["saved_at"]})
