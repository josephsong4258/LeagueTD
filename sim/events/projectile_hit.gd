class_name ProjectileHit
extends SimEvent

# Emitted by Projectiles when a shot reaches its target (ARCHITECTURE.md §4 step
# 8). Carries the impact point so the renderer can play a fire-and-forget hit
# flash with no state in World (§9).

var projectile_id: int
var enemy_id: int
var pos: Vector2

func _init(p_projectile_id: int, p_enemy_id: int, p_pos: Vector2) -> void:
	super(SimEvent.Kind.PROJECTILE_HIT)
	projectile_id = p_projectile_id
	enemy_id = p_enemy_id
	pos = p_pos
