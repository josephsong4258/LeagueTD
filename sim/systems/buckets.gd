class_name Buckets
extends RefCounted

# ARCHITECTURE.md §4 step 4 / §6. The perimeter is split into Path.BUCKET_COUNT
# fixed buckets. Each tick this clears and refills world.buckets so targeting can
# scan only the buckets a unit's coverage touches instead of every enemy. O(n),
# trivial at the 400-enemy cap; no sorting, no spatial tree, fully deterministic.
#
# Buckets store indices into world.enemies (not ids): the enemies array is not
# mutated between this rebuild and targeting, so indices are stable and cheap.

static func rebuild(world: World) -> void:
	var buckets := world.buckets
	if buckets.size() != Path.BUCKET_COUNT:
		# First tick, or the count changed: allocate the fixed set of buckets once.
		buckets = []
		buckets.resize(Path.BUCKET_COUNT)
		for i in Path.BUCKET_COUNT:
			buckets[i] = PackedInt32Array()
		world.buckets = buckets
	else:
		for i in Path.BUCKET_COUNT:
			buckets[i].clear()
	for i in world.enemies.size():
		var b := Path.bucket_of(world.enemies[i].path_pos)
		buckets[b].append(i)
