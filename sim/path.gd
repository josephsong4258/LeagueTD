class_name Path
extends RefCounted

# The entire map is one function (ARCHITECTURE.md §6). The arena is a HEXAGON: a
# six-sided loop filled by a hexagonal cluster of hex tiles. A hexagonal boundary is
# the shape a hex grid tiles with NO gaps — every edge runs along hex edges and every
# one of the six corners is a full tile — which a rectangle/stadium can't do (hex
# angles are 120deg, so they leave dead triangles at rectangular corners, worst of all
# at the corners themselves, which are premium placement spots). An enemy's position
# is a single float `d` in [0, perimeter()), distance clockwise from the right vertex.
#
# The arena is a FLAT-TOP hexagon (a vertex at left and right), so it is a little
# wider than tall. Its tiles are POINTY-TOP hexes (BoardGrid); a pointy-top cluster
# packs into a flat-top hexagonal outline. The ring is six exact straight segments —
# no chord approximation — centered on the origin. The renderer maps sim space to
# screen.
#
# These are structural constants (geometry + data-structure sizing), not balance
# numbers, so they live here rather than in content JSON. The tile size and ring count
# also drive BoardGrid, and the arena is sized from them so the track hugs the cluster.

const CELL_SIZE: float = 42.0             # pointy-top tile radius (center to corner); BoardGrid uses this
const RINGS: int = 5                      # tile-cluster radius; tile count = 1 + 3*RINGS*(RINGS+1)
const TILE_GAP: float = 6.0               # clearance between the outer tiles and the path band
const TRACK_WIDTH: float = 76.0           # the path is a terrain band, TRACK_WIDTH/2 to either side
const BUCKET_COUNT: int = 64

# Lazily built ring + cumulative arc length, cached (pure function of the constants).
static var _ring: PackedVector2Array = PackedVector2Array()
static var _cum: PackedFloat32Array = PackedFloat32Array()   # _cum[i] = arc length ring[0]..ring[i]
static var _perim: float = -1.0

# Circumradius of the arena hexagon: reach past the cluster's corner tiles far enough
# for the band (TRACK_WIDTH/2) plus the tile gap to clear their outer corners. A
# pointy-top corner tile on the horizontal axis reaches sqrt(3)*CELL_SIZE*(RINGS+0.5).
static func circumradius() -> float:
	return sqrt(3.0) * CELL_SIZE * (float(RINGS) + 0.5) + TILE_GAP + TRACK_WIDTH * 0.5

# Center-to-side distance of the arena hexagon (its flat top/bottom edges sit here).
static func apothem() -> float:
	return circumradius() * sqrt(3.0) * 0.5

static func _ensure() -> void:
	if _perim >= 0.0:
		return
	_ring = _build_ring()
	_cum = PackedFloat32Array()
	var acc := 0.0
	var n := _ring.size()
	for i in n:
		_cum.append(acc)
		acc += _ring[i].distance_to(_ring[(i + 1) % n])
	_perim = acc

# Flat-top hexagon: six vertices at 0, 60, ... 300 degrees. Vertex 0 (d = 0) is the
# right point; increasing angle is clockwise on screen (y is down), matching enemy
# travel. Sides are exact straight segments of length CELL-driven circumradius.
static func _build_ring() -> PackedVector2Array:
	var r := circumradius()
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * float(i))
		pts.append(r * Vector2(cos(a), sin(a)))
	return pts

static func perimeter() -> float:
	_ensure()
	return _perim

static func bucket_size() -> float:
	return perimeter() / float(BUCKET_COUNT)

# The ring vertices, for the renderer (draws the band) and BoardGrid.
static func ring() -> PackedVector2Array:
	_ensure()
	return _ring

# The arena hexagon shrunk inward by `margin` (a smaller concentric hexagon). The
# renderer clips boundary tiles to inset_ring(TRACK_WIDTH/2) so the tile field fills
# exactly to the band's inner edge with no gap, straightening the cluster's sawtooth
# outer edge against the track.
static func inset_ring(margin: float) -> PackedVector2Array:
	var r := (apothem() - margin) / (sqrt(3.0) * 0.5)
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * float(i))
		pts.append(r * Vector2(cos(a), sin(a)))
	return pts

# Axis-aligned bounding box of the centerline, for layout/fit. The band overhangs it
# by TRACK_WIDTH/2; the caller adds that if it needs the terrain's outer extent.
static func bounds() -> Rect2:
	var r := circumradius()
	var a := apothem()
	return Rect2(-r, -a, 2.0 * r, 2.0 * a)

# Is `p` inside the hexagon shrunk inward by `margin`? The inset of a regular hexagon
# is a smaller one with the apothem reduced by margin. BoardGrid uses this to keep
# tiles clear of the path band. Three side-normal constraints (at 90/30/150 degrees)
# collapse to two tests using |x|,|y|.
static func point_inside(p: Vector2, margin: float) -> bool:
	var apo := apothem() - margin
	if apo <= 0.0:
		return false
	var qx := absf(p.x)
	var qy := absf(p.y)
	return qy <= apo and 0.8660254 * qx + 0.5 * qy <= apo

static func pos_to_xy(d: float) -> Vector2:
	_ensure()
	var dist := fposmod(d, _perim)
	var n := _ring.size()
	var i := 0
	while i + 1 < n and _cum[i + 1] <= dist:
		i += 1
	var a := _ring[i]
	var b := _ring[(i + 1) % n]
	var seg_len := a.distance_to(b)
	var t := (dist - _cum[i]) / seg_len if seg_len > 0.0 else 0.0
	return a.lerp(b, t)

# Nearest point on the perimeter to an arbitrary point, as a perimeter distance.
# Used to snap placement and hit-testing to the track.
static func nearest_pos(p: Vector2) -> float:
	_ensure()
	var best_d := 0.0
	var best_sq := INF
	var n := _ring.size()
	for i in n:
		var a := _ring[i]
		var ab := _ring[(i + 1) % n] - a
		var len_sq := ab.length_squared()
		var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0) if len_sq > 0.0 else 0.0
		var point := a + ab * t
		var sq := p.distance_squared_to(point)
		if sq < best_sq:
			best_sq = sq
			best_d = _cum[i] + t * sqrt(len_sq)
	return best_d

# Which arcs of the perimeter a range circle centered at `center` with radius
# `radius` covers. For perpendicular distance `perp` from a segment, the covered
# chord half-length is sqrt(radius^2 - perp^2) when radius > perp, and nothing
# otherwise (§6). Returns merged [start, end] intervals in perimeter space; coverage
# spanning a vertex merges into one interval. A wrap across the origin is left as two
# intervals, which targeting tests independently.
static func coverage_intervals(center: Vector2, radius: float) -> Array[Vector2]:
	_ensure()
	var raw: Array[Vector2] = []
	var n := _ring.size()
	for i in n:
		var a := _ring[i]
		var ab := _ring[(i + 1) % n] - a
		var seg_len := ab.length()
		if seg_len <= 0.0:
			continue
		var dir := ab / seg_len
		var v := center - a
		var along := v.dot(dir)
		var perp := (v - dir * along).length()
		if radius <= perp:
			continue
		var half := sqrt(radius * radius - perp * perp)
		var lo: float = clampf(along - half, 0.0, seg_len)
		var hi: float = clampf(along + half, 0.0, seg_len)
		if hi <= lo:
			continue
		raw.append(Vector2(_cum[i] + lo, _cum[i] + hi))
	return _merge_intervals(raw)

# The bucket a perimeter distance falls in. Each tick, every enemy is bucketed by
# this; each unit stores the buckets its coverage touches, so targeting scans only
# those buckets before the precise interval test (§6).
static func bucket_of(d: float) -> int:
	return int(fposmod(d, perimeter()) / bucket_size())

# The set of bucket indices a coverage interval list touches, deduplicated and
# sorted. Computed once per placement and cached on Unit.buckets.
static func buckets_for_intervals(intervals: Array[Vector2]) -> PackedInt32Array:
	var bs := bucket_size()
	var seen: Dictionary = {}
	var result := PackedInt32Array()
	for interval in intervals:
		var first := int(interval.x / bs)
		var last := int((interval.y - 0.0001) / bs)
		for b in range(first, last + 1):
			var idx := ((b % BUCKET_COUNT) + BUCKET_COUNT) % BUCKET_COUNT
			if not seen.has(idx):
				seen[idx] = true
				result.append(idx)
	result.sort()
	return result

# --- helpers ---

# Sub-pixel: merge intervals that touch within half a unit, so coverage spanning a
# vertex reads as one interval and no hairline seam lets an enemy slip through.
const _MERGE_EPS := 0.5

static func _merge_intervals(raw: Array[Vector2]) -> Array[Vector2]:
	if raw.is_empty():
		return raw
	raw.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var merged: Array[Vector2] = []
	var cur := raw[0]
	for i in range(1, raw.size()):
		var nxt := raw[i]
		if nxt.x <= cur.y + _MERGE_EPS:
			cur.y = maxf(cur.y, nxt.y)
		else:
			merged.append(cur)
			cur = nxt
	merged.append(cur)
	return merged
