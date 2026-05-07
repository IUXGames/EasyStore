# EasyStore

[![Godot 4](https://img.shields.io/badge/Godot-4.4+-478cbf?logo=godotengine&logoColor=white)](https://godotengine.org/)
[![Version](https://img.shields.io/badge/version-1.0.0-3498db)](./plugin.cfg)

**EasyStore** is a **modular save system addon** for [**Godot 4**](https://godotengine.org/). It exposes one clean **Autoload API** (`EasyStore`) while routing all persistence through **pluggable backends**â€”**Local** and **Steam Cloud**â€”so game code stays the same regardless of where data is stored.

Slots, sections, in-memory caching, autosave, versioned migrations, multi-backend sync, and conflict resolution are all handled internally. You configure the active backends, call `save` / `load` / `sync`, react to signals, and drop optional nodes such as **`EasyStoreTrigger`** where you need scene-level auto-save.

---

## ðŸ“‘ Table of contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Documentation](#documentation)
- [Project layout](#project-layout)
- [Changelog](#changelog)
- [Credits](#credits)

---

## âœ¨ Features

| | |
| :--- | :--- |
| **Single public API** | One **`EasyStore`** Autoload: backends, slots, sections, signals, autosave, migrations, and debug. |
| **Swappable backends** | **`StorageBackend`** contract; **Local** and **Steam Cloud** backends included. New backends can be added without touching game code. |
| **Multi-backend sync** | Run **Local + Steam** simultaneously. Save writes to both in parallel; `sync()` aligns timestamps automatically on reconnect. |
| **Conflict resolution** | Four strategies: `NEWEST_WINS` (default), `CLOUD_WINS`, `LOCAL_WINS`, and `MANUAL` (signal-driven dialog). |
| **Section cache** | Write-through in-memory buffer with dirty tracking. `save()` is instant; I/O is flushed asynchronously. |
| **Slot system** | Multiple independent save slots with lightweight sidecar metadata for fast slot listing. |
| **Autosave** | Built-in timer with configurable interval. Emits `autosave_triggered` every cycle. |
| **Migrations** | Register `from â†’ to` callables. Applied automatically on load when `save_version < current_version`. |
| **Async I/O** | Thread + semaphore worker keeps file operations off the main thread. |
| **Steam Cloud backend** | Reads and writes to **Steam Remote Storage** via [GodotSteam](https://godotsteam.com/). Resolved at runtime â€” no parse errors when the plugin is absent. |
| **Drop-in node** | **`EasyStoreTrigger`** auto-saves on configurable scene lifecycle events. |
| **Debug tooling** | Structured logger, runtime debug info, and a `debug_mode()` toggle. |

---

## ðŸ“‹ Requirements

| Item | Required? | Notes |
| :--- | :---: | :--- |
| **Godot 4.4+** | Yes | Developed and tested on Godot **4.4+** (see [`plugin.cfg`](./plugin.cfg)). |
| **GodotSteam GDExtension 4.4+** | Steam backend only | Official [**GodotSteam**](https://godotsteam.com/) plugin by **Gramps**. Required only when using `StoreEnums.BackendType.STEAM_CLOUD`. |

Expected install path in your project:

```text
res://addons/easystore/
```

---

## ðŸ“¦ Installation

1. Copy this repository's `addons/easystore` folder into your Godot project under **`res://addons/easystore/`**.
2. Open **Project â†’ Project Settings â†’ Plugins**.
3. Enable **EasyStore** â€” the editor registers the **`EasyStore`** autoload (see [`plugin.gd`](./plugin.gd) and [`easystore.tscn`](./easystore.tscn)).
4. Optionally configure a **`EasyStoreConfig`** resource and pass it to `EasyStore.initialize(config)`.
5. Add at least one backend with **`EasyStore.add_backend(StoreEnums.BackendType.LOCAL)`** and start saving.

> **Steam backend:** also install [GodotSteam GDExtension 4.4+](https://godotsteam.com/) and add the Steam backend with `EasyStore.add_backend(StoreEnums.BackendType.STEAM_CLOUD)` after verifying that Steam is running.

---

## ðŸš€ Quick start

### 1ï¸âƒ£ Verify the autoload

After enabling the plugin, you should see **`EasyStore`** under **Project â†’ Project Settings â†’ Autoloads**, pointing at `res://addons/easystore/easystore.tscn`.

### 2ï¸âƒ£ Initialize with local storage

```gdscript
func _ready() -> void:
    EasyStore.initialize()
    EasyStore.add_backend(StoreEnums.BackendType.LOCAL)
```

### 3ï¸âƒ£ Save and load data

```gdscript
# Save a section â€” written to cache instantly, flushed to disk async
EasyStore.save("player", { "level": 5, "health": 100, "coins": 320 })

# Load a section â€” returns from cache if already loaded, {} otherwise
var player_data: Dictionary = EasyStore.load("player")

# Await confirmation that the write reached disk
await EasyStore.save_completed
```

### 4ï¸âƒ£ Add Steam Cloud (optional)

```gdscript
func _ready() -> void:
    EasyStore.initialize()
    EasyStore.add_backend(StoreEnums.BackendType.LOCAL)

    if Engine.has_singleton("Steam") and Engine.get_singleton("Steam").isSteamRunning():
        EasyStore.add_backend(StoreEnums.BackendType.STEAM_CLOUD)
        await EasyStore.sync()   # align local â†” cloud on startup
```

### 5ï¸âƒ£ Multiple save slots

```gdscript
# Switch to slot 2 and save
EasyStore.set_slot(2)
EasyStore.save("world", { "level_name": "forest", "time": 1200 })

# List all slots with metadata
var slots: Array[SaveMetadata] = await EasyStore.list_slots()
for meta in slots:
    print("Slot %d â€” %s" % [meta.slot, meta.custom.get("title", "Untitled")])
```

### 6ï¸âƒ£ Autosave

```gdscript
func _ready() -> void:
    EasyStore.autosave_triggered.connect(func(slot): print("Autosaved slot ", slot))
    EasyStore.enable_autosave(120.0)   # every 2 minutes
```

### 7ï¸âƒ£ Save migrations

```gdscript
func _ready() -> void:
    EasyStore.set_current_version(2)

    # v1 â†’ v2: add a stamina field that didn't exist before
    EasyStore.register_migration(1, 2, func(sections: Dictionary) -> Dictionary:
        sections["player"]["stamina"] = 100
        return sections
    )

    EasyStore.initialize()
    EasyStore.add_backend(StoreEnums.BackendType.LOCAL)
```

### 8ï¸âƒ£ React to signals

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
    # MANUAL strategy â€” decide which version wins
    if cloud_data.get("level", 0) > local_data.get("level", 0):
        EasyStore.save(key, cloud_data)
    else:
        EasyStore.save(key, local_data)
```

---

## ðŸ“š Documentation

The **official documentation** is hosted at:

**[EasyStore Official Documentation](https://iuxgames.github.io/EasyStore_WebSite/)**

Full interactive docs with sidebar navigation, **EN / ES** language toggle, and **quick search** â€” covering all backends, the full API reference, signals, enums, migrations, multi-backend sync, custom backend guide, and complete examples.

---

## ðŸ—‚ Project layout

```text
addons/easystore/
â”œâ”€â”€ plugin.cfg                      # Plugin metadata
â”œâ”€â”€ plugin.gd                       # EditorPlugin: autoload registration
â”œâ”€â”€ easystore.tscn                  # Autoload scene root
â”œâ”€â”€ easystore.gd                    # EasyStore singleton (public API facade)
â”œâ”€â”€ config/
â”‚   â”œâ”€â”€ easystore_config.gd         # Global configuration resource
â”‚   â”œâ”€â”€ local_backend_config.gd     # Local backend options (path, format, encryption)
â”‚   â””â”€â”€ steam_backend_config.gd     # Steam backend options (file prefix)
â”œâ”€â”€ core/
â”‚   â”œâ”€â”€ store_enums.gd              # BackendType, ConflictStrategy, SerializationFormat, ErrorCode
â”‚   â”œâ”€â”€ store_events.gd             # Internal event bus (Node child of autoload)
â”‚   â”œâ”€â”€ storage_backend.gd          # Abstract backend contract
â”‚   â”œâ”€â”€ save_file.gd                # Save data model (Resource)
â”‚   â””â”€â”€ save_metadata.gd            # Per-slot metadata sidecar (Resource)
â”œâ”€â”€ backends/
â”‚   â”œâ”€â”€ local/
â”‚   â”‚   â””â”€â”€ local_backend.gd        # Local filesystem backend
â”‚   â””â”€â”€ steam/
â”‚       â””â”€â”€ steam_backend.gd        # Steam Remote Storage backend (GodotSteam)
â”œâ”€â”€ subsystems/
â”‚   â”œâ”€â”€ slot_manager.gd             # Active slot tracking and slot lifecycle
â”‚   â”œâ”€â”€ section_cache.gd            # In-memory write-through cache with dirty tracking
â”‚   â”œâ”€â”€ autosave_timer.gd           # Configurable autosave interval
â”‚   â”œâ”€â”€ migration_manager.gd        # Versioned migration chain execution
â”‚   â”œâ”€â”€ sync_manager.gd             # Multi-backend orchestration and conflict resolution
â”‚   â””â”€â”€ async_worker.gd             # Thread + semaphore async I/O queue
â”œâ”€â”€ debug/
â”‚   â”œâ”€â”€ store_logger.gd             # Structured log buffer
â”‚   â””â”€â”€ store_debugger.gd           # Runtime debug info and mode toggle
â””â”€â”€ nodes/
    â””â”€â”€ easy_store_trigger.gd       # Drop-in scene node for automatic saving
```

---

## ðŸ“ Changelog

### v1.0.0
- **Initial release.**
- **Local backend** â€” saves to `user://saves/slot_N.sav` + `slot_N.meta.json`. Supports JSON and binary serialization formats, optional AES encryption, and optional compression via `FileAccess`.
- **Steam Cloud backend** â€” reads and writes to Steam Remote Storage using [GodotSteam GDExtension 4.4+](https://godotsteam.com/). Steam is resolved at runtime via `Engine.get_singleton("Steam")` â€” no parse errors when the plugin is absent.
- **Multi-backend sync** â€” `sync()` compares `SaveMetadata.timestamp` across all active backends and resolves conflicts with the configured `ConflictStrategy` (`NEWEST_WINS`, `CLOUD_WINS`, `LOCAL_WINS`, `MANUAL`).
- **Section cache** â€” write-through in-memory buffer with per-section dirty tracking. `save()` is synchronous from the game's perspective; disk I/O is dispatched to `AsyncWorker`.
- **Slot system** â€” multiple save slots with lightweight sidecar metadata for instant `list_slots()` without deserializing full save data.
- **Autosave** â€” built-in timer with configurable interval. Emits `autosave_triggered`.
- **Migrations** â€” register `from_version â†’ to_version` callables via `register_migration()`. Applied automatically on load.
- **Drop-in node** â€” `EasyStoreTrigger` for scene-level auto-save on configurable lifecycle events.
- **Debug tooling** â€” `StoreLogger`, `StoreDebugger`, `get_logs()`, `get_debug_info()`, `debug_mode()`.

---

## ðŸ™ Credits

- **EasyStore** â€” **IUX Games**, **Isaackiux** Â· version **1.0.0** (see [`plugin.cfg`](./plugin.cfg)).
- **GodotSteam** â€” [Gramps](https://godotsteam.com/) Â· used as the transport layer for the Steam Cloud backend.
