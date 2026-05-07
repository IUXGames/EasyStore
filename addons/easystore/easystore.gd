# easystore.gd
# EasyStore — modular save system for Godot 4.
# Global singleton. Access from any script: EasyStore.save("player", data)
extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted just before a save is dispatched to the backends.
## Use this to show a saving indicator in your UI.
signal save_started(slot: int)
## Emitted when a save operation completes (all active backends finished).
signal save_completed(slot: int, success: bool)
## Emitted just before a load is dispatched to a backend.
## Use this to show a loading screen or spinner in your UI.
signal load_started(slot: int)
## Emitted when a load operation completes.
signal load_completed(slot: int, data: Dictionary, success: bool)
## Emitted by the autosave timer before the save is dispatched.
signal autosave_triggered(slot: int)
## Emitted after a backend is successfully added.
signal backend_added(type: StoreEnums.BackendType)
## Emitted after a backend is removed.
signal backend_removed(type: StoreEnums.BackendType)
## Emitted whenever a migration step is applied to a loaded save.
signal migration_applied(old_version: int, new_version: int)
## Emitted when a slot is deleted.
signal slot_deleted(slot: int)
## Emitted when a multi-backend sync finishes. result = { BackendType -> bool }
signal sync_completed(result: Dictionary)
## Emitted during sync when ConflictStrategy.MANUAL is set and data differs.
signal sync_conflict(slot: int, key: String, local_data: Variant, cloud_data: Variant)
## Emitted on any error.
signal error_occurred(code: int, message: String)

# ─── Subsystem references (resolved from child nodes in _ready) ───────────────

var _events:    Node   # StoreEvents
var _slots:     Node   # SlotManager
var _cache:     Node   # SectionCache
var _autosave:  Node   # AutosaveTimer
var _migrator:  Node   # MigrationManager
var _syncer:    Node   # SyncManager
var _worker:    Node   # AsyncWorker
var _debugger:  Node   # StoreDebugger
var _logger:    Node   # StoreLogger

# ─── State ────────────────────────────────────────────────────────────────────

## List of active StorageBackend instances (instantiated dynamically).
var _backends: Array[StorageBackend] = []
var _config:   EasyStoreConfig
var _initialized: bool = false
## Tracks in-flight multi-backend saves. slot → { "remaining": int, "all_success": bool }
## Ensures save_completed fires exactly once per save call, not once per backend.
var _pending_saves: Dictionary = {}

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_events   = $StoreEvents
	_slots    = $SlotManager
	_cache    = $SectionCache
	_autosave = $AutosaveTimer
	_migrator = $MigrationManager
	_syncer   = $SyncManager
	_worker   = $AsyncWorker
	_logger   = $StoreLogger
	_debugger = $StoreDebugger

	# Wire internal signals
	_events.autosave_tick.connect(_on_autosave_tick)
	_events.migration_applied.connect(func(o, n): migration_applied.emit(o, n))
	_events.slot_deleted.connect(func(s): slot_deleted.emit(s))
	_events.sync_conflict_detected.connect(
		func(s, k, l, c): sync_conflict.emit(s, k, l, c)
	)

# ─── Setup ────────────────────────────────────────────────────────────────────

## Initialize EasyStore. Call once at game start.
## If no config is provided, uses all defaults (local backend, slot 0).
func initialize(config: EasyStoreConfig = null) -> void:
	# Guard against being called before _ready() resolves child node references.
	# This happens when another autoload calls initialize() before EasyStore's
	# own _ready() has run due to autoload ordering.
	if not is_node_ready():
		await ready

	if _initialized:
		_logger.warn("EasyStore.initialize() called more than once — ignoring. Call it only once at startup.", "Core")
		return

	_config = config if config else EasyStoreConfig.new()

	_logger.setup(_config.log_level)
	_slots.setup(_events)
	_migrator.setup(_events)
	_migrator.set_current_version(_config.current_save_version)
	_autosave.setup(_events, Callable(self, "get_slot"))
	_syncer.setup(_events, _logger, _config.conflict_strategy)
	_debugger.setup(_logger, _events, _backends)

	_slots.set_slot(_config.default_slot)
	_initialized = true
	_logger.info("EasyStore ready. (save_version=%d, strategy=%s)" % [
		_config.current_save_version,
		StoreEnums.ConflictStrategy.keys()[_config.conflict_strategy],
	], "Core")

# ─── Backend management ───────────────────────────────────────────────────────

## Add a backend. Multiple backends can be active simultaneously.
## config is optional — uses default config values if null.
func add_backend(type: StoreEnums.BackendType, config: Resource = null) -> void:
	if has_backend(type):
		_logger.warn("Backend already active — skipping. Call remove_backend() first if you need to re-add it.", "Backend")
		return

	var backend: StorageBackend = _create_backend(type) as StorageBackend
	if backend == null:
		_emit_error(StoreEnums.ErrorCode.BACKEND_NOT_READY, "Unknown backend type: %d" % type)
		return

	add_child(backend)

	var cfg = config if config else _resolve_default_config(type)
	var err  = backend.initialize(cfg)

	if err != OK:
		backend.queue_free()
		if err == ERR_UNAVAILABLE:
			# ERR_UNAVAILABLE is expected (e.g. Steam not running). Warn, don't error.
			var reason = _unavailable_reason(type)
			_logger.warn("%s backend unavailable: %s" % [StoreEnums.BackendType.keys()[type], reason], "Backend")
		else:
			_emit_error(StoreEnums.ErrorCode.BACKEND_NOT_READY,
				"%s backend failed to initialize. (error=%d)" % [StoreEnums.BackendType.keys()[type], err])
		return

	_wire_backend(backend)
	_backends.append(backend)
	backend_added.emit(type)
	_logger.info(_ready_message(type), "Backend")


## Remove and shut down a backend.
func remove_backend(type: StoreEnums.BackendType) -> void:
	var backend = _get_backend(type)
	if backend == null:
		return
	_backends.erase(backend)
	backend.shutdown()
	backend.queue_free()
	backend_removed.emit(type)
	_logger.info("%s backend shut down and removed." % StoreEnums.BackendType.keys()[type], "Backend")


## Returns an array of currently active BackendType values.
func get_active_backends() -> Array[StoreEnums.BackendType]:
	var result: Array[StoreEnums.BackendType] = []
	for b in _backends:
		result.append(b.get_backend_type())
	return result


## Returns true if a backend of the given type is active AND initialized correctly.
## Use this to check if Steam (or any cloud backend) started successfully.
## Example:  if EasyStore.is_backend_ready(StoreEnums.BackendType.STEAM_CLOUD): ...
func is_backend_ready(type: StoreEnums.BackendType) -> bool:
	var b = _get_backend(type)
	return b != null and b.is_ready()


## Returns true if a backend of the given type is in the active list.
func has_backend(type: StoreEnums.BackendType) -> bool:
	return _get_backend(type) != null

# ─── Slot management ──────────────────────────────────────────────────────────

func set_slot(slot: int) -> void:
	_slots.set_slot(slot)


func get_slot() -> int:
	return _slots.get_slot()


func list_slots() -> Array[SaveMetadata]:
	return _slots.list_slots()


func delete_slot(slot: int) -> void:
	if not _initialized:
		push_warning("EasyStore: delete_slot() called before initialize() — ignoring. Call initialize() first.")
		return
	_cache.evict(slot)
	for b in _backends:
		b.backend_delete(slot)
	_slots.remove_slot(slot)


func has_slot(slot: int) -> bool:
	return _slots.has_slot(slot)

# ─── Save / Load ──────────────────────────────────────────────────────────────

## Write data to a section. Dispatched to ALL active backends.
## slot = -1 uses the current active slot.
func save(section: String, data: Dictionary, slot: int = -1) -> void:
	if not _initialized:
		push_warning("EasyStore: save() called before initialize() — ignoring. Call initialize() first.")
		return
	var s = _resolve_slot(slot)
	_cache.write(s, section, data)
	_flush_to_backends(s)


## Write ALL cached sections for a slot to all backends.
func save_all(slot: int = -1) -> void:
	if not _initialized:
		push_warning("EasyStore: save_all() called before initialize() — ignoring. Call initialize() first.")
		return
	var s = _resolve_slot(slot)
	_flush_to_backends(s)


## Read a section. Returns from cache if available, otherwise loads from backend.
## Returns {} if no data exists for that section.
func load(section: String, slot: int = -1) -> Dictionary:
	if not _initialized:
		push_warning("EasyStore: load() called before initialize() — returning {}. Call initialize() first.")
		return {}
	var s = _resolve_slot(slot)
	if _cache.has(s, section):
		return _cache.read(s, section)
	# Trigger async load; game should await load_completed or use load_all
	_load_slot_from_backend(s)
	return {}


## Trigger a full async load for a slot. Await load_completed to get data.
func load_all(slot: int = -1) -> void:
	if not _initialized:
		push_warning("EasyStore: load_all() called before initialize() — ignoring. Call initialize() first.")
		return
	var s = _resolve_slot(slot)
	_load_slot_from_backend(s)


## Returns save metadata for a slot, or null if the slot is unknown.
func get_save_metadata(slot: int = -1) -> SaveMetadata:
	return _slots.get_metadata(_resolve_slot(slot))


## Returns the absolute OS path where saves are stored for the local backend.
## Useful for showing the save location in settings menus or for debugging.
## Returns "" if no local backend is active.
func get_save_path(slot: int = -1) -> String:
	var local_b = _get_backend(StoreEnums.BackendType.LOCAL) as LocalBackend
	if local_b == null:
		return ""
	var s    = _resolve_slot(slot)
	var dir  = local_b._save_dir
	var file = "slot_%d.sav" % s
	return ProjectSettings.globalize_path(dir.path_join(file))

# ─── Multi-backend sync ───────────────────────────────────────────────────────

## Compare and sync all active backends for a slot.
## Supports both await patterns:
##   await EasyStore.sync()                           ← awaits the coroutine (recommended)
##   EasyStore.sync() + await EasyStore.sync_completed ← manual signal wait (also valid)
func sync(slot: int = -1) -> void:
	# Flag set by a ONE_SHOT listener so we know if _run_sync() emitted
	# sync_completed synchronously (e.g. no backends, Steam backend).
	# If it did, we skip the await — otherwise we suspend until the signal fires.
	# Because this function contains 'await', GDScript always treats it as a
	# coroutine, so 'await EasyStore.sync()' works correctly in both cases.
	var _done := false
	sync_completed.connect(func(_r: Dictionary) -> void: _done = true, CONNECT_ONE_SHOT)
	_run_sync(_resolve_slot(slot))
	if not _done:
		await sync_completed


func _run_sync(s: int) -> void:
	# ── Single-backend: load to populate cache, nothing to compare ───────────────
	if _backends.size() < 2:
		if _backends.is_empty():
			sync_completed.emit({})
			return
		_logger.info("Single backend — loading slot %d to populate cache." % s, "Sync")
		_load_from_backend(_backends[0], s, func(sf: SaveFile) -> void:
			if sf: _cache.populate_from_save_file(sf)
			sync_completed.emit({})
		)
		return

	# ── Two-backend sync (LOCAL + STEAM_CLOUD) ────────────────────────────────────
	_logger.info("Starting sync for slot %d — comparing timestamps across %d backends." % [s, _backends.size()], "Sync")

	var local_b = _get_backend(StoreEnums.BackendType.LOCAL)
	var cloud_b = _get_backend(StoreEnums.BackendType.STEAM_CLOUD)

	if local_b == null or cloud_b == null:
		sync_completed.emit({})
		return

	# Load actual data from both backends to get real timestamps before comparing.
	# ALL variables needed by the callbacks are stored in _sync_state to avoid
	# GDScript lambda capture issues: in Godot 4, closures that fire after their
	# enclosing function returns may not reliably capture local variables — using
	# a Dictionary as a shared context is the safest pattern.
	# _on_backend_load_completed is temporarily bypassed during sync reads to prevent
	# it from overwriting the cache or emitting load_completed spuriously.
	var _sync_state := { "local_sf": null, "local_b": local_b, "cloud_b": cloud_b, "slot": s }

	_load_raw_from_backend(local_b, s, func(local_sf: SaveFile) -> void:
		_sync_state["local_sf"] = local_sf

		# Use _sync_state for cloud_b and slot — do NOT capture them directly.
		# Direct capture of outer-function locals in async callbacks is unreliable
		# in GDScript 4 once the enclosing function (_run_sync) has already returned.
		_load_raw_from_backend(_sync_state["cloud_b"] as StorageBackend, _sync_state["slot"], func(cloud_sf: SaveFile) -> void:
			var lsf: SaveFile        = _sync_state["local_sf"]
			var lb: StorageBackend   = _sync_state["local_b"]
			var cb: StorageBackend   = _sync_state["cloud_b"]
			var sl: int              = _sync_state["slot"]

			var local_meta: SaveMetadata = lsf.metadata if lsf else null
			var cloud_meta: SaveMetadata = cloud_sf.metadata if cloud_sf else null
			var local_data: Dictionary   = lsf.sections if lsf else {}
			var cloud_data: Dictionary   = cloud_sf.sections if cloud_sf else {}

			var winner: int = _syncer.resolve_conflict(sl, local_meta, cloud_meta, local_data, cloud_data)
			var result      = _syncer.build_result(_backends, { winner: true })

			if winner == StoreEnums.BackendType.LOCAL:
				if lsf:
					_cache.populate_from_save_file(lsf)
					cb.backend_save(sl, lsf)
					_logger.info("Local save is newer — pushing to cloud. (slot=%d)" % sl, "Sync")
				sync_completed.emit(result)

			elif winner == StoreEnums.BackendType.STEAM_CLOUD:
				if cloud_sf:
					_cache.populate_from_save_file(cloud_sf)
					lb.backend_save(sl, cloud_sf)
					_logger.info("Cloud save is newer — pulling to local. (slot=%d)" % sl, "Sync")
				else:
					# Steam has no data (first launch / new account) → use local
					if lsf: _cache.populate_from_save_file(lsf)
				sync_completed.emit(result)

			else:
				# MANUAL — conflicts already emitted by SyncManager
				sync_completed.emit(result)
		)
	)

# ─── Auto-save ────────────────────────────────────────────────────────────────

func enable_autosave(interval_seconds: float = 60.0) -> void:
	_autosave.enable(interval_seconds)


func disable_autosave() -> void:
	_autosave.disable()

# ─── Migrations ───────────────────────────────────────────────────────────────

func register_migration(from_version: int, to_version: int, fn: Callable) -> void:
	_migrator.register_migration(from_version, to_version, fn)


func set_current_version(version: int) -> void:
	_migrator.set_current_version(version)

# ─── Debug ────────────────────────────────────────────────────────────────────

func get_logs(limit: int = 0) -> Array[Dictionary]:
	return _logger.get_logs(limit)


func get_debug_info() -> Dictionary:
	return _debugger.get_debug_info()


func debug_mode(enabled: bool) -> void:
	_logger.set_log_level(StoreEnums.LogLevel.DEBUG if enabled else StoreEnums.LogLevel.NONE)


## Set log verbosity directly. More granular than debug_mode().
## Example: EasyStore.set_log_level(StoreEnums.LogLevel.DEBUG)
func set_log_level(level: int) -> void:
	_logger.set_log_level(level)

# ─── Private helpers ──────────────────────────────────────────────────────────

func _resolve_slot(slot: int) -> int:
	return slot if slot >= 0 else _slots.get_slot()


func _get_backend(type: StoreEnums.BackendType) -> StorageBackend:
	for b in _backends:
		if b.get_backend_type() == type:
			return b
	return null


func _create_backend(type: StoreEnums.BackendType) -> Node:
	match type:
		StoreEnums.BackendType.LOCAL:
			var b = LocalBackend.new()
			b.setup(_worker)
			return b
		StoreEnums.BackendType.STEAM_CLOUD:
			var b: StorageBackend = load("res://addons/easystore/backends/steam/steam_backend.gd").new()
			b.setup()
			return b
	return null


func _resolve_default_config(type: StoreEnums.BackendType) -> Resource:
	if _config == null:
		return null
	match type:
		StoreEnums.BackendType.LOCAL:  return _config.local
		StoreEnums.BackendType.STEAM_CLOUD:  return _config.steam_cloud
	return null


func _wire_backend(backend: StorageBackend) -> void:
	backend.backend_save_completed.connect(_on_backend_save_completed)
	backend.backend_load_completed.connect(_on_backend_load_completed)
	backend.backend_delete_completed.connect(_on_backend_delete_completed)
	backend.backend_error.connect(_on_backend_error)
	backend.backend_list_completed.connect(_on_backend_list_completed)


func _flush_to_backends(slot: int) -> void:
	var meta: SaveMetadata = _slots.get_metadata(slot)
	if meta == null:
		meta = SaveMetadata.new()
	meta.slot      = slot
	meta.timestamp = int(Time.get_unix_time_from_system())
	meta.is_empty  = false

	var sf: SaveFile = _cache.build_save_file(slot, meta)
	if sf == null:
		# Nothing dirty — still emit success
		save_completed.emit(slot, true)
		return

	sf.version = _migrator.get_current_version()
	_slots.register_metadata(slot, meta)

	if _backends.is_empty():
		save_completed.emit(slot, true)
		return

	# Register a completion counter so save_completed fires exactly ONCE,
	# even when multiple backends are active simultaneously (BUG-02 fix).
	_pending_saves[slot] = { "remaining": _backends.size(), "all_success": true }
	save_started.emit(slot)
	_syncer.broadcast_save(_backends, slot, sf)


func _load_slot_from_backend(slot: int) -> void:
	# Prefer local backend, fall back to first available
	var backend = _get_backend(StoreEnums.BackendType.LOCAL)
	if backend == null and not _backends.is_empty():
		backend = _backends[0]
	if backend == null:
		load_completed.emit(slot, {}, false)
		return
	load_started.emit(slot)
	backend.backend_load(slot)


func _load_from_backend(backend: StorageBackend, slot: int, callback: Callable) -> void:
	# Use a ref-array so the lambda can disconnect itself — CONNECT_ONE_SHOT is
	# NOT used here because it fires on the FIRST emission regardless of slot,
	# which would silently swallow the callback if a different slot responds first
	# (CNM-04 fix). The lambda stays connected until the correct slot fires.
	var ref := [null]
	ref[0] = func(s: int, sf: SaveFile, ok: bool, _code: int) -> void:
		if s != slot:
			return  # wrong slot — keep the connection alive and wait
		backend.backend_load_completed.disconnect(ref[0])
		callback.call(sf if ok else null)
	backend.backend_load_completed.connect(ref[0])
	backend.backend_load(slot)


## Like _load_from_backend but bypasses _on_backend_load_completed.
## Used internally by sync() so the persistent handler doesn't overwrite the
## cache or emit load_completed before the winner comparison is done.
func _load_raw_from_backend(backend: StorageBackend, slot: int, callback: Callable) -> void:
	# Guard: only disconnect if the connection actually exists.
	if backend.backend_load_completed.is_connected(_on_backend_load_completed):
		backend.backend_load_completed.disconnect(_on_backend_load_completed)
	# Same ref-array pattern as _load_from_backend: stays connected until the
	# correct slot fires, then self-disconnects and restores the normal handler.
	var ref := [null]
	ref[0] = func(s: int, sf: SaveFile, ok: bool, _code: int) -> void:
		if s != slot:
			return  # wrong slot — wait for our slot
		backend.backend_load_completed.disconnect(ref[0])
		if not backend.backend_load_completed.is_connected(_on_backend_load_completed):
			backend.backend_load_completed.connect(_on_backend_load_completed)
		callback.call(sf if ok else null)
	backend.backend_load_completed.connect(ref[0])
	backend.backend_load(slot)


func _on_autosave_tick(slot: int) -> void:
	autosave_triggered.emit(slot)
	save_all(slot)


func _on_backend_save_completed(slot: int, success: bool, error_code: int) -> void:
	if not success:
		_logger.error("Failed to write slot %d to a backend. (error_code=%d)" % [slot, error_code], "Save")

	# Saves triggered by sync() or other internal paths have no pending counter.
	if not _pending_saves.has(slot):
		return

	if not success:
		_pending_saves[slot]["all_success"] = false

	_pending_saves[slot]["remaining"] -= 1
	if _pending_saves[slot]["remaining"] > 0:
		return  # still waiting for other backends

	# All backends for this slot have reported back — emit exactly once.
	var all_ok: bool = _pending_saves[slot]["all_success"]
	_pending_saves.erase(slot)
	if all_ok:
		_cache.mark_clean(slot)
		_logger.info("Slot %d saved successfully." % slot, "Save")
	save_completed.emit(slot, all_ok)


func _on_backend_load_completed(slot: int, save_file: SaveFile, success: bool, _code: int) -> void:
	if not success or save_file == null:
		load_completed.emit(slot, {}, false)
		return

	# Run migrations if needed
	_migrator.migrate(save_file)

	_cache.populate_from_save_file(save_file)
	if save_file.metadata:
		_slots.register_metadata(slot, save_file.metadata)

	_logger.info("Slot %d loaded successfully. (save_version=%d)" % [slot, save_file.version], "Load")
	load_completed.emit(slot, save_file.sections.duplicate(true), true)


func _on_backend_delete_completed(slot: int, success: bool) -> void:
	if success:
		_logger.info("Slot %d deleted from backend." % slot, "Delete")
	else:
		_logger.warn("Failed to delete slot %d from backend." % slot, "Delete")


func _on_backend_error(code: int, message: String) -> void:
	_logger.error(message, "Backend")
	error_occurred.emit(code, message)


func _on_backend_list_completed(metadata_list: Array) -> void:
	_slots.populate_index(metadata_list)


func _emit_error(code: StoreEnums.ErrorCode, message: String) -> void:
	_logger.error(message, "Core")
	error_occurred.emit(code, message)


func _unavailable_reason(type: StoreEnums.BackendType) -> String:
	match type:
		StoreEnums.BackendType.STEAM_CLOUD:
			if not Engine.has_singleton("Steam"):
				return "GodotSteam is not installed or the singleton is not registered."
			return "Steam is not running. Make sure the Steam client is open before launching the game."
	return "Backend reported itself as unavailable."


func _ready_message(type: StoreEnums.BackendType) -> String:
	match type:
		StoreEnums.BackendType.LOCAL:
			return "Local backend ready. Saves will be stored in user://saves/"
		StoreEnums.BackendType.STEAM_CLOUD:
			return "Steam Remote Storage backend ready. Cloud saves are active."
	return "%s backend ready." % StoreEnums.BackendType.keys()[type]
