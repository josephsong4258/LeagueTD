extends Node2D

# Draws each deployed unit's range circle and the perimeter arcs it actually
# covers, straight from Path.coverage_intervals — the same data targeting uses
# (ARCHITECTURE.md §6). Because the preview and the combat math share one function,
# the highlighted arc is exactly what the unit can shoot. Call queue_redraw() when
# placement changes; for M0 it is drawn once after the demo unit is deployed.

var world: World

const _RANGE_COLOR := Color(0.35, 0.65, 1.0, 0.15)
const _ARC_COLOR := Color(0.45, 0.80, 1.0, 0.85)
const _ARC_WIDTH := 5.0
const _ARC_SAMPLES := 24

func _draw() -> void:
	if world == null:
		return
	for unit in world.units:
		if unit.stats == null:
			continue
		draw_arc(unit.pos, unit.stats.attack_range, 0.0, TAU, 48, _RANGE_COLOR, 2.0, true)
		for interval in unit.coverage:
			var points := PackedVector2Array()
			for i in _ARC_SAMPLES + 1:
				var d: float = lerpf(interval.x, interval.y, float(i) / float(_ARC_SAMPLES))
				points.append(Path.pos_to_xy(d))
			draw_polyline(points, _ARC_COLOR, _ARC_WIDTH, true)
