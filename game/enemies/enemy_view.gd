extends Node2D

# One pooled enemy sprite (ARCHITECTURE.md §9). Its screen position is interpolated
# between the sim's prev_path_pos and path_pos each frame. Crucially the *scalar*
# perimeter distance is interpolated first, then converted with Path.pos_to_xy —
# lerping the Vector2 directly would cut the corners of the square (§9).

const _RADIUS := 13.0
const _BODY_COLOR := Color(0.85, 0.35, 0.35)
const _HP_BG := Color(0.0, 0.0, 0.0, 0.6)
const _HP_FG := Color(0.35, 0.85, 0.4)

var _hp_ratio: float = 1.0

# Reposition from interpolated sim state. alpha is the fraction between the last two
# ticks (Engine.get_physics_interpolation_fraction).
func update_interp(enemy: Enemy, alpha: float) -> void:
	var d0 := enemy.prev_path_pos
	var d1 := enemy.path_pos
	# Unwrap across the origin so a lap boundary interpolates the short way, not
	# halfway around the map.
	if d0 - d1 > Path.PERIMETER * 0.5:
		d1 += Path.PERIMETER
	elif d1 - d0 > Path.PERIMETER * 0.5:
		d1 -= Path.PERIMETER
	var d: float = lerpf(d0, d1, alpha)
	position = Path.pos_to_xy(fposmod(d, Path.PERIMETER))
	_hp_ratio = clampf(enemy.hp / maxf(enemy.max_hp, 0.0001), 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, _RADIUS, _BODY_COLOR)
	var bar_w := _RADIUS * 2.0
	var bar_h := 4.0
	var top := Vector2(-_RADIUS, -_RADIUS - 8.0)
	draw_rect(Rect2(top, Vector2(bar_w, bar_h)), _HP_BG)
	draw_rect(Rect2(top, Vector2(bar_w * _hp_ratio, bar_h)), _HP_FG)
