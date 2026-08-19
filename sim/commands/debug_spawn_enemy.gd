class_name DebugSpawnEnemy
extends Command

# M0 dev-only command (ARCHITECTURE.md §4 step 1). Carries the enemy's stats so no
# balance numbers live in sim/ — the client sources them, M1 will source them from
# waves.json. Because it flows through the command channel like any other input, it
# is ingested by the sole mutator (step) and lands in the replay log for free.

var type_id: StringName
var hp: float
var speed: float
var path_pos: float

func _init(p_type_id: StringName, p_hp: float, p_speed: float, p_path_pos: float = 0.0) -> void:
	super(Command.Kind.DEBUG_SPAWN_ENEMY)
	type_id = p_type_id
	hp = p_hp
	speed = p_speed
	path_pos = p_path_pos
