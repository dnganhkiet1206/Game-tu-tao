extends Node
## Global signal bus. Systems talk through here so they stay decoupled.

# Economy / inventory
signal money_changed(amount: int)
signal inventory_changed
signal item_picked_up(item_id: String, count: int)

# Time / weather
signal hour_changed(hour: int)
signal weather_changed(kind: String)

# Player
signal player_spawned(player: Node3D)
signal player_entered_vehicle(vehicle: Node3D)
signal player_exited_vehicle(vehicle: Node3D)
signal player_busted(fine: int)

# Crime
signal wanted_changed(level: int)
signal crime_committed(kind: String, position: Vector3)

# Jobs
signal job_started(job_id: String)
signal job_updated(job_id: String, text: String)
signal job_ended(job_id: String, success: bool)

# Commerce / home
signal shop_requested(kind: String)
signal sleep_requested
signal upgrade_requested

# UI
signal toast(message: String)
signal objective_changed(text: String, world_pos: Vector3, active: bool)
signal dialogue_opened(speaker: String, text: String)
signal dialogue_closed

# Persistence
signal game_saved
signal game_loaded


func emit_toast(message: String) -> void:
	toast.emit(message)


func clear_objective() -> void:
	objective_changed.emit("", Vector3.ZERO, false)
