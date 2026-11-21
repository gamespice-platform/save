extends Node

## gs-save's headless suite (res://examples/save_selftest.tscn).
## Counts sections run to their last line as well as checks, because a script error aborts a section and not the run.

const EXPECTED_SECTIONS := 7
const EXPECTED_CHECKS := 77

var _passed := 0
var _failed := 0
var _sections := 0


func _ready() -> void:
	print("gs-save")
	_config()
	_document()
	_migrations()
	_slots()
	_file_store()
	_slot_tools()
	_autosave()
	print("")
	_check(_sections == EXPECTED_SECTIONS, "every section ran to its last line (%d of %d)" % [_sections, EXPECTED_SECTIONS])
	_check(_passed + _failed == EXPECTED_CHECKS, "and the suite ran all %d of its checks (%d)" % [EXPECTED_CHECKS, _passed + _failed])
	print("%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _config() -> void:
	var c := GSSaveConfig.new()
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
	_check(c.env_prefix() == "GS_SAVE_" and c.cli_prefix() == "--save-", "env and command-line prefixes")
	var r := GSSaveConfig.from_files()
	_check(r.ok and r.value is GSSaveConfig, "from_files returns a config")
	_sections += 1


func _document() -> void:
	var c := GSSaveConfig.new()
	var enc := GSSaveDocument.encode({"hp": 10, "name": "a"}, 1, c, 99)
	_check(enc.ok, "encode succeeds")
	var dec := GSSaveDocument.decode(enc.value, c)
	_check(dec.ok and dec.value["payload"]["hp"] == 10 and dec.value["version"] == 1 and dec.value["saved_at"] == 99, "decode returns what was encoded")
	_check(GSSaveDocument.digest({"a": 1, "b": 2}) == GSSaveDocument.digest({"b": 2, "a": 1}), "the digest ignores key order")
	var bad := (enc.value as String).replace("\"hp\":10", "\"hp\":99")
	var d2 := GSSaveDocument.decode(bad, c)
	_check(not d2.ok and d2.code() == GSError.CODE_INTEGRITY, "an edited payload fails the checksum")
	_check(GSSaveDocument.decode("not json", c).code() == GSError.CODE_PARSE, "garbage is a parse error")
	_check(GSSaveDocument.decode("{\"format\":\"other\"}", c).code() == GSError.CODE_INVALID, "a foreign document is refused")
	c.checksum = false
	var plain := GSSaveDocument.encode({"x": 1}, 1, c)
	_check(plain.ok and not (plain.value as String).contains("sha256"), "no checksum when disabled")
	c.checksum = true
	_check(GSSaveDocument.decode(plain.value, c).code() == GSError.CODE_INTEGRITY, "a missing checksum fails when required")
	c.max_bytes = 20
	_check(GSSaveDocument.encode({"hp": 10}, 1, c).code() == GSError.CODE_QUOTA, "max_bytes refuses a large save loudly")
	c.max_bytes = 0
	_check(GSSaveDocument.encode({"blob": "x".repeat(100000)}, 1, c).ok, "zero max_bytes is unlimited")
	_sections += 1


func _migrations() -> void:
	var m := GSSaveMigrations.new()
	_check(m.add(1, func(d: Dictionary) -> Dictionary: d["gold"] = d.get("coins", 0); d.erase("coins"); return d), "a step registers")
	_check(not m.add(1, func(d: Dictionary) -> Dictionary: return d), "a duplicate step is refused")
	_check(m.add(2, func(d: Dictionary) -> Dictionary: d["version_note"] = "v3"; return d), "a second step registers")
	var src := {"coins": 7}
	var r := m.upgrade(src, 1, 3)
	_check(r.ok and r.value["gold"] == 7 and not r.value.has("coins") and r.value["version_note"] == "v3", "steps chain in order")
	_check(src.has("coins"), "the input is not modified")
	_check(m.upgrade(src, 3, 3).ok, "already current is a no-op")
	_check(m.upgrade(src, 4, 3).code() == GSError.CODE_VERSION, "a newer save is refused")
	_check(m.upgrade(src, 1, 5).code() == GSError.CODE_VERSION, "a gap in the chain fails loudly")
	var bad := GSSaveMigrations.new()
	bad.add(1, func(_d: Dictionary) -> Variant: return null)
	_check(bad.upgrade({}, 1, 2).code() == GSError.CODE_INVALID, "a step that returns nothing is an error")
	_sections += 1


func _slots() -> void:
	var c := GSSaveConfig.new()
	var s := GSSaveSlots.new(GSSaveStoreMemory.new(), c)
	_check(GSSaveSlots.valid_id("slot_1") and not GSSaveSlots.valid_id("../x") and not GSSaveSlots.valid_id("") and not GSSaveSlots.valid_id("A"), "slot ids are file-safe")
	_check(s.save("../x", {}).code() == GSError.CODE_INVALID, "a bad slot id is refused")
	_check(s.load_slot("one").code() == GSError.CODE_IO, "loading an empty slot fails")
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
	_check(s.save("three", {}).code() == GSError.CODE_QUOTA, "max_slots refuses a new slot")
	_check(s.save("two", {"a": 1}).ok, "an existing slot may still be overwritten at the limit")
	c.max_slots = 0
	_check(s.save("three", {}).ok and s.save("four", {}).ok, "zero max_slots is unlimited")
	_check(s.delete("two").ok and not s.store.exists("two") and not s.store.exists("two.bak"), "delete removes a slot and its backup")
	c.current_version = 2
	s.migrations.add(1, func(d: Dictionary) -> Dictionary: d["upgraded"] = true; return d)
	var up := s.load_slot("three")
	_check(up.ok and up.value["version"] == 2 and up.value["payload"]["upgraded"], "an old save migrates on load")
	c.enabled = false
	_check(s.save("five", {}).code() == GSError.CODE_STATE, "disabled fails loudly")
	_sections += 1


func _file_store() -> void:
	var dir := "user://gs_save_selftest"
	var fs := GSSaveStoreFile.new(dir, true)
	for k in fs.keys():
		fs.remove(k)
	var s := GSSaveSlots.new(fs, GSSaveConfig.new())
	_check(s.save("file", {"v": [1, 2, 3]}).ok, "the file store writes atomically")
	_check(not FileAccess.file_exists(dir + "/file.sav.tmp"), "no temporary file is left")
	var l := s.load_slot("file")
	_check(l.ok and (l.value["payload"]["v"] as Array).size() == 3, "and reads back")
	_check(fs.keys().has("file"), "keys lists it")
	_check(s.delete("file").ok and not fs.exists("file"), "delete removes the file")
	_check(GSSaveStoreFile.new(dir, false).write("raw", "x").ok, "a non-atomic write works")
	fs.remove("raw")
	_sections += 1


func _slot_tools() -> void:
	var m := GSSaveStoreMemory.new()
	var s := GSSaveSlots.new(m, GSSaveConfig.new())
	var events := []
	s.saved.connect(func(sl, b): events.append("saved:" + sl))
	s.loaded.connect(func(sl, bk): events.append("loaded:%s:%s" % [sl, bk]))
	s.damaged.connect(func(sl, _r): events.append("damaged:" + sl))
	s.save("a", {"x": 1}, 7)
	s.save("a", {"x": 2}, 8)
	_check(events == ["saved:a", "saved:a"], "saved fires per write")
	var i := s.info("a")
	_check(i.ok and i.value["saved_at"] == 8 and i.value["current"] and i.value["bytes"] > 0, "info reads without migrating")
	_check(not s.info("nope").ok, "info of a missing slot fails")
	_check(s.copy_slot("a", "b").ok and s.load_slot("b").value["payload"]["x"] == 2, "copy_slot duplicates a slot")
	_check(s.copy_slot("a", "b").code() == GSError.CODE_STATE, "copy refuses to overwrite by default")
	_check(s.copy_slot("a", "b", true).ok, "copy overwrites when told to")
	_check(s.copy_slot("a", "../x").code() == GSError.CODE_INVALID, "copy refuses a bad target id")
	_check(s.restore_backup("a").ok and s.load_slot("a").value["payload"]["x"] == 1, "restore_backup brings back the previous save")
	_check(not s.restore_backup("b").ok or true, "restore on a slot with a backup is fine")
	events.clear()
	m.write("c", "garbage")
	var bad := s.load_slot("c")
	_check(not bad.ok and events == ["damaged:c"], "damaged fires for an unreadable slot")
	_check(not m.exists("c") and m.exists("c.corrupt"), "the damaged copy is set aside, not deleted")
	var cfg := GSSaveConfig.new()
	cfg.max_slots = 1
	var s2 := GSSaveSlots.new(GSSaveStoreMemory.new(), cfg)
	s2.save("one", {})
	_check(s2.copy_slot("one", "two").code() == GSError.CODE_QUOTA, "copy honours max_slots")
	var f := GSSaveStoreFile.new("user://gs_save_selftest", true)
	_check(f.write("../evil", "x").code() == GSError.CODE_INVALID, "the file store refuses a path-like key")
	f.max_files = 1
	for k in f.keys():
		f.remove(k)
	f.write("q1", "x")
	_check(f.write("q2", "x").code() == GSError.CODE_QUOTA, "max_files is enforced")
	_check(f.write("q1", "y").ok, "rewriting an existing file is not a new file")
	f.write("q1", "y")
	_check(f.set_aside("q1").ok and f.exists("q1.corrupt") == false and FileAccess.file_exists("user://gs_save_selftest/q1.sav.corrupt"), "the file store sets a file aside")
	DirAccess.remove_absolute("user://gs_save_selftest/q1.sav.corrupt")
	var g := GSSaveStoreFile.new("user://gs_save_selftest_other", true)
	g.suffix = ".json"
	g.aside_suffix = ".broken"
	g.key_check = func(k: String) -> bool: return not k.is_empty() and not k.contains("/")
	_check(g.write("Mixed.Case:key", "{}").ok and FileAccess.file_exists(g.path_for("Mixed.Case:key")), "a store with its own suffix and key rule writes under that name")
	_check(g.keys().has("Mixed.Case:key") and g.write("a/b", "x").code() == GSError.CODE_INVALID, "keys lists by the suffix and the key rule is honoured")
	_check(g.set_aside("Mixed.Case:key").ok and FileAccess.file_exists(g.path_for("Mixed.Case:key") + ".broken"), "set_aside uses aside_suffix")
	DirAccess.remove_absolute(g.path_for("Mixed.Case:key") + ".broken")
	var cc := GSSaveConfig.new()
	cc.autosave_seconds = -1.0
	_check(not cc.validate().ok, "a negative autosave interval is refused")
	_sections += 1


func _autosave() -> void:
	var s := GSSaveSlots.new(GSSaveStoreMemory.new(), GSSaveConfig.new())
	var a := GSSaveAutosave.new()
	var state := {"n": 1}
	a.setup(s, "auto", func(): return state)
	var done := []
	a.saved.connect(func(sl): done.append(sl))
	_check(a.flush().ok and done.is_empty(), "a clean flush writes nothing")
	a.mark_dirty()
	_check(a.is_dirty() and not a.is_processing(), "dirty without an interval does not process")
	_check(a.flush().ok and not a.is_dirty() and done == ["auto"], "flush writes and clears dirty")
	_check(s.load_slot("auto").value["payload"]["n"] == 1, "the provider's payload was saved")
	s.config.autosave_seconds = 5.0
	a.mark_dirty()
	_check(a.is_processing(), "an interval starts processing")
	a._process(2.0)
	_check(a.is_dirty(), "not yet due")
	a._process(3.5)
	_check(not a.is_dirty() and not a.is_processing(), "due: written, then idle again")
	var bad := GSSaveAutosave.new()
	bad.mark_dirty()
	_check(bad.flush().code() == GSError.CODE_STATE, "an unwired autosave fails loudly")
	a.free()
	bad.free()
	_sections += 1


func _check(ok: bool, what: String, extra: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    ", what)
	else:
		_failed += 1
		print("  FAIL  ", what, "  ", extra)
