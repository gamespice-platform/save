class_name DotSaveStore
extends RefCounted

## Where save text lives. A store holds opaque strings under keys; the slot logic above it does not know whether that is a folder, browser storage or a cloud service. Every method returns a [DotResult].


## The text under [param key]; fails with CODE_IO when there is none.
func read(_key: String) -> DotResult:
	return DotResult.fail(DotError.CODE_UNSUPPORTED, "store does not implement read")


func write(_key: String, _text: String) -> DotResult:
	return DotResult.fail(DotError.CODE_UNSUPPORTED, "store does not implement write")


func remove(_key: String) -> DotResult:
	return DotResult.fail(DotError.CODE_UNSUPPORTED, "store does not implement remove")


func exists(_key: String) -> bool:
	return false


func keys() -> PackedStringArray:
	return PackedStringArray()


## Keeps an unreadable entry for a person to recover and frees its key; the value is where it went. Stores that cannot do this say so.
func set_aside(_key: String) -> DotResult:
	return DotResult.fail(DotError.CODE_UNSUPPORTED, "store does not implement set_aside")
