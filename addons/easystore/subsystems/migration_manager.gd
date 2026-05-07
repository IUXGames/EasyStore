# migration_manager.gd
# Applies versioned migrations to SaveFile data when loading an old save.
#
# Usage:
#   EasyStore.register_migration(1, 2, func(sections):
#       sections["player"]["stamina"] = 100
#       return sections
#   )
#   EasyStore.set_current_version(2)
extends Node

var _migrations: Dictionary = {}   # { from_version (int) -> { to: int, fn: Callable } }
var _current_version: int  = 1
var _events: Node   # StoreEvents, injected by EasyStore


func setup(events: Node) -> void:
	_events = events


func set_current_version(version: int) -> void:
	_current_version = version


func get_current_version() -> int:
	return _current_version


## Register a migration step from one version to the next.
## fn receives sections: Dictionary and must return the transformed Dictionary.
func register_migration(from_version: int, to_version: int, fn: Callable) -> void:
	if to_version <= from_version:
		push_error("EasyStore: register_migration() to_version (%d) must be greater than from_version (%d). Ignoring." % [to_version, from_version])
		return
	_migrations[from_version] = { "to": to_version, "fn": fn }


## Apply all registered migrations to bring save_file up to _current_version.
## Mutates save_file.sections and save_file.version in place.
## Returns OK on success, ERR_INVALID_DATA if a migration callable fails.
func migrate(save_file: SaveFile) -> Error:
	if save_file.version >= _current_version:
		return OK

	var version := save_file.version
	var visited: Array[int] = []

	while version < _current_version:
		if version in visited:
			push_error("EasyStore: Migration cycle detected at v%d — aborting to prevent infinite loop." % version)
			return ERR_INVALID_DATA
		visited.append(version)
		if not _migrations.has(version):
			push_warning("EasyStore: No migration registered from v%d. Skipping." % version)
			version += 1
			continue

		var step: Dictionary = _migrations[version]
		var fn: Callable     = step["fn"]
		var to_v: int        = step["to"]

		var result = fn.call(save_file.sections)
		if result == null or not (result is Dictionary):
			push_error("EasyStore: Migration v%d→v%d returned null or non-Dictionary." % [version, to_v])
			_events.log_entry.emit("ERROR", "Migration failed v%d->v%d" % [version, to_v], {})
			return ERR_INVALID_DATA

		save_file.sections = result
		var old_v := version
		version   = to_v

		_events.log_entry.emit("INFO", "Migration applied v%d->v%d" % [old_v, version], {})
		_events.migration_applied.emit(old_v, version)

	save_file.version = _current_version
	if save_file.metadata != null:
		save_file.metadata.save_version = _current_version
	return OK
