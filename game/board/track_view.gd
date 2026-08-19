extends Node2D

# Draws the path as a terrain BAND, in sim space (ARCHITECTURE.md §6, §9). The parent
# board Node2D handles the scale/translate to screen. Enemies walk the centerline
# (Path's stadium ring); the band extends Path.TRACK_WIDTH/2 to either side of it.
# Static: the track never changes during a run.

const _FIELD_COLOR := Color(0.16, 0.18, 0.23)     # interior play-field, under the tiles
const _BAND_COLOR := Color(0.26, 0.28, 0.35)
const _CENTERLINE_COLOR := Color(0.38, 0.42, 0.50)
const _CENTERLINE_WIDTH := 2.0
const _SPAWN_COLOR := Color(0.90, 0.75, 0.30)

func _draw() -> void:
	var ring := Path.ring()
	# Fill the interior first so the area between the tiles and the track reads as the
	# play-field, not empty void. The ring polygon fills up to the centerline; the band
	# is then painted on top of its outer half.
	draw_colored_polygon(ring, _FIELD_COLOR)
	# The centerline ring, closed. Drawing it as a thick polyline paints the band; the
	# arena is convex so the rounded corners read smoothly at this chord resolution.
	var closed := PackedVector2Array(ring)
	closed.append(ring[0])
	draw_polyline(closed, _BAND_COLOR, Path.TRACK_WIDTH, true)
	draw_polyline(closed, _CENTERLINE_COLOR, _CENTERLINE_WIDTH, true)
	# Spawn point marker (perimeter 0, left end of the top edge). Rotating corners: M4.
	draw_circle(Path.pos_to_xy(0.0), 14.0, _SPAWN_COLOR)
