# sync_manager.gd
# Orchestrates multiple simultaneous backends.
#
# Responsibilities:
#   - Route save/load calls to ALL active backends in parallel
#   - Compare timestamps when syncing two backends that have diverged
#   - Apply the configured ConflictStrategy
#   - Emit sync_completed / sync_conflict on StoreEvents
extends Node

var _events:   Node   # StoreEvents, injected
var _strategy: StoreEnums.ConflictStrategy = StoreEnums.ConflictStrategy.NEWEST_WINS
var _logger:   Node   # StoreLogger, injected


func setup(events: Node, logger: Node, strategy: StoreEnums.ConflictStrategy) -> void:
	_events   = events
	_logger   = logger
	_strategy = strategy


# ─── Multi-backend save ───────────────────────────────────────────────────────

## Dispatch a save_file write to every backend in backends_list.
## Fires backend_save on each; callers await save_completed signals individually.
func broadcast_save(backends: Array, slot: int, save_file: SaveFile) -> void:
	for backend in backends:
		backend.backend_save(slot, save_file)


# ─── Multi-backend sync ───────────────────────────────────────────────────────

## Compare metadata from two backends and determine which data wins.
## Returns the BackendType that should be treated as authoritative,
## or -1 if conflict requires manual resolution.
func resolve_conflict(
	slot:          int,
	local_meta:    SaveMetadata,
	cloud_meta:    SaveMetadata,
	local_data:    Dictionary,
	cloud_data:    Dictionary,
) -> int:  # returns BackendType or -1
	match _strategy:
		StoreEnums.ConflictStrategy.NEWEST_WINS:
			if local_meta == null:
				return StoreEnums.BackendType.STEAM_CLOUD
			if cloud_meta == null:
				return StoreEnums.BackendType.LOCAL
			return StoreEnums.BackendType.LOCAL if local_meta.timestamp >= cloud_meta.timestamp \
			       else StoreEnums.BackendType.STEAM_CLOUD

		StoreEnums.ConflictStrategy.CLOUD_WINS:
			return StoreEnums.BackendType.STEAM_CLOUD

		StoreEnums.ConflictStrategy.LOCAL_WINS:
			return StoreEnums.BackendType.LOCAL

		StoreEnums.ConflictStrategy.MANUAL:
			# Emit section-by-section conflicts for the game to handle
			for key in local_data:
				if local_data[key] != cloud_data.get(key):
					_events.sync_conflict_detected.emit(
						slot, key, local_data[key], cloud_data.get(key, {})
					)
			return -1   # caller must wait for sync_conflict responses

	return StoreEnums.BackendType.LOCAL


## Build a log-friendly summary of the sync result.
func build_result(backends: Array, successes: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for backend in backends:
		var t: int = backend.get_backend_type()
		result[t]  = successes.get(t, false)
	return result
