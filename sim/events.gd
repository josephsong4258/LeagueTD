class_name SimEvent
extends RefCounted

# Systems emit events; step() accumulates them and returns them at the end of the
# tick. The renderer turns events into sprites, sound, and VFX and never diffs
# World to reconstruct what happened (ARCHITECTURE.md §4). Concrete typed event
# classes land as the systems that emit them are built — this is the base and the
# kind registry.

enum Kind {
	ENEMY_SPAWNED,
	ENEMY_DAMAGED,
	ENEMY_DIED,
	PROJECTILE_FIRED,
	PROJECTILE_HIT,
	WAVE_CLEARED,
	GAME_OVER,
}

var kind: int = -1

func _init(p_kind: int = -1) -> void:
	kind = p_kind
