class_name DotSaveDocument
extends RefCounted

## The envelope around a save: {format, version, saved_at, payload, sha256}. Pure functions, no files, so a server and a suite can check a save without a store.

const FORMAT := "gamespice-save"


## The text of a document holding [param payload] (a Dictionary of JSON types) at [param version].
static func encode(payload: Dictionary, version: int, cfg: DotSaveConfig, saved_at: int = 0) -> DotResult:
	var doc := {"format": FORMAT, "version": version, "saved_at": saved_at, "payload": payload}
	if cfg.checksum:
		doc["sha256"] = digest(payload)
	var text := JSON.stringify(doc, "", true)
	if cfg.max_bytes > 0 and text.to_utf8_buffer().size() > cfg.max_bytes:
		return DotResult.fail(DotError.CODE_QUOTA, "save is %d bytes, over max_bytes %d" % [text.to_utf8_buffer().size(), cfg.max_bytes])
	return DotResult.success(text)


## Parse and verify [param text]. The result's value is {version, saved_at, payload}. A checksum that is present is always checked; one that is missing fails when the config asks for checksums.
static func decode(text: String, cfg: DotSaveConfig) -> DotResult:
	if cfg.max_bytes > 0 and text.to_utf8_buffer().size() > cfg.max_bytes:
		return DotResult.fail(DotError.CODE_QUOTA, "save is over max_bytes %d" % cfg.max_bytes)
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if not (parsed is Dictionary):
		return DotResult.fail(DotError.CODE_PARSE, "save is not a JSON object")
	var doc: Dictionary = parsed
	if doc.get("format", "") != FORMAT:
		return DotResult.fail(DotError.CODE_INVALID, "not a GameSpice save (format '%s')" % str(doc.get("format", "")))
	if not (doc.get("payload") is Dictionary) or not doc.has("version"):
		return DotResult.fail(DotError.CODE_INVALID, "save has no payload or version")
	var payload: Dictionary = doc["payload"]
	if doc.has("sha256"):
		if not DotHash.constant_time_equal_hex(str(doc["sha256"]), digest(payload)):
			return DotResult.fail(DotError.CODE_INTEGRITY, "save checksum does not match its payload")
	elif cfg.checksum:
		return DotResult.fail(DotError.CODE_INTEGRITY, "save has no checksum")
	return DotResult.success({"version": int(doc["version"]), "saved_at": int(doc.get("saved_at", 0)), "payload": payload})


## sha256 of the payload with keys sorted. The payload is first round-tripped through JSON so that 10 and 10.0, which a reload cannot tell apart, digest the same.
static func digest(payload: Dictionary) -> String:
	var canonical: Variant = JSON.parse_string(JSON.stringify(payload, "", true))
	return DotHash.sha256_text(JSON.stringify(canonical, "", true))
