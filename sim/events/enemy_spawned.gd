class_name EnemySpawned
extends SimEvent

# Emitted when an enemy enters the world (ARCHITECTURE.md §4 step 2). The renderer
# creates a pooled sprite from this event rather than diffing World to notice a new
# enemy (§4, §9). In M0 the source is a debug spawn command; M1 replaces it with
# the wave scheduler reading waves.json.

var enemy_id: int
var type_id: StringName
var path_pos: float

func _init(p_enemy_id: int, p_type_id: StringName, p_path_pos: float) -> void:
	super(SimEvent.Kind.ENEMY_SPAWNED)
	enemy_id = p_enemy_id
	type_id = p_type_id
	path_pos = p_path_pos
