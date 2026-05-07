# save_metadata.gd
# Lightweight metadata stored alongside every save slot.
# Written as a separate sidecar file so list_slots() is fast
# without deserializing the full save payload.
class_name SaveMetadata
extends Resource

## Save slot index.
@export var slot: int = 0
## Unix timestamp of the last write (seconds since epoch).
@export var timestamp: int = 0
## Accumulated playtime in seconds.
@export var playtime_seconds: float = 0.0
## Godot project version at save time (ProjectSettings APPLICATION_VERSION).
@export var game_version: String = ""
## EasyStore save schema version (used by MigrationManager).
@export var save_version: int = 1
## Optional path to a screenshot thumbnail for UI display.
@export var thumbnail_path: String = ""
## Free-form data the game can use for slot previews (level name, character, etc.).
@export var custom: Dictionary = {}
## True if this slot has never been written to.
@export var is_empty: bool = true


func to_dict() -> Dictionary:
	return {
		"slot":             slot,
		"timestamp":        timestamp,
		"playtime_seconds": playtime_seconds,
		"game_version":     game_version,
		"save_version":     save_version,
		"thumbnail_path":   thumbnail_path,
		"custom":           custom,
		"is_empty":         is_empty,
	}


func from_dict(d: Dictionary) -> void:
	slot             = d.get("slot",             0)
	timestamp        = d.get("timestamp",        0)
	playtime_seconds = d.get("playtime_seconds", 0.0)
	game_version     = d.get("game_version",     "")
	save_version     = d.get("save_version",     1)
	thumbnail_path   = d.get("thumbnail_path",   "")
	custom           = d.get("custom",           {})
	is_empty         = d.get("is_empty",         true)
