class_name ProjectileFired
extends SimEvent

# Emitted by Combat when a unit's auto-attack resolves and a projectile spawns
# (ARCHITECTURE.md §4 step 6/8). The renderer uses it to show a shot leaving the
# unit; it never diffs World to discover the projectile.

var projectile_id: int
var source_unit_id: int
var target_enemy_id: int

func _init(p_projectile_id: int, p_source_unit_id: int, p_target_enemy_id: int) -> void:
	super(SimEvent.Kind.PROJECTILE_FIRED)
	projectile_id = p_projectile_id
	source_unit_id = p_source_unit_id
	target_enemy_id = p_target_enemy_id
