# async_worker.gd
# Thread pool (single worker thread) for non-blocking file I/O.
# LocalBackend dispatches all disk operations here so the main thread is never blocked.
# SteamBackend does NOT use this — Steam has its own async callback system.
extends Node

var _thread: Thread
var _semaphore: Semaphore
var _mutex: Mutex
var _queue: Array[Dictionary] = []  # { work: Callable, on_complete: Callable }
var _running: bool = false


func _ready() -> void:
	_semaphore = Semaphore.new()
	_mutex     = Mutex.new()
	_thread    = Thread.new()
	_running   = true
	_thread.start(_worker_loop)


func _exit_tree() -> void:
	_running = false
	_semaphore.post()       # unblock thread so it can exit
	_thread.wait_to_finish()


## Queue a unit of work.
## work        — Callable executed on the worker thread; should return a Variant result.
## on_complete — Callable called on the MAIN thread with (result: Variant).
func dispatch(work: Callable, on_complete: Callable = Callable()) -> void:
	_mutex.lock()
	_queue.push_back({ "work": work, "on_complete": on_complete })
	_mutex.unlock()
	_semaphore.post()


# ─── Internal ─────────────────────────────────────────────────────────────────

func _worker_loop() -> void:
	while _running:
		_semaphore.wait()
		if not _running:
			break
		_mutex.lock()
		var job: Dictionary = _queue.pop_front() if not _queue.is_empty() else {}
		_mutex.unlock()
		if job.is_empty():
			continue
		var result: Variant = job["work"].call()
		if job["on_complete"].is_valid():
			job["on_complete"].bind(result).call_deferred()
