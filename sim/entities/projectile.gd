class_name Projectile
extends RefCounted

# ARCHITECTURE.md §5 / §4 step 8. In-flight shot; advances, tests, resolves hits.

var id: int = 0
var source_unit_id: int = 0
var target_enemy_id: int = 0
var pos: Vector2 = Vector2.ZERO
var prev_pos: Vector2 = Vector2.ZERO    # for render interpolation
var speed: float = 0.0                  # world units per tick
var damage: float = 0.0

# Save/replay serialization (ARCHITECTURE.md §10). Vector2 has no JSON form, so store it
# as a two-element array.
func to_dict() -> Dictionary:
	return {
		"id": id, "source_unit_id": source_unit_id, "target_enemy_id": target_enemy_id,
		"pos": [pos.x, pos.y], "prev_pos": [prev_pos.x, prev_pos.y],
		"speed": speed, "damage": damage,
	}

static func from_dict(d: Dictionary) -> Projectile:
	var p := Projectile.new()
	p.id = int(d.get("id", 0))
	p.source_unit_id = int(d.get("source_unit_id", 0))
	p.target_enemy_id = int(d.get("target_enemy_id", 0))
	var xy: Array = d.get("pos", [0.0, 0.0])
	p.pos = Vector2(xy[0], xy[1])
	var pxy: Array = d.get("prev_pos", [0.0, 0.0])
	p.prev_pos = Vector2(pxy[0], pxy[1])
	p.speed = d.get("speed", 0.0)
	p.damage = d.get("damage", 0.0)
	return p
