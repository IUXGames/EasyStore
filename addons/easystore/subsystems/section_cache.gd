# section_cache.gd
# In-memory write-through cache for save sections.
# Writes hit the cache immediately (synchronous for the game), then the
# backend flushes to disk/cloud asynchronously.
#
# Structure:  { slot (int) -> { section_name (String) -> data (Dictionary) } }
# Dirty set:  { slot (int) -> Set<String> }  — sections awaiting flush
extends Node

var _data:  Dictionary = {}   # slot -> { section -> data }
var _dirty: Dictionary = {}   # slot -> Array[String]  (dirty section names)


## Write a section to the cache and mark it dirty.
func write(slot: int, section: String, data: Dictionary) -> void:
	if not _data.has(slot):
		_data[slot] = {}
		_dirty[slot] = []
	_data[slot][section] = data.duplicate(true)
	if section not in _dirty[slot]:
		_dirty[slot].append(section)


## Read a section from the cache. Returns {} if not cached.
func read(slot: int, section: String) -> Dictionary:
	return _data.get(slot, {}).get(section, {})


## Returns true if the section is in the cache (whether dirty or clean).
func has(slot: int, section: String) -> bool:
	return _data.get(slot, {}).has(section)


## Populate the cache from a loaded SaveFile (marks sections as clean).
func populate_from_save_file(save_file: SaveFile) -> void:
	var slot := save_file.slot
	_data[slot]  = save_file.sections.duplicate(true)
	_dirty[slot] = []


## Build a SaveFile from all dirty sections of the given slot.
## Returns null if there are no dirty sections.
func build_save_file(slot: int, metadata: SaveMetadata) -> SaveFile:
	if _dirty.get(slot, []).is_empty():
		return null
	var sf       := SaveFile.new()
	sf.slot      = slot
	sf.metadata  = metadata
	sf.sections  = _data.get(slot, {}).duplicate(true)
	return sf


## Build a SaveFile with ALL sections (not just dirty), used for full sync.
func build_full_save_file(slot: int, metadata: SaveMetadata) -> SaveFile:
	var sf       := SaveFile.new()
	sf.slot      = slot
	sf.metadata  = metadata
	sf.sections  = _data.get(slot, {}).duplicate(true)
	return sf


## Mark all sections for a slot as clean (after a successful flush).
func mark_clean(slot: int) -> void:
	_dirty[slot] = []


## Returns true if any section in the slot is dirty.
func is_dirty(slot: int) -> bool:
	return not _dirty.get(slot, []).is_empty()


## Remove all cached data for a slot.
func evict(slot: int) -> void:
	_data.erase(slot)
	_dirty.erase(slot)


## Remove all cached data.
func clear_all() -> void:
	_data.clear()
	_dirty.clear()
