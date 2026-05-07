# store_logger.gd
# Structured logger for EasyStore. Matches LinkUx's DebugLogger format:
#   [EasyStore] LEVEL [Context]: message
# Supports log levels and buffers entries retrievable via EasyStore.get_logs().
extends Node

## Emitted on every log entry that passes the active level filter.
signal log_emitted(level: int, level_name: String, context: String, message: String, formatted: String, timestamp_msec: int)

const MAX_BUFFER: int = 500
const _PREFIX    := "[EasyStore]"

var _level:  int               = StoreEnums.LogLevel.NONE
var _buffer: Array[Dictionary] = []


# ─── Setup ────────────────────────────────────────────────────────────────────

func setup(log_level: int) -> void:
	_level = log_level


func set_log_level(level: int) -> void:
	_level = level


# ─── Public log methods ───────────────────────────────────────────────────────

func error(message: String, context: String = "") -> void:
	_write(StoreEnums.LogLevel.ERROR, "ERROR", message, context)

func warn(message: String, context: String = "") -> void:
	_write(StoreEnums.LogLevel.WARN, "WARN", message, context)

func info(message: String, context: String = "") -> void:
	_write(StoreEnums.LogLevel.INFO, "INFO", message, context)

func debug(message: String, context: String = "") -> void:
	_write(StoreEnums.LogLevel.DEBUG, "DEBUG", message, context)

func trace(message: String, context: String = "") -> void:
	_write(StoreEnums.LogLevel.TRACE, "TRACE", message, context)

## Bridge used by StoreDebugger to forward log_entry events from StoreEvents.
func log(level_name: String, message: String, context: String = "") -> void:
	_write(_name_to_level(level_name), level_name, message, context)


# ─── Buffer access ────────────────────────────────────────────────────────────

## Return the last `limit` entries (0 = all).
func get_logs(limit: int = 0) -> Array[Dictionary]:
	if limit <= 0 or limit >= _buffer.size():
		return _buffer.duplicate()
	return _buffer.slice(_buffer.size() - limit)


func clear() -> void:
	_buffer.clear()


# ─── Internal ─────────────────────────────────────────────────────────────────

func _write(level: int, level_name: String, message: String, context: String) -> void:
	# Always buffer regardless of level so get_logs() returns a full history.
	var entry := {
		"level":     level_name,
		"context":   context,
		"message":   message,
		"timestamp": Time.get_unix_time_from_system(),
	}
	if _buffer.size() >= MAX_BUFFER:
		_buffer.pop_front()
	_buffer.append(entry)

	# Only print / push_error when entry passes the active filter.
	if level > _level:
		return

	var formatted := _format_message(level_name, message, context)

	match level:
		StoreEnums.LogLevel.ERROR: push_error(formatted)
		StoreEnums.LogLevel.WARN:  push_warning(formatted)
		_:                         print(formatted)

	log_emitted.emit(level, level_name, context, message, formatted, Time.get_ticks_msec())


func _format_message(level_name: String, message: String, context: String) -> String:
	var msg := _PREFIX + " " + level_name
	if context != "":
		msg += " [%s]" % context
	msg += ": " + message
	return msg


func _name_to_level(level_name: String) -> int:
	match level_name:
		"ERROR": return StoreEnums.LogLevel.ERROR
		"WARN":  return StoreEnums.LogLevel.WARN
		"INFO":  return StoreEnums.LogLevel.INFO
		"DEBUG": return StoreEnums.LogLevel.DEBUG
		"TRACE": return StoreEnums.LogLevel.TRACE
	return StoreEnums.LogLevel.INFO
