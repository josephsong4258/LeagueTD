extends Node2D

# Draws the square loop once, in sim space (ARCHITECTURE.md §6, §9). The parent
# board Node2D handles the scale/translate to screen, so everything here is in raw
# perimeter coordinates. Static: the track never changes during a run.

const _TRACK_COLOR := Color(0.32, 0.36, 0.44)
const _TRACK_WIDTH := 6.0
const _SPAWN_COLOR := Color(0.90, 0.75, 0.30)

func _draw() -> void:
	var corners := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(Path.SIDE, 0.0),
		Vector2(Path.SIDE, Path.SIDE),
		Vector2(0.0, Path.SIDE),
		Vector2(0.0, 0.0),
	])
	draw_polyline(corners, _TRACK_COLOR, _TRACK_WIDTH, true)
	# Spawn corner marker (top-left, perimeter 0). Rotating corners land in M4.
	draw_circle(Vector2.ZERO, 14.0, _SPAWN_COLOR)
