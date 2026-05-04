# EasyStore

[![Godot 4](https://img.shields.io/badge/Godot-4.4+-478cbf?logo=godotengine&logoColor=white)](https://godotengine.org/)
[![Version](https://img.shields.io/badge/version-1.0.0-3498db)](./plugin.cfg)

**EasyStore** is a **modular save system addon** for [**Godot 4**](https://godotengine.org/). It exposes one clean **Autoload API** (`EasyStore`) while routing all persistence through **pluggable backends**—**Local** and **Steam Cloud**—so game code stays the same regardless of where data is stored.

Slots, sections, in-memory caching, autosave, versioned migrations, multi-backend sync, and conflict resolution are all handled internally. You configure the active backends, call `save` / `load` / `sync`, react to signals, and drop optional nodes such as **`EasyStoreTrigger`** where you need scene-level auto-save.

---

## 📑 Table of contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Documentation](#documentation)
- [Project layout](#project-layout)
- [Changelog](#changelog)
- [Credits](#credits)

---

## ✨ Features

| | |
| :--- | :--- |
| **Single public API** | One **`EasyStore`** Autoload: backends, slots, sections, signals, autosave, migrations, and debug. |
| **Swappable backends** | **`StorageBackend`** contract; **Local** and **Steam Cloud** backends included. New backends can be added without touching game code. |
| **Multi-backend sync** | Run **Local + Steam** simultaneously. Save writes to both in parallel; `sync()` aligns timestamps automatically on reconnect. |
| **Conflict resolution** | Four strategies: `NEWEST_WINS` (default), `CLOUD_WINS`, `LOCAL_WINS`, and `MANUAL` (signal-driven dialog). |
| **Section cache** | Write-through in-memory buffer with dirty tracking. `save()` is instant; I/O is flushed asynchronously. |
| **Slot system** | Multiple independent save slots with lightweight sidecar metadata for fast slot listing. |
| **Autosave** | Built-in timer with configurable interval. Emits `autosave_triggered` every cycle. |
| **Migrations** | Register `from → to` callables. Applied automatically on load when `save_version < current_version`. |
| **Async I/O** | Thread + semaphore worker keeps file operations off the main thread. |
| **Steam Cloud backend** | Reads and writes to **Steam Remote Storage** via [GodotSteam](https://godotsteam.com/). Resolved at runtime — no parse errors when the plugin is absent. |
| **Drop-in node** | **`EasyStoreTrigger`** auto-saves on configurable scene lifecycle events. |
| **Debug tooling** | Structured logger, runtime debug info, and a `debug_mode()` toggle. |

---

## 📋 Requirements

| Item | Required? | Notes |
| :--- | :---: | :--- |
| **Godot 4.4+** | Yes | Developed and tested on Godot **4.4+** (see [`plugin.cfg`](./plugin.cfg)). |
| **GodotSteam GDExtension 4.4+** | Steam backend only | Official [**GodotSteam**](https://godotsteam.com/) plugin by **Gramps**. Required only when using `StoreEnums.BackendType.STEAM`. |

Expected install path in your project:

```text
res://addons/easystore/
```

---

## 📦 Installation

1. Copy this repository's `addons/easystore` folder into your Godot project under **`res://addons/easystore/`**.
2. Open **Project → Project Settings → Plugins**.
3. Enable **EasyStore** — the editor registers the **`EasyStore`** autoload (see [`plugin.gd`](./plugin.gd) and [`easystore.tscn`](./easystore.tscn)).
4. Optionally configure a **`EasyStoreConfig`** resource and pass it to `EasyStore.initialize(config)`.
5. Add at least one backend with **`EasyStore.add_backend(StoreEnums.BackendType.LOCAL)`** and start saving.

> **Steam backend:** also install [GodotSteam GDExtension 4.4+](https://godotsteam.com/) and add the Steam backend with `EasyStore.add_backend(StoreEnums.BackendType.STEAM)` after verifying that Steam is running.

---

## 🚀 Quick start

### 1️⃣ Verify the autoload

After enabling the plugin, you should see **`EasyStore`** under **Project → Project Settings → Autoloads**, pointing at `res://addons/easystore/easystore.tscn`.

### 2️⃣ Initialize with local storage

```gdscript
func _ready() -> void:
    EasyStore.initialize()
    EasyStore.add_backend(StoreEnums.BackendType.LOCAL)
```

### 3️⃣ Save and load data

```gdscript
# Save a section — written to cache instantly, flushed to disk async
EasyStore.save("player", { "level": 5, "health": 100, "coins": 320 })

# Load a section — returns from cache if already loaded, {} otherwise
var player_data: Dictionary = EasyStore.load("player")

# Await confirmation that the write reached disk
await EasyStore.save_completed
```

### 4️⃣ Add Steam Cloud (optional)

```gdscript
func _ready() -> void:
    EasyStore.initialize()
    EasyStore.add_backend(StoreEnums.BackendType.LOCAL)

    if Engine.has_singleton("Steam") and Engine.get_singleton("Steam").isSteamRunning():
        EasyStore.add_backend(StoreEnums.BackendType.STEAM)
        await EasyStore.sync()   # align local ↔ cloud on startup
```

### 5️⃣ Multiple save slots

```gdscript
# Switch to slot 2 and save
EasyStore.set_slot(2)
EasyStore.save("world", { "level_name": "forest", "time": 1200 })

# List all slots with metadata
var slots: Array[SaveMetadata] = await EasyStore.list_slots()
for meta in slots:
    print("Slot %d — %s" % [meta.slot, meta.custom.get("title", "Untitled")])
```

### 6️⃣ Autosave

```gdscript
func _ready() -> void:
    EasyStore.autosave_triggered.connect(func(slot): print("Autosaved slot ", slot))
    EasyStore.enable_autosave(120.0)   # every 2 minutes
```

### 7️⃣ Save migrations

```gdscript
func _ready() -> void:
    EasyStore.set_current_version(2)

    # v1 → v2: add a stamina field that didn't exist before
    EasyStore.register_migration(1, 2, func(sections: Dictionary) -> Dictionary:
        sections["player"]["stamina"] = 100
        return sections
    )

    EasyStore.initialize()
    EasyStore.add_backend(StoreEnums.BackendType.LOCAL)
```

### 8️⃣ React to signals

```gdscript
func _ready() -> void:
    EasyStore.save_completed.connect(_on_save_completed)
    EasyStore.load_completed.connect(_on_load_completed)
    EasyStore.error_occurred.connect(_on_error)
    EasyStore.sync_conflict.connect(_on_sync_conflict)


func _on_save_completed(slot: int, success: bool) -> void:
    if success:
        print("Slot %d saved." % slot)


func _on_load_completed(slot: int, data: Dictionary, success: bool) -> void:
    if success:
        print("Loaded slot %d: %s" % [slot, data])


func _on_error(code: int, message: String) -> void:
    push_error("[EasyStore] Error %d: %s" % [code, message])


func _on_sync_conflict(slot: int, key: String, local_data: Variant, cloud_data: Variant) -> void:
    # MANUAL strategy — decide which version wins
    if cloud_data.get("level", 0) > local_data.get("level", 0):
        EasyStore.save(key, cloud_data)
    else:
        EasyStore.save(key, local_data)
```

---

## 📚 Documentation

The **official documentation** is hosted at:

**[EasyStore Official Documentation](https://iuxgames.github.io/EasyStore_WebSite/)**

Full interactive docs with sidebar navigation, **EN / ES** language toggle, and **quick search** — covering all backends, the full API reference, signals, enums, migrations, multi-backend sync, custom backend guide, and complete examples.

---

## 🗂 Project layout

```text
addons/easystore/
├── plugin.cfg                      # Plugin metadata
├── plugin.gd                       # EditorPlugin: autoload registration
├── easystore.tscn                  # Autoload scene root
├── easystore.gd                    # EasyStore singleton (public API facade)
├── config/
│   ├── easystore_config.gd         # Global configuration resource
│   ├── local_backend_config.gd     # Local backend options (path, format, encryption)
│   └── steam_backend_config.gd     # Steam backend options (file prefix)
├── core/
│   ├── store_enums.gd              # BackendType, ConflictStrategy, SerializationFormat, ErrorCode
│   ├── store_events.gd             # Internal event bus (Node child of autoload)
│   ├── storage_backend.gd          # Abstract backend contract
│   ├── save_file.gd                # Save data model (Resource)
│   └── save_metadata.gd            # Per-slot metadata sidecar (Resource)
├── backends/
│   ├── local/
│   │   └── local_backend.gd        # Local filesystem backend
│   └── steam/
│       └── steam_backend.gd        # Steam Remote Storage backend (GodotSteam)
├── subsystems/
│   ├── slot_manager.gd             # Active slot tracking and slot lifecycle
│   ├── section_cache.gd            # In-memory write-through cache with dirty tracking
│   ├── autosave_timer.gd           # Configurable autosave interval
│   ├── migration_manager.gd        # Versioned migration chain execution
│   ├── sync_manager.gd             # Multi-backend orchestration and conflict resolution
│   └── async_worker.gd             # Thread + semaphore async I/O queue
├── debug/
│   ├── store_logger.gd             # Structured log buffer
│   └── store_debugger.gd           # Runtime debug info and mode toggle
└── nodes/
    └── easy_store_trigger.gd       # Drop-in scene node for automatic saving
```

---

## 📝 Changelog

### v1.0.0
- **Initial release.**
- **Local backend** — saves to `user://saves/slot_N.sav` + `slot_N.meta.json`. Supports JSON and binary serialization formats, optional AES encryption, and optional compression via `FileAccess`.
- **Steam Cloud backend** — reads and writes to Steam Remote Storage using [GodotSteam GDExtension 4.4+](https://godotsteam.com/). Steam is resolved at runtime via `Engine.get_singleton("Steam")` — no parse errors when the plugin is absent.
- **Multi-backend sync** — `sync()` compares `SaveMetadata.timestamp` across all active backends and resolves conflicts with the configured `ConflictStrategy` (`NEWEST_WINS`, `CLOUD_WINS`, `LOCAL_WINS`, `MANUAL`).
- **Section cache** — write-through in-memory buffer with per-section dirty tracking. `save()` is synchronous from the game's perspective; disk I/O is dispatched to `AsyncWorker`.
- **Slot system** — multiple save slots with lightweight sidecar metadata for instant `list_slots()` without deserializing full save data.
- **Autosave** — built-in timer with configurable interval. Emits `autosave_triggered`.
- **Migrations** — register `from_version → to_version` callables via `register_migration()`. Applied automatically on load.
- **Drop-in node** — `EasyStoreTrigger` for scene-level auto-save on configurable lifecycle events.
- **Debug tooling** — `StoreLogger`, `StoreDebugger`, `get_logs()`, `get_debug_info()`, `debug_mode()`.

---

## 🙏 Credits

- **EasyStore** — **IUX Games**, **Isaackiux** · version **1.0.0** (see [`plugin.cfg`](./plugin.cfg)).
- **GodotSteam** — [Gramps](https://godotsteam.com/) · used as the transport layer for the Steam Cloud backend.
