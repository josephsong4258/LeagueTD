extends Node2D

# One pooled projectile sprite (ARCHITECTURE.md §9). Projectiles fly in straight
# lines, so unlike enemies a direct Vector2 lerp between prev_pos and pos is
# correct — there are no corners to cut.

const _RADIUS := 5.0
const _COLOR := Color(1.0, 0.9, 0.5)

func update_interp(projectile: Projectile, alpha: float) -> void:
	position = projectile.prev_pos.lerp(projectile.pos, alpha)
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, _RADIUS, _COLOR)
