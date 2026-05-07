# easy_store_trigger.gd
# Optional drop-in node for scene-based auto-save.
# Add this node to any scene. Configure when and what to save in the Inspector.
# No code required — everything is driven by Inspector properties.
@tool
class_name EasyStoreTrigger
extends Node

## Section name to save/load automatically.
@export var section: String = "player"

## Save slot to use (-1 = EasyStore's current active slot).
@export var slot: int = -1

## Save when this node's parent scene is about to change (tree_exiting).
@export var save_on_scene_exit: bool = true

## Load when this node enters the scene tree (_ready).
@export var load_on_scene_enter: bool = true

## Callable the scene provides to get the data Dictionary to save.
## Connect via: $EasyStoreTrigger.data_provider = func(): return { ... }
var data_provider: Callable = Callable()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if load_on_scene_enter:
		_do_load()
	if save_on_scene_exit:
		get_tree().root.child_exiting_tree.connect(_on_root_child_exiting)


func _on_root_child_exiting(node: Node) -> void:
	# Fire only when the parent scene (owner) is being removed
	if node == owner or node == get_parent():
		_do_save()


func _do_save() -> void:
	if not data_provider.is_valid():
		push_warning("EasyStoreTrigger: data_provider not set on '%s'." % name)
		return
	var data: Dictionary = data_provider.call()
	EasyStore.save(section, data, slot)


func _do_load() -> void:
	var data: Dictionary = EasyStore.load(section, slot)
	if not data.is_empty():
		load_completed.emit(data)

## Emitted after a successful load with the retrieved data.
signal load_completed(data: Dictionary)
