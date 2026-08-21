class_name Enemy
extends RefCounted

# ARCHITECTURE.md §5. Position is a single float along the perimeter; the map is
# one function (§6).

var id: int = 0
var type_id: StringName = &""
var path_pos: float = 0.0               # 0 .. Path.PERIMETER
var prev_path_pos: float = 0.0          # for render interpolation
var lap: int = 0
var hp: float = 0.0
var max_hp: float = 0.0
var speed: float = 0.0                  # perimeter units per tick
var gold: int = 0                       # kill reward, stamped from EnemyType at spawn (M4 per-lap scaling recomputes)
var statuses: Array = []                # Array[Status] — Status type lands in M2

# Save/replay serialization (ARCHITECTURE.md §10). `statuses` is empty in M1 (Status is
# M2), so it is omitted; add it here when that system lands.
func to_dict() -> Dictionary:
	return {
		"id": id, "type_id": String(type_id), "path_pos": path_pos,
		"prev_path_pos": prev_path_pos, "lap": lap, "hp": hp, "max_hp": max_hp,
		"speed": speed, "gold": gold,
	}

static func from_dict(d: Dictionary) -> Enemy:
	var e := Enemy.new()
	e.id = int(d.get("id", 0))
	e.type_id = StringName(d.get("type_id", ""))
	e.path_pos = d.get("path_pos", 0.0)
	e.prev_path_pos = d.get("prev_path_pos", 0.0)
	e.lap = int(d.get("lap", 0))
	e.hp = d.get("hp", 0.0)
	e.max_hp = d.get("max_hp", 0.0)
	e.speed = d.get("speed", 0.0)
	e.gold = int(d.get("gold", 0))
	return e
