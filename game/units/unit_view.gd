extends Node2D

# A unit marker (ARCHITECTURE.md §9). One pooled instance per live unit, on the bench
# or a board tile; main sets its position from UnitBought/UnitMoved events and moves it
# directly while it is being dragged. The draw itself is static — real hero art is M2.

const _RADIUS := 16.0
const _COLOR := Color(0.4, 0.55, 0.95)
const _RING := Color(0.8, 0.85, 1.0)

func _draw() -> void:
	draw_circle(Vector2.ZERO, _RADIUS, _COLOR)
	draw_arc(Vector2.ZERO, _RADIUS, 0.0, TAU, 24, _RING, 2.0, true)
