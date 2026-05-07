# save_file.gd
# Main save data container. Holds all sections (player, world, settings, etc.)
# and the metadata sidecar for this slot.
class_name SaveFile
extends Resource

## Schema version. Compared against EasyStore.current_version for migrations.
@export var version: int = 1
## Slot index this file belongs to.
@export var slot: int = 0
## Lightweight metadata (timestamp, playtime, custom preview data).
@export var metadata: SaveMetadata
## Data sections. Keys are section names (e.g. "player", "world").
## Values are Dictionaries with the game's save data.
@export var sections: Dictionary = {}


func _init() -> void:
	metadata = SaveMetadata.new()


## Returns the data Dictionary for a section, or {} if it doesn't exist.
func get_section(section_name: String) -> Dictionary:
	return sections.get(section_name, {})


## Writes (or overwrites) a section.
func set_section(section_name: String, data: Dictionary) -> void:
	sections[section_name] = data.duplicate(true)


## Returns true if the given section exists and is not empty.
func has_section(section_name: String) -> bool:
	return sections.has(section_name) and not sections[section_name].is_empty()


## Serializes the entire SaveFile to a plain Dictionary (for JSON/binary I/O).
func to_dict() -> Dictionary:
	return {
		"version":  version,
		"slot":     slot,
		"metadata": metadata.to_dict() if metadata else {},
		"sections": sections.duplicate(true),
	}


## Populates this SaveFile from a plain Dictionary (after JSON/binary read).
func from_dict(d: Dictionary) -> void:
	version  = d.get("version", 1)
	slot     = d.get("slot",    0)
	sections = d.get("sections", {}).duplicate(true)
	var meta_dict: Dictionary = d.get("metadata", {})
	if not meta_dict.is_empty():
		metadata = SaveMetadata.new()
		metadata.from_dict(meta_dict)
	else:
		metadata = SaveMetadata.new()
