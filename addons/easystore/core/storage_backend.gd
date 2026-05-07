# storage_backend.gd
# Abstract base class for all EasyStore backends (Local, Steam, etc.).
# Equivalent to NetworkBackend in LinkUx.
#
# To add a new backend:
#   1. Create backends/my_backend/my_backend.gd extending StorageBackend
#   2. Implement every _backend_* virtual method
#   3. Add a BackendType entry in store_enums.gd
#   4. Add a branch in EasyStore.add_backend()
class_name StorageBackend
extends Node

# ─── Signals (every backend MUST emit these) ──────────────────────────────────

## Emitted when a save operation finishes.
signal backend_save_completed(slot: int, success: bool, error_code: int)
## Emitted when a load operation finishes. save_file is null on failure.
signal backend_load_completed(slot: int, save_file: SaveFile, success: bool, error_code: int)
## Emitted when a slot delete operation finishes.
signal backend_delete_completed(slot: int, success: bool)
## Emitted when list_slots finishes. metadata_list is Array[SaveMetadata].
signal backend_list_completed(metadata_list: Array)
## Emitted on any backend-level error.
signal backend_error(code: int, message: String)

# ─── State ────────────────────────────────────────────────────────────────────

var _is_ready: bool = false
var _backend_type: StoreEnums.BackendType = StoreEnums.BackendType.LOCAL


func get_backend_type() -> StoreEnums.BackendType:
	return _backend_type


func is_ready() -> bool:
	return _is_ready


# ─── Public wrappers (called by EasyStore — do not override) ──────────────────

func initialize(config: Resource) -> Error:
	var result := _backend_initialize(config)
	if result == OK:
		_is_ready = true
	return result


func shutdown() -> void:
	_is_ready = false
	_backend_shutdown()


func backend_save(slot: int, save_file: SaveFile) -> void:
	if not _is_ready:
		backend_error.emit(StoreEnums.ErrorCode.BACKEND_NOT_READY, "Backend not initialized.")
		backend_save_completed.emit(slot, false, StoreEnums.ErrorCode.BACKEND_NOT_READY)
		return
	_backend_save(slot, save_file)


func backend_load(slot: int) -> void:
	if not _is_ready:
		backend_error.emit(StoreEnums.ErrorCode.BACKEND_NOT_READY, "Backend not initialized.")
		backend_load_completed.emit(slot, null, false, StoreEnums.ErrorCode.BACKEND_NOT_READY)
		return
	_backend_load(slot)


func backend_delete(slot: int) -> void:
	if not _is_ready:
		backend_error.emit(StoreEnums.ErrorCode.BACKEND_NOT_READY, "Backend not initialized.")
		backend_delete_completed.emit(slot, false)
		return
	_backend_delete(slot)


func backend_list_slots() -> void:
	if not _is_ready:
		backend_list_completed.emit([])
		return
	_backend_list_slots()


func backend_slot_exists(slot: int) -> bool:
	if not _is_ready:
		return false
	return _backend_slot_exists(slot)


# ─── Virtual methods (MUST be implemented by subclasses) ──────────────────────

## Initialize the backend with the given config Resource. Return OK or an Error.
func _backend_initialize(_config: Resource) -> Error:
	return OK


## Clean up any resources (close files, disconnect, etc.).
func _backend_shutdown() -> void:
	pass


## Persist save_file to slot. Must emit backend_save_completed when done.
func _backend_save(_slot: int, _save_file: SaveFile) -> void:
	push_error("StorageBackend._backend_save() not implemented.")


## Load data from slot. Must emit backend_load_completed when done.
func _backend_load(_slot: int) -> void:
	push_error("StorageBackend._backend_load() not implemented.")


## Delete slot data. Must emit backend_delete_completed when done.
func _backend_delete(_slot: int) -> void:
	push_error("StorageBackend._backend_delete() not implemented.")


## List all available slots. Must emit backend_list_completed when done.
func _backend_list_slots() -> void:
	push_error("StorageBackend._backend_list_slots() not implemented.")


## Return true if the given slot has data. Synchronous.
func _backend_slot_exists(_slot: int) -> bool:
	return false


## Return a Dictionary describing optional capabilities.
## Keys: "encryption", "compression", "cloud_sync", "quota_bytes"
func _backend_get_capabilities() -> Dictionary:
	return {}
