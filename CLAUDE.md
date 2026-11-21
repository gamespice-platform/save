# GameSpice Save

Save games: slots, versioned documents, migrations, atomic writes, integrity. Read the family [CLAUDE.md](../../CLAUDE.md) first. **The distributable is `addons/gs_save/`**; it requires [GameSpice Core](../gs-core) only (`ln -s ../../gs-core/addons/gs_core addons/gs_core`, gitignored).

| Path | What |
| --- | --- |
| `core/gs_save_config.gd` | `GSSaveConfig`: every tunable, `from_files()` |
| `core/gs_save_document.gd` | `GSSaveDocument`: the envelope, encode, decode, sha256 digest (pure) |
| `core/gs_save_migrations.gd` | `GSSaveMigrations`: N to N+1 steps, a gap fails loudly |
| `store/gs_save_store*.gd` | `GSSaveStore` interface, `Memory`, `File` (atomic) |
| `runtime/gs_save_slots.gd` | `GSSaveSlots`: slots, backup fallback, slot limit |
| `examples/save_selftest.tscn` | the suite |

- **Boundary**: not gs-settings (options and scopes), not gs-achievements/gs-stats (reported to the backbone), not gs-cloud (content delivery; a cloud save is a `GSSaveStore` the game supplies). No class name overlaps any other addon.
- **No hard caps**: `max_bytes` and `max_slots` are 0 = unlimited; every failure is a `GSResult`, never a silent skip.
- **Pack rules**: no `uid://`, load by path.
- **Validate**: `--import`, parse every `.gd`, run the suite.
