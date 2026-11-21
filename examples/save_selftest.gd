extends Node

## dot-save's headless suite (res://examples/save_selftest.tscn).
## Counts sections run to their last line as well as checks, because a script error aborts a section and not the run.

const EXPECTED_SECTIONS := 5
const EXPECTED_CHECKS := 49

var _passed := 0
var _failed := 0
var _sections := 0


func _ready() -> void:
	print("dot-save")
	_config()
	_document()
	_migrations()
	_slots()
	_file_store()
	print("")
	_check(_sections == EXPECTED_SECTIONS, "every section ran to its last line (%d of %d)" % [_sections, EXPECTED_SECTIONS])
	_check(_passed + _failed == EXPECTED_CHECKS, "and the suite ran all %d of its checks (%d)" % [EXPECTED_CHECKS, _passed + _failed])
	print("%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _config() -> void:
	var c := DotSaveConfig.new()
	_check(c.validate().ok, "defaults validate")
	_check(c.max_bytes == 0 and c.max_slots == 0, "limits default to unlimited")
	c.current_version = 0
	_check(not c.validate().ok, "version 0 is refused")
	c.current_version = 3
	c.max_slots = -1
	_check(not c.validate().ok, "a negative limit is refused")
	c.max_slots = 0
	c.apply_dictionary({"current_version": 4, "keep_backup": false, "directory": "user://x"})
	_check(c.current_version == 4 and not c.keep_backup and c.directory == "user://x", "a dictionary layer sets every type")
	_check(c.env_prefix() == "DOT_SAVE_" and c.cli_prefix() == "--save-", "env and command-line prefixes")
	var r := DotSaveConfig.from_files()
	_check(r.ok and r.value is DotSaveConfig, "from_files returns a config")
	_sections += 1


func _document() -> void:
	var c := DotSaveConfig.new()
	var enc := DotSaveDocument.encode({"hp": 10, "name": "a"}, 1, c, 99)
	_check(enc.ok, "encode succeeds")
	var dec := DotSaveDocument.decode(enc.value, c)
	_check(dec.ok and dec.value["payload"]["hp"] == 10 and dec.value["version"] == 1 and dec.value["saved_at"] == 99, "decode returns what was encoded")
	_check(DotSaveDocument.digest({"a": 1, "b": 2}) == DotSaveDocument.digest({"b": 2, "a": 1}), "the digest ignores key order")
	var bad := (enc.value as String).replace("\"hp\":10", "\"hp\":99")
	var d2 := DotSaveDocument.decode(bad, c)
	_check(not d2.ok and d2.code() == DotError.CODE_INTEGRITY, "an edited payload fails the checksum")
	_check(DotSaveDocument.decode("not json", c).code() == DotError.CODE_PARSE, "garbage is a parse error")
	_check(DotSaveDocument.decode("{\"format\":\"other\"}", c).code() == DotError.CODE_INVALID, "a foreign document is refused")
	c.checksum = false
	var plain := DotSaveDocument.encode({"x": 1}, 1, c)
	_check(plain.ok and not (plain.value as String).contains("sha256"), "no checksum when disabled")
	c.checksum = true
	_check(DotSaveDocument.decode(plain.value, c).code() == DotError.CODE_INTEGRITY, "a missing checksum fails when required")
	c.max_bytes = 20
	_check(DotSaveDocument.encode({"hp": 10}, 1, c).code() == DotError.CODE_QUOTA, "max_bytes refuses a large save loudly")
	c.max_bytes = 0
	_check(DotSaveDocument.encode({"blob": "x".repeat(100000)}, 1, c).ok, "zero max_bytes is unlimited")
	_sections += 1


func _migrations() -> void:
	var m := DotSaveMigrations.new()
	_check(m.add(1, func(d: Dictionary) -> Dictionary: d["gold"] = d.get("coins", 0); d.erase("coins"); return d), "a step registers")
	_check(not m.add(1, func(d: Dictionary) -> Dictionary: return d), "a duplicate step is refused")
	_check(m.add(2, func(d: Dictionary) -> Dictionary: d["version_note"] = "v3"; return d), "a second step registers")
	var src := {"coins": 7}
	var r := m.upgrade(src, 1, 3)
	_check(r.ok and r.value["gold"] == 7 and not r.value.has("coins") and r.value["version_note"] == "v3", "steps chain in order")
	_check(src.has("coins"), "the input is not modified")
	_check(m.upgrade(src, 3, 3).ok, "already current is a no-op")
	_check(m.upgrade(src, 4, 3).code() == DotError.CODE_VERSION, "a newer save is refused")
	_check(m.upgrade(src, 1, 5).code() == DotError.CODE_VERSION, "a gap in the chain fails loudly")
	var bad := DotSaveMigrations.new()
	bad.add(1, func(_d: Dictionary) -> Variant: return null)
	_check(bad.upgrade({}, 1, 2).code() == DotError.CODE_INVALID, "a step that returns nothing is an error")
	_sections += 1


func _slots() -> void:
	var c := DotSaveConfig.new()
	var s := DotSaveSlots.new(DotSaveStoreMemory.new(), c)
	_check(DotSaveSlots.valid_id("slot_1") and not DotSaveSlots.valid_id("../x") and not DotSaveSlots.valid_id("") and not DotSaveSlots.valid_id("A"), "slot ids are file-safe")
	_check(s.save("../x", {}).code() == DotError.CODE_INVALID, "a bad slot id is refused")
	_check(s.load_slot("one").code() == DotError.CODE_IO, "loading an empty slot fails")
	_check(s.save("one", {"lvl": 1}).ok, "save writes")
	var l := s.load_slot("one")
	_check(l.ok and l.value["payload"]["lvl"] == 1 and not l.value["from_backup"], "load reads it back")
	_check(s.slots() == PackedStringArray(["one"]), "slots lists it")
	s.save("one", {"lvl": 2})
	_check(s.store.exists("one.bak"), "the previous copy is kept as a backup")
	_check(s.slots() == PackedStringArray(["one"]), "backups are not slots")
	s.store.write("one", "corrupt")
	var fb := s.load_slot("one")
	_check(fb.ok and fb.value["payload"]["lvl"] == 1 and fb.value["from_backup"], "a damaged save falls back to the backup")
	s.store.write("one.bak", "corrupt")
	_check(not s.load_slot("one").ok, "both damaged is an error")
	c.max_slots = 2
	s.save("two", {})
	_check(s.save("three", {}).code() == DotError.CODE_QUOTA, "max_slots refuses a new slot")
	_check(s.save("two", {"a": 1}).ok, "an existing slot may still be overwritten at the limit")
	c.max_slots = 0
	_check(s.save("three", {}).ok and s.save("four", {}).ok, "zero max_slots is unlimited")
	_check(s.delete("two").ok and not s.store.exists("two") and not s.store.exists("two.bak"), "delete removes a slot and its backup")
	c.current_version = 2
	s.migrations.add(1, func(d: Dictionary) -> Dictionary: d["upgraded"] = true; return d)
	var up := s.load_slot("three")
	_check(up.ok and up.value["version"] == 2 and up.value["payload"]["upgraded"], "an old save migrates on load")
	c.enabled = false
	_check(s.save("five", {}).code() == DotError.CODE_STATE, "disabled fails loudly")
	_sections += 1


func _file_store() -> void:
	var dir := "user://dot_save_selftest"
	var fs := DotSaveStoreFile.new(dir, true)
	for k in fs.keys():
		fs.remove(k)
	var s := DotSaveSlots.new(fs, DotSaveConfig.new())
	_check(s.save("file", {"v": [1, 2, 3]}).ok, "the file store writes atomically")
	_check(not FileAccess.file_exists(dir + "/file.sav.tmp"), "no temporary file is left")
	var l := s.load_slot("file")
	_check(l.ok and (l.value["payload"]["v"] as Array).size() == 3, "and reads back")
	_check(fs.keys().has("file"), "keys lists it")
	_check(s.delete("file").ok and not fs.exists("file"), "delete removes the file")
	_check(DotSaveStoreFile.new(dir, false).write("raw", "x").ok, "a non-atomic write works")
	fs.remove("raw")
	_sections += 1


func _check(ok: bool, what: String, extra: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    ", what)
	else:
		_failed += 1
		print("  FAIL  ", what, "  ", extra)
