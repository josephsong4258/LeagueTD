class_name Movement
extends RefCounted

# ARCHITECTURE.md §4 step 3: advance path_pos, wrap at the perimeter, increment
# lap. prev_path_pos is snapshotted here so the renderer can interpolate between
# ticks (§9). Iteration order over enemies does not affect the outcome of this
# system, but per-unit systems must iterate in tile order (§3).

static func run(world: World) -> void:
	var dir := float(world.direction)
	for enemy in world.enemies:
		enemy.prev_path_pos = enemy.path_pos
		var advanced := enemy.path_pos + enemy.speed * dir
		var wrapped := fposmod(advanced, Path.PERIMETER)
		if world.direction > 0 and wrapped < enemy.path_pos:
			enemy.lap += 1
		elif world.direction < 0 and wrapped > enemy.path_pos:
			enemy.lap += 1
		enemy.path_pos = wrapped
