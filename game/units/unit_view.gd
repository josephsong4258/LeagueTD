extends Node2D

# A unit marker (ARCHITECTURE.md §9). One pooled instance per live unit, on the bench
# or a board tile; main sets its position (projected onto the tilted plane) from
# UnitBought/UnitMoved events and moves it directly while it is being dragged. The token
# is drawn UPRIGHT above its ground point with a squashed shadow so it stands on the
# tabletop rather than lying flat. The draw itself is static — real hero art is M2.

const _RADIUS := 16.0
const _LIFT := 13.0                                # how far the token stands above its ground point
const _SHADOW_SQUASH := 0.5
const _COLOR := Color(0.4, 0.55, 0.95)
const _RING := Color(0.8, 0.85, 1.0)
const _SHADOW := Color(0.0, 0.0, 0.0, 0.25)

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, _SHADOW_SQUASH))
	draw_circle(Vector2.ZERO, _RADIUS * 0.9, _SHADOW)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var body := Vector2(0.0, -_LIFT)
	draw_circle(body, _RADIUS, _COLOR)
	draw_arc(body, _RADIUS, 0.0, TAU, 24, _RING, 2.0, true)
