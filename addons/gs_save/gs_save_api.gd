extends RefCounted

## GameSpice Save's API level. The rule for bumping it is on [GSAddonApi].

# 1: first slice, see README.
# 2: slot info/copy/restore, signals, autosave node, file store quota and set-aside.
# 3: GSSaveStoreFile suffix, aside_suffix, key_check and path_for, so other addons' file stores can sit on it.
const LEVEL := 3
const OLDEST := 1
