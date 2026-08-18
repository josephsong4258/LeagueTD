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
