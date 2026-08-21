extends Node2D

# One pooled enemy sprite (ARCHITECTURE.md §9). Its screen position is interpolated
# between the sim's prev_path_pos and path_pos each frame. Crucially the *scalar*
# perimeter distance is interpolated first, then converted with Path.pos_to_xy —
# lerping the Vector2 directly would cut the corners of the square (§9). interp_pos
# returns the flat sim point; main projects it to the isometric board. The body is drawn
# UPRIGHT above its ground point with a squashed shadow, so it stands on the track.

const _RADIUS := 13.0
const _LIFT := 9.0                                 # how far the body stands above its ground point
const _SHADOW_SQUASH := 0.5
const _BODY_COLOR := Color(0.85, 0.35, 0.35)
const _SHADOW := Color(0.0, 0.0, 0.0, 0.22)
const _HP_BG := Color(0.0, 0.0, 0.0, 0.6)
const _HP_FG := Color(0.35, 0.85, 0.4)

var _hp_ratio: float = 1.0

# The interpolated flat sim position (main projects it). alpha is the fraction between
# the last two ticks (Engine.get_physics_interpolation_fraction).
func interp_pos(enemy: Enemy, alpha: float) -> Vector2:
	var d0 := enemy.prev_path_pos
	var d1 := enemy.path_pos
	# Unwrap across the origin so a lap boundary interpolates the short way, not
	# halfway around the map.
	var perim := Path.perimeter()
	if d0 - d1 > perim * 0.5:
		d1 += perim
	elif d1 - d0 > perim * 0.5:
		d1 -= perim
	var d: float = lerpf(d0, d1, alpha)
	_hp_ratio = clampf(enemy.hp / maxf(enemy.max_hp, 0.0001), 0.0, 1.0)
	queue_redraw()
	return Path.pos_to_xy(fposmod(d, perim))

func _draw() -> void:
	# Ground shadow at the foot, flattened to read as cast on the tilted plane.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, _SHADOW_SQUASH))
	draw_circle(Vector2.ZERO, _RADIUS * 0.85, _SHADOW)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var body := Vector2(0.0, -_LIFT)
	draw_circle(body, _RADIUS, _BODY_COLOR)
	var bar_w := _RADIUS * 2.0
	var bar_h := 4.0
	var top := body + Vector2(-_RADIUS, -_RADIUS - 8.0)
	draw_rect(Rect2(top, Vector2(bar_w, bar_h)), _HP_BG)
	draw_rect(Rect2(top, Vector2(bar_w * _hp_ratio, bar_h)), _HP_FG)
