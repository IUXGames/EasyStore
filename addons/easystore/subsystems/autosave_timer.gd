# autosave_timer.gd
# Fires autosave_tick on StoreEvents at a configurable interval.
extends Node

var _timer: Timer
var _events: Node   # StoreEvents, injected by EasyStore
var _slot_getter: Callable   # returns the current slot int


func setup(events: Node, slot_getter: Callable) -> void:
	_events      = events
	_slot_getter = slot_getter

	_timer           = Timer.new()
	_timer.one_shot  = false
	_timer.autostart = false
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)


## Start firing autosave events every interval_seconds.
func enable(interval_seconds: float) -> void:
	_timer.wait_time = maxf(interval_seconds, 1.0)
	_timer.start()


## Stop the autosave timer.
func disable() -> void:
	_timer.stop()


func is_active() -> bool:
	return not _timer.is_stopped()


func _on_timer_timeout() -> void:
	var slot: int = _slot_getter.call() if _slot_getter.is_valid() else 0
	_events.autosave_tick.emit(slot)
