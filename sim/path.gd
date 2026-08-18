class_name Path
extends RefCounted

# The entire map is one function (ARCHITECTURE.md §6). A square loop; an enemy's
# position is a single float `d` in [0, PERIMETER), distance clockwise from the
# top-left corner. Everything here is pure and static. The same coverage function
# feeds both the combat math and the hover preview, so the UI can never disagree
# with what the projectiles actually hit.
#
# These are structural constants (geometry + data-structure sizing), not balance
# numbers, so they live here rather than in content JSON. Sim space is abstract;
# the renderer maps it to screen.

const SIDE: float = 900.0
const PERIMETER: float = 4.0 * SIDE
const BUCKET_COUNT: int = 64
const BUCKET_SIZE: float = PERIMETER / float(BUCKET_COUNT)

# Clockwise from the top-left corner (0, 0):
#   seg 0: top    (0,0)       -> (SIDE,0)
#   seg 1: right  (SIDE,0)    -> (SIDE,SIDE)
#   seg 2: bottom (SIDE,SIDE) -> (0,SIDE)
#   seg 3: left   (0,SIDE)    -> (0,0)

static func pos_to_xy(d: float) -> Vector2:
	var dist := fposmod(d, PERIMETER)
	var seg := int(dist / SIDE)
	var t := dist - float(seg) * SIDE
	match seg:
		0: return Vector2(t, 0.0)
		1: return Vector2(SIDE, t)
		2: return Vector2(SIDE - t, SIDE)
		_: return Vector2(0.0, SIDE - t)

# Nearest point on the perimeter to an arbitrary screen-space point, as a
# perimeter distance. Used to snap placement and hit-testing to the track.
static func nearest_pos(p: Vector2) -> float:
	var best_d := 0.0
	var best_dist_sq := INF
	for seg in 4:
		var a := _seg_start(seg)
		var dir := _seg_dir(seg)
		var t: float = clampf((p - a).dot(dir), 0.0, SIDE)
		var point := a + dir * t
		var dist_sq := p.distance_squared_to(point)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_d = float(seg) * SIDE + t
	return best_d

# Which arcs of the perimeter a range circle centered at `center` with radius
# `radius` covers. For perpendicular distance `perp` from a track segment, the
# covered chord half-length is sqrt(radius^2 - perp^2) when radius > perp, and
# nothing otherwise (§6). Returns merged [start, end] intervals in perimeter
# space; a wrap across the origin is left as two intervals, which targeting tests
# independently.
static func coverage_intervals(center: Vector2, radius: float) -> Array[Vector2]:
	var raw: Array[Vector2] = []
	for seg in 4:
		var a := _seg_start(seg)
		var dir := _seg_dir(seg)
		var v := center - a
		var along := v.dot(dir)
		var perp := (v - dir * along).length()
		if radius <= perp:
			continue
		var half := sqrt(radius * radius - perp * perp)
		var lo: float = clampf(along - half, 0.0, SIDE)
		var hi: float = clampf(along + half, 0.0, SIDE)
		if hi <= lo:
			continue
		raw.append(Vector2(float(seg) * SIDE + lo, float(seg) * SIDE + hi))
	return _merge_intervals(raw)

# The bucket a perimeter distance falls in. Each tick, every enemy is bucketed by
# this; each unit stores the buckets its coverage touches, so targeting scans only
# those buckets before the precise interval test (§6).
static func bucket_of(d: float) -> int:
	return int(fposmod(d, PERIMETER) / BUCKET_SIZE)

# The set of bucket indices a coverage interval list touches, deduplicated and
# sorted. Computed once per placement and cached on Unit.buckets.
static func buckets_for_intervals(intervals: Array[Vector2]) -> PackedInt32Array:
	var seen: Dictionary = {}
	var result := PackedInt32Array()
	for interval in intervals:
		var first := int(interval.x / BUCKET_SIZE)
		var last := int((interval.y - 0.0001) / BUCKET_SIZE)
		for b in range(first, last + 1):
			var idx := ((b % BUCKET_COUNT) + BUCKET_COUNT) % BUCKET_COUNT
			if not seen.has(idx):
				seen[idx] = true
				result.append(idx)
	result.sort()
	return result

# --- helpers ---

static func _seg_start(seg: int) -> Vector2:
	match seg:
		0: return Vector2(0.0, 0.0)
		1: return Vector2(SIDE, 0.0)
		2: return Vector2(SIDE, SIDE)
		_: return Vector2(0.0, SIDE)

static func _seg_dir(seg: int) -> Vector2:
	match seg:
		0: return Vector2(1.0, 0.0)
		1: return Vector2(0.0, 1.0)
		2: return Vector2(-1.0, 0.0)
		_: return Vector2(0.0, -1.0)

static func _merge_intervals(raw: Array[Vector2]) -> Array[Vector2]:
	if raw.is_empty():
		return raw
	raw.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var merged: Array[Vector2] = []
	var cur := raw[0]
	for i in range(1, raw.size()):
		var nxt := raw[i]
		if nxt.x <= cur.y + 0.0001:
			cur.y = maxf(cur.y, nxt.y)
		else:
			merged.append(cur)
			cur = nxt
	merged.append(cur)
	return merged
