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
var statuses: Array = []                # Array[Status] — Status type lands in M2
