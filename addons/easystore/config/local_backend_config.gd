# local_backend_config.gd
# Configuration for the LocalBackend.
class_name LocalBackendConfig
extends Resource

## Base directory for all save files. Relative to user://.
## Note: user:// already contains your project name (set in Project Settings).
@export var save_directory: String = "saves"

## If true, saves go into user://saves/{ProjectName}/ instead of user://saves/.
## Useful when shipping multiple games that share the same OS user data root.
@export var use_project_subfolder: bool = false

## Serialization format. JSON is human-readable; BINARY is more compact.
@export var format: StoreEnums.SerializationFormat = StoreEnums.SerializationFormat.JSON

## Enable file encryption using FileAccess.open_encrypted_with_pass().
## If true, encryption_key must be set.
@export var encrypt: bool = false

## Encryption passphrase. Keep this out of version control in production.
@export var encryption_key: String = ""

## Maximum number of backup copies kept per slot (0 = disabled).
@export var max_backups: int = 1
