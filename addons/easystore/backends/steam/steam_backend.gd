# steam_backend.gd
# Saves data to Steam Remote Storage using GodotSteam.
# Steam is resolved at runtime via Engine.get_singleton("Steam") so this file
# parses without errors even if GodotSteam is not installed.
extends StorageBackend

const SAVE_EXT := ".sav"
const META_EXT := ".meta.json"

var _prefix:   String = "easystore_"
var _steam                        # Steam singleton (untyped — resolved at runtime)


func setup() -> void:
	_backend_type = StoreEnums.BackendType.STEAM_CLOUD


# ─── StorageBackend implementation ────────────────────────────────────────────

func _backend_initialize(config: Resource) -> Error:
	# ── Check 1: Is GodotSteam installed in the project? ──────────────────────
	if not Engine.has_singleton("Steam"):
		return ERR_UNAVAILABLE

	_steam = Engine.get_singleton("Steam")

	# ── Check 2: Is Steam running on this machine? ─────────────────────────────
	if not _steam.isSteamRunning():
		return ERR_UNAVAILABLE

	# ── Check 3: Apply config ─────────────────────────────────────────────────
	if config and config is SteamCloudBackendConfig:
		_prefix = (config as SteamCloudBackendConfig).file_prefix

	return OK


func _backend_shutdown() -> void:
	_steam = null


func _backend_save(slot: int, save_file: SaveFile) -> void:
	if _steam == null:
		backend_save_completed.emit(slot, false, StoreEnums.ErrorCode.CLOUD_UNAVAILABLE)
		return

	var fname      := _slot_filename(slot)
	var meta_fname := _meta_filename(slot)

	var data_str := JSON.stringify(save_file.to_dict())
	var meta_str := JSON.stringify(save_file.metadata.to_dict())

	var ok_data: bool = _steam.fileWrite(fname, data_str.to_utf8_buffer())
	var ok_meta: bool = _steam.fileWrite(meta_fname, meta_str.to_utf8_buffer())

	var success: bool = ok_data and ok_meta
	var code: int     = StoreEnums.ErrorCode.OK if success else StoreEnums.ErrorCode.CLOUD_UNAVAILABLE
	backend_save_completed.emit(slot, success, code)


func _backend_load(slot: int) -> void:
	if _steam == null:
		backend_load_completed.emit(slot, null, false, StoreEnums.ErrorCode.CLOUD_UNAVAILABLE)
		return

	var fname := _slot_filename(slot)

	if not _steam.fileExists(fname):
		backend_load_completed.emit(slot, null, false, StoreEnums.ErrorCode.FILE_NOT_FOUND)
		return

	var file_size: int = _steam.getFileSize(fname)
	if file_size <= 0:
		backend_load_completed.emit(slot, null, false, StoreEnums.ErrorCode.FILE_NOT_FOUND)
		return

	var raw: PackedByteArray = _steam_file_read(fname, file_size)
	if raw.is_empty():
		backend_load_completed.emit(slot, null, false, StoreEnums.ErrorCode.FILE_NOT_FOUND)
		return

	var json := JSON.new()
	if json.parse(raw.get_string_from_utf8()) != OK:
		backend_load_completed.emit(slot, null, false, StoreEnums.ErrorCode.PARSE_ERROR)
		return

	var sf := SaveFile.new()
	sf.from_dict(json.data)
	backend_load_completed.emit(slot, sf, true, StoreEnums.ErrorCode.OK)


func _backend_delete(slot: int) -> void:
	if _steam == null:
		backend_delete_completed.emit(slot, false)
		return

	var ok_data: bool = _steam.fileDelete(_slot_filename(slot))
	var ok_meta: bool = _steam.fileDelete(_meta_filename(slot))
	backend_delete_completed.emit(slot, ok_data and ok_meta)


func _backend_list_slots() -> void:
	if _steam == null:
		backend_list_completed.emit([])
		return

	var list: Array[SaveMetadata] = []
	var count: int = _steam.getFileCount()

	for i in range(count):
		var entry       = _steam.getFileNameAndSize(i)
		var fname: String = entry[0]
		var fsize: int    = entry[1] if entry.size() > 1 else _steam.getFileSize(fname)
		if fname.begins_with(_prefix) and fname.ends_with(META_EXT):
			if fsize <= 0:
				continue
			var raw: PackedByteArray = _steam_file_read(fname, fsize)
			if raw.is_empty():
				continue
			var json := JSON.new()
			if json.parse(raw.get_string_from_utf8()) != OK:
				continue
			var meta := SaveMetadata.new()
			meta.from_dict(json.data)
			list.append(meta)

	backend_list_completed.emit(list)


func _backend_slot_exists(slot: int) -> bool:
	if _steam == null:
		return false
	return _steam.fileExists(_slot_filename(slot))


func _backend_get_capabilities() -> Dictionary:
	return {
		"encryption":  false,
		"compression": false,
		"cloud_sync":  true,
	}


# ─── Helpers ──────────────────────────────────────────────────────────────────

func _slot_filename(slot: int) -> String:
	return "%sslot_%d%s" % [_prefix, slot, SAVE_EXT]


func _meta_filename(slot: int) -> String:
	return "%smeta_%d%s" % [_prefix, slot, META_EXT]


## Wrapper for Steam.fileRead() that handles different GodotSteam return types:
## - GodotSteam 4.12.x  → Dictionary { "ret": int, "buf": PackedByteArray }
## - Some 4.x versions  → Dictionary { "ret_code": int, "buffer": PackedByteArray }
## - Older versions     → PackedByteArray directly
func _steam_file_read(fname: String, size: int) -> PackedByteArray:
	var result = _steam.fileRead(fname, size)
	if result is Dictionary:
		# Try both known key names used across GodotSteam versions.
		# "buf" is used in 4.12.x; "buffer" in some earlier 4.x builds.
		for key in ["buf", "buffer"]:
			if result.has(key) and result[key] is PackedByteArray:
				return result[key]
		return PackedByteArray()
	if result is PackedByteArray:
		return result
	return PackedByteArray()
