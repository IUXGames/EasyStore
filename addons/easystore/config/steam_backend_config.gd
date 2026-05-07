# steam_backend_config.gd
# Configuration for the SteamBackend (GodotSteam Remote Storage).
class_name SteamCloudBackendConfig
extends Resource

## Prefix for Steam Remote Storage filenames.
## Files are stored as "{file_prefix}slot_{N}.sav" and "{file_prefix}meta_{N}.json".
@export var file_prefix: String = "easystore_"

## If true, EasyStore will call sync() automatically when Steam becomes available
## after initialize() has already been called.
@export var auto_sync_on_connect: bool = true

## Maximum quota to use on Steam Remote Storage, in bytes (0 = no limit check).
## Steam's default quota is 100 MB per game.
@export var quota_warning_bytes: int = 0
