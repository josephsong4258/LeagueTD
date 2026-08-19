class_name Deaths
extends RefCounted

# ARCHITECTURE.md §4 step 10. Remove enemies at hp <= 0 and emit a death event per
# removal, preserving enemy array order for the survivors. Rebuilding the array
# each tick is fine at the 400 cap and keeps indices simple.
#
# Gold payout and alive_count bookkeeping are intentionally not here yet: the
# counterpart (spawn incrementing alive_count, economy paying out) lands with the
# wave scheduler and win/loss check in M1. Adding a decrement now would be
# asymmetric with nothing to increment it.

static func run(world: World, events: Array[SimEvent]) -> void:
	if world.enemies.is_empty():
		return
	var survivors: Array[Enemy] = []
	for enemy in world.enemies:
		if enemy.hp <= 0.0:
			events.append(EnemyDied.new(enemy.id, enemy.path_pos))
		else:
			survivors.append(enemy)
	world.enemies = survivors
