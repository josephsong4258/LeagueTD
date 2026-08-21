extends Node2D

# One pooled projectile sprite (ARCHITECTURE.md §9). Projectiles fly in straight
# lines, so unlike enemies a direct Vector2 lerp between prev_pos and pos is
# correct — there are no corners to cut. interp_pos returns the flat sim point; main
# projects it onto the isometric board to match the ground and pieces.

const _RADIUS := 5.0
const _COLOR := Color(1.0, 0.9, 0.5)

func interp_pos(projectile: Projectile, alpha: float) -> Vector2:
	queue_redraw()
	return projectile.prev_pos.lerp(projectile.pos, alpha)

func _draw() -> void:
	draw_circle(Vector2.ZERO, _RADIUS, _COLOR)
