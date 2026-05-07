# slot_manager.gd
# Tracks the active slot and the metadata index for all known slots.
# The metadata index is populated lazily when list_slots() is called.
extends Node

var _current_slot: int = 0
var _metadata_index: Dictionary = {}   # slot (int) -> SaveMetadata
var _events: Node   # StoreEvents reference, injected by EasyStore


func setup(events: Node) -> void:
	_events = events


# ─── Slot selection ───────────────────────────────────────────────────────────

func set_slot(slot: int) -> void:
	_current_slot = slot
	_events.slot_changed.emit(slot)


func get_slot() -> int:
	return _current_slot


# ─── Metadata index ───────────────────────────────────────────────────────────

## Register or update metadata for a slot (called after every save).
func register_metadata(slot: int, metadata: SaveMetadata) -> void:
	_metadata_index[slot] = metadata


## Return metadata for a slot, or null if unknown.
func get_metadata(slot: int) -> SaveMetadata:
	return _metadata_index.get(slot, null)


## Replace the full index (called after list_slots() returns from a backend).
func populate_index(metadata_list: Array) -> void:
	for meta in metadata_list:
		if meta is SaveMetadata:
			_metadata_index[meta.slot] = meta


## Return all known SaveMetadata objects sorted by slot index.
func list_slots() -> Array[SaveMetadata]:
	var result: Array[SaveMetadata] = []
	var keys: Array = _metadata_index.keys()
	keys.sort()
	for k in keys:
		result.append(_metadata_index[k])
	return result


## Remove a slot from the index.
func remove_slot(slot: int) -> void:
	_metadata_index.erase(slot)
	_events.slot_deleted.emit(slot)


## Return true if the slot has registered metadata and is not marked empty.
func has_slot(slot: int) -> bool:
	var meta: SaveMetadata = _metadata_index.get(slot, null)
	return meta != null and not meta.is_empty
