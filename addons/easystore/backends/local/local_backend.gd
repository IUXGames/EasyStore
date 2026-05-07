# local_backend.gd
# Saves data to the local filesystem under user://saves/.
# All disk I/O is dispatched to AsyncWorker to avoid blocking the main thread.
class_name LocalBackend
extends StorageBackend

const SAVE_EXT := ".sav"
const META_EXT := ".meta.json"

var _save_dir:  String = "user://saves"
var _format:    StoreEnums.SerializationFormat = StoreEnums.SerializationFormat.JSON
var _encrypt:   bool   = false
var _enc_key:   String = ""
var _max_back:  int    = 1
var _worker:    Node   # AsyncWorker, injected


func setup(worker: Node) -> void:
	_worker       = worker
	_backend_type = StoreEnums.BackendType.LOCAL


# ─── StorageBackend implementation ────────────────────────────────────────────

func _backend_initialize(config: Resource) -> Error:
	if config and config is LocalBackendConfig:
		var c       := config as LocalBackendConfig
		var base    := c.save_directory
		if c.use_project_subfolder:
			var proj := ProjectSettings.get_setting("application/config/name", "game") as String
			base = base.path_join(proj.validate_filename())
		_save_dir = "user://" + base
		_format   = c.format
		_encrypt  = c.encrypt
		_enc_key  = c.encryption_key
		_max_back = c.max_backups

	var err := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_save_dir)
	)
	return err if err != OK else OK


func _backend_shutdown() -> void:
	pass   # nothing to clean up


func _backend_save(slot: int, save_file: SaveFile) -> void:
	var path      := _slot_path(slot)
	var meta_path := _meta_path(slot)
	var format    := _format
	var encrypt   := _encrypt
	var enc_key   := _enc_key
	var max_back  := _max_back
	var save_dir  := _save_dir

	_worker.dispatch(
		func() -> Variant:
			# ── Serialize ───────────────────────────────────────────────────────────
			var data_dict := save_file.to_dict()
			var data_bytes: PackedByteArray
			if format == StoreEnums.SerializationFormat.BINARY:
				data_bytes = var_to_bytes(data_dict)
			else:
				data_bytes = JSON.stringify(data_dict, "\t").to_utf8_buffer()

			# ── Atomic write: write to .tmp first ───────────────────────────────────
			# This guarantees the existing .sav is never touched if the write fails.
			var tmp_path  := path + ".tmp"
			var write_err := _write_file(tmp_path, data_bytes, encrypt, enc_key)
			if write_err != OK:
				DirAccess.remove_absolute(tmp_path)
				return write_err

			# ── Rotate backups and promote .tmp → .sav ──────────────────────────────
			# Naming convention: .bak = backup 1, .bak2 = backup 2, etc.
			var dir := DirAccess.open(save_dir)
			if dir != null:
				if max_back > 0:
					# Remove oldest backup slot to make room
					var oldest: String = path.get_file() + (".bak" if max_back == 1 else ".bak%d" % max_back)
					if dir.file_exists(oldest):
						dir.remove(oldest)
					# Shift: .bak(n-1) → .bak(n) for n = max_back down to 2
					for i in range(max_back - 1, 0, -1):
						var from_name: String = path.get_file() + (".bak" if i == 1 else ".bak%d" % i)
						var to_name:   String = path.get_file() + ".bak%d" % (i + 1)
						if dir.file_exists(from_name):
							dir.rename(from_name, to_name)
					# Current .sav → .bak
					if dir.file_exists(path.get_file()):
						dir.rename(path.get_file(), path.get_file() + ".bak")
				elif dir.file_exists(path.get_file()):
					# max_back == 0: no backups — just remove the old file
					dir.remove(path.get_file())
				# Promote .tmp → .sav (rename is near-atomic)
				dir.rename(tmp_path.get_file(), path.get_file())
			else:
				# Fallback: DirAccess unavailable — use copy+delete (less safe)
				if max_back > 0 and FileAccess.file_exists(path):
					DirAccess.copy_absolute(path, path + ".bak")
				DirAccess.copy_absolute(tmp_path, path)
				DirAccess.remove_absolute(tmp_path)

			# ── Metadata sidecar (always JSON — lightweight, human-readable) ────────
			var meta_str := JSON.stringify(save_file.metadata.to_dict())
			_write_file(meta_path, meta_str.to_utf8_buffer(), false, "")

			return OK,

		func(result: Variant) -> void:
			var success: bool = (result == OK)
			backend_save_completed.emit(slot, success, result as int)
			if not success:
				backend_error.emit(result as int, "LocalBackend save failed for slot %d" % slot)
	)


func _backend_load(slot: int) -> void:
	var path     := _slot_path(slot)
	var encrypt  := _encrypt
	var enc_key  := _enc_key
	var format   := _format
	var max_back := _max_back

	_worker.dispatch(
		func() -> Variant:
			if not FileAccess.file_exists(path):
				return null   # no data

			# Try primary save file first.
			var raw := _read_file(path, encrypt, enc_key)
			if not raw.is_empty():
				if format == StoreEnums.SerializationFormat.BINARY:
					var v = bytes_to_var(raw)
					if v is Dictionary:
						var sf := SaveFile.new()
						sf.from_dict(v)
						return sf
				else:
					var json := JSON.new()
					if json.parse(raw.get_string_from_utf8()) == OK:
						var sf := SaveFile.new()
						sf.from_dict(json.data)
						return sf

			# Primary missing or corrupt — try backups in order (.bak, .bak2, ...).
			for i in range(1, max_back + 1):
				var bak_path := path + (".bak" if i == 1 else ".bak%d" % i)
				if not FileAccess.file_exists(bak_path):
					continue
				var bak_raw := _read_file(bak_path, encrypt, enc_key)
				if bak_raw.is_empty():
					continue
				if format == StoreEnums.SerializationFormat.BINARY:
					var v = bytes_to_var(bak_raw)
					if v is Dictionary:
						var sf := SaveFile.new()
						sf.from_dict(v)
						return sf
				else:
					var bak_json := JSON.new()
					if bak_json.parse(bak_raw.get_string_from_utf8()) == OK:
						var sf := SaveFile.new()
						sf.from_dict(bak_json.data)
						return sf

			return null,

		func(result: Variant) -> void:
			if result == null:
				backend_load_completed.emit(slot, null, false, StoreEnums.ErrorCode.FILE_NOT_FOUND)
			else:
				backend_load_completed.emit(slot, result, true, StoreEnums.ErrorCode.OK)
	)


func _backend_delete(slot: int) -> void:
	var path      := _slot_path(slot)
	var meta_path := _meta_path(slot)

	_worker.dispatch(
		func() -> Variant:
			var ok := true
			if FileAccess.file_exists(path):
				ok = (DirAccess.remove_absolute(path) == OK) and ok
			if FileAccess.file_exists(meta_path):
				ok = (DirAccess.remove_absolute(meta_path) == OK) and ok
			return ok,

		func(result: Variant) -> void:
			backend_delete_completed.emit(slot, result as bool)
	)


func _backend_list_slots() -> void:
	var save_dir := _save_dir

	_worker.dispatch(
		func() -> Variant:
			var list: Array[SaveMetadata] = []
			var dir  := DirAccess.open(save_dir)
			if dir == null:
				return list

			dir.list_dir_begin()
			var fname := dir.get_next()
			while fname != "":
				if fname.ends_with(META_EXT):
					var meta_path := save_dir.path_join(fname)
					var fa        := FileAccess.open(meta_path, FileAccess.READ)
					if fa:
						var json := JSON.new()
						if json.parse(fa.get_as_text()) == OK:
							var meta := SaveMetadata.new()
							meta.from_dict(json.data)
							list.append(meta)
				fname = dir.get_next()
			dir.list_dir_end()
			return list,

		func(result: Variant) -> void:
			backend_list_completed.emit(result)
	)


func _backend_slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


func _backend_get_capabilities() -> Dictionary:
	return {
		"encryption":  _encrypt,
		"compression": false,
		"cloud_sync":  false,
	}


# ─── Helpers ──────────────────────────────────────────────────────────────────

func _slot_path(slot: int) -> String:
	return _save_dir.path_join("slot_%d%s" % [slot, SAVE_EXT])


func _meta_path(slot: int) -> String:
	return _save_dir.path_join("slot_%d%s" % [slot, META_EXT])


func _write_file(path: String, data: PackedByteArray, encrypt: bool, key: String) -> int:
	var fa: FileAccess
	if encrypt and not key.is_empty():
		fa = FileAccess.open_encrypted_with_pass(path, FileAccess.WRITE, key)
	else:
		fa = FileAccess.open(path, FileAccess.WRITE)

	if fa == null:
		return FileAccess.get_open_error()
	fa.store_buffer(data)
	return OK


func _read_file(path: String, encrypt: bool, key: String) -> PackedByteArray:
	var fa: FileAccess
	if encrypt and not key.is_empty():
		fa = FileAccess.open_encrypted_with_pass(path, FileAccess.READ, key)
	else:
		fa = FileAccess.open(path, FileAccess.READ)

	if fa == null:
		return PackedByteArray()
	return fa.get_buffer(fa.get_length())
