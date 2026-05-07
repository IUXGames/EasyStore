# store_events.gd
# Internal signal bus for EasyStore subsystems.
# Subsystems emit and connect to these signals instead of calling each other
# directly, keeping them fully decoupled.
extends Node

# ─── Save / Load ──────────────────────────────────────────────────────────────
signal save_requested(slot: int, save_file: SaveFile)
signal load_requested(slot: int)

# ─── Slot ─────────────────────────────────────────────────────────────────────
signal slot_changed(new_slot: int)
signal slot_deleted(slot: int)

# ─── Migration ────────────────────────────────────────────────────────────────
signal migration_needed(save_file: SaveFile)
signal migration_applied(old_version: int, new_version: int)

# ─── Sync ─────────────────────────────────────────────────────────────────────
signal sync_requested(slot: int)
signal sync_conflict_detected(slot: int, key: String, local_data: Variant, cloud_data: Variant)

# ─── Auto-save ────────────────────────────────────────────────────────────────
signal autosave_tick(slot: int)

# ─── Debug / Logging ──────────────────────────────────────────────────────────
signal log_entry(level: String, message: String, context: Dictionary)
