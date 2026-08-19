class_name EnemyDied
extends SimEvent

# Emitted by Deaths when an enemy is removed at hp <= 0 (ARCHITECTURE.md §4 step
# 10). Carries the last path position so the renderer can despawn the sprite and
# place a death effect, and the gold reward Deaths just paid so the client can float
# a "+N" without re-deriving it from Content.

var enemy_id: int
var path_pos: float
var gold: int

func _init(p_enemy_id: int, p_path_pos: float, p_gold: int = 0) -> void:
	super(SimEvent.Kind.ENEMY_DIED)
	enemy_id = p_enemy_id
	path_pos = p_path_pos
	gold = p_gold
