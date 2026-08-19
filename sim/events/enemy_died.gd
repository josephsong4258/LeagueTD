class_name EnemyDied
extends SimEvent

# Emitted by Deaths when an enemy is removed at hp <= 0 (ARCHITECTURE.md §4 step
# 10). Carries the last path position so the renderer can despawn the sprite and
# place a death effect. Gold payout and alive_count bookkeeping land with the
# economy/win-loss systems in M1.

var enemy_id: int
var path_pos: float

func _init(p_enemy_id: int, p_path_pos: float) -> void:
	super(SimEvent.Kind.ENEMY_DIED)
	enemy_id = p_enemy_id
	path_pos = p_path_pos
