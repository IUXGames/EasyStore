# store_debugger.gd
# Bridges StoreEvents log_entry signals to StoreLogger and exposes
# a get_debug_info() snapshot for runtime inspection.
extends Node

var _logger:   Node   # StoreLogger, injected via setup()
var _events:   Node   # StoreEvents, injected via setup()
var _backends: Array  # Reference to EasyStore._backends


func setup(logger: Node, events: Node, backends_ref: Array) -> void:
	_logger   = logger
	_events   = events
	_backends = backends_ref
	_events.log_entry.connect(_on_log_entry)


func _on_log_entry(level: String, message: String, _context: Dictionary) -> void:
	_logger.log(level, message)


## Returns a snapshot of the current EasyStore runtime state.
func get_debug_info() -> Dictionary:
	var backend_info: Array = []
	for b in _backends:
		backend_info.append({
			"type":     b.get_backend_type(),
			"is_ready": b.is_ready(),
			"caps":     b._backend_get_capabilities(),
		})
	return {
		"backends":    backend_info,
		"log_entries": _logger.get_logs(20),
	}
