# easystore_config.gd
# Root configuration resource for EasyStore.
# Pass an instance of this to EasyStore.initialize() to customize behaviour.
# All fields have sensible defaults — no configuration is required for basic use.
class_name EasyStoreConfig
extends Resource

## Default active slot index when none is specified in API calls.
@export var default_slot: int = 0

## Strategy used when syncing two backends that have diverged.
@export var conflict_strategy: StoreEnums.ConflictStrategy = StoreEnums.ConflictStrategy.NEWEST_WINS

## Schema version of the current game save format.
## If a loaded save has a lower version, MigrationManager will upgrade it.
@export var current_save_version: int = 1

## Log verbosity level. NONE = silent, INFO = recommended for dev, DEBUG = verbose.
## See StoreEnums.LogLevel for all values.
@export var log_level: int = StoreEnums.LogLevel.INFO

## Configuration for the Local backend (optional — uses defaults if null).
@export var local: LocalBackendConfig

## Configuration for the Steam Cloud backend (optional — uses defaults if null).
@export var steam_cloud: SteamCloudBackendConfig


func _init() -> void:
	local       = LocalBackendConfig.new()
	steam_cloud = SteamCloudBackendConfig.new()
