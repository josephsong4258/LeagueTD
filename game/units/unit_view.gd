extends Node2D

# A deployed unit marker (ARCHITECTURE.md §9). Units don't move once placed, so this
# is static — position is set once from Unit.pos. The board grid, drag-to-place, and
# real hero art land in M1/M2; this is just enough to see who is shooting.

const _RADIUS := 16.0
const _COLOR := Color(0.4, 0.55, 0.95)
const _RING := Color(0.8, 0.85, 1.0)

func _draw() -> void:
	draw_circle(Vector2.ZERO, _RADIUS, _COLOR)
	draw_arc(Vector2.ZERO, _RADIUS, 0.0, TAU, 24, _RING, 2.0, true)
