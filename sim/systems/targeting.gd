class_name Targeting
extends RefCounted

# ARCHITECTURE.md §4 step 5 / §6. Each deployed unit picks a target by scanning
# only the buckets its coverage touches, then doing a precise interval test. The
# M0 policy is "first" — the enemy furthest along the path (highest lap-adjusted
# progress) among those in range. Units are iterated in tile order (world.units is
# kept sorted), so the choice is deterministic.
#
# Sets unit.target_enemy_id (0 = no valid target); Combat consumes it this tick.

const _EPS := 0.0001

static func run(world: World) -> void:
	for unit in world.units:
		unit.target_enemy_id = 0
		if unit.stats == null or unit.coverage.is_empty():
			continue
		var best_id := 0
		var best_progress := -INF
		for b in unit.buckets:
			for idx in world.buckets[b]:
				var enemy := world.enemies[idx]
				if not _in_coverage(unit.coverage, enemy.path_pos):
					continue
				var progress := float(enemy.lap) * Path.perimeter() + enemy.path_pos
				if progress > best_progress:
					best_progress = progress
					best_id = enemy.id
		unit.target_enemy_id = best_id

# A perimeter position is covered if it falls inside any of the unit's cached
# intervals. Intervals never wrap past the origin (a corner-spanning circle yields
# two separate intervals), so a plain containment test handles the wrap case too.
static func _in_coverage(intervals: Array[Vector2], path_pos: float) -> bool:
	for interval in intervals:
		if path_pos >= interval.x - _EPS and path_pos <= interval.y + _EPS:
			return true
	return false
