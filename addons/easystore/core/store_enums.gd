# store_enums.gd
# Enums and error codes shared across the entire EasyStore addon.
class_name StoreEnums

enum BackendType {
	LOCAL       = 0,
	STEAM_CLOUD = 1,
	# Reserved for future versions:
	GOOGLE_PLAY = 2,
	CUSTOM_HTTP = 3,
}

## How conflicts are resolved when syncing two backends with different data.
enum ConflictStrategy {
	NEWEST_WINS = 0,  ## Default: the backend with the most recent timestamp wins.
	CLOUD_WINS  = 1,  ## Cloud data always overwrites local.
	LOCAL_WINS  = 2,  ## Local data always overwrites cloud.
	MANUAL      = 3,  ## Emits sync_conflict signal for the game to handle.
}

## Serialization format used by LocalBackend.
enum SerializationFormat {
	JSON   = 0,  ## Human-readable, good for debugging.
	BINARY = 1,  ## var_to_bytes — more compact.
}

## Log verbosity. Pass to EasyStoreConfig.log_level or EasyStore.set_log_level().
enum LogLevel {
	NONE  = 0,  ## Silent — no output at all.
	ERROR = 1,  ## Only errors.
	WARN  = 2,  ## Errors and warnings.
	INFO  = 3,  ## Normal operational messages (recommended for development).
	DEBUG = 4,  ## Detailed internal flow — backend calls, cache hits, etc.
	TRACE = 5,  ## Everything, including per-operation data payloads.
}

## Error codes used in error_occurred and backend signals.
enum ErrorCode {
	OK                = 0,
	FILE_NOT_FOUND    = 1,
	PARSE_ERROR       = 2,
	CLOUD_UNAVAILABLE = 3,
	SLOT_EMPTY        = 4,
	MIGRATION_FAILED  = 5,
	BACKEND_NOT_READY = 6,
	PERMISSION_DENIED = 7,
	UNKNOWN           = 99,
}
