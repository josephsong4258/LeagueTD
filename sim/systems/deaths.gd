class_name Deaths
extends RefCounted

# ARCHITECTURE.md §4 step 10: "remove entities, pay gold, emit death events." Remove
# enemies at hp <= 0, preserving enemy array order for the survivors. Rebuilding the
# array each tick is fine at the 400 cap and keeps indices simple.
#
# Kill-gold economy (M1): each removal pays out the enemy's stamped reward and
# decrements alive_count — the mirror of Spawn's +1, so the loss counter Win/loss
# reads (§4 step 11) stays exact. Gold is kill-only in M1; stipend/interest are
# stubbed off in Content until M4/M5 (§7).

static func run(world: World, events: Array[SimEvent]) -> void:
	if world.enemies.is_empty():
		return
	var survivors: Array[Enemy] = []
	for enemy in world.enemies:
		if enemy.hp <= 0.0:
			world.gold += enemy.gold
			world.alive_count -= 1
			events.append(EnemyDied.new(enemy.id, enemy.path_pos, enemy.gold))
		else:
			survivors.append(enemy)
	world.enemies = survivors
