class_name NpcManager
extends Node3D
## Spawns the island cast and ticks them. NPCs handle their own LOD
## (physics near the player, cheap gliding far away).

var npcs: Array[NPC] = []


func spawn_all() -> void:
	for entry in NpcData.CAST:
		var npc: NPC
		if entry.role == "police":
			npc = PoliceOfficer.new()
		else:
			npc = NPC.new()
		npc.data = entry
		npc.name = "NPC_" + entry.id
		add_child(npc)
		npc.snap_to_schedule()
		npcs.append(npc)


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	for npc in npcs:
		if is_instance_valid(npc):
			npc.tick(delta)
