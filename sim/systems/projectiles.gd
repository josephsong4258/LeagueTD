class_name Projectiles
extends RefCounted

# ARCHITECTURE.md §4 step 8. In-flight shots home toward their target's current
# position, advancing by `speed` world units per tick. When the remaining distance
# is within one step the shot resolves: it snaps to the target, applies damage,
# and is consumed. A projectile whose target no longer exists is dropped without a
# hit (deaths happen at step 10, so this is the tick-boundary case of a target
# that died last tick). prev_pos is snapshotted for render interpolation (§9).

static func run(world: World, events: Array[SimEvent]) -> void:
	if world.projectiles.is_empty():
		return
	var by_id := {}
	for enemy in world.enemies:
		by_id[enemy.id] = enemy
	var survivors: Array[Projectile] = []
	for projectile in world.projectiles:
		var target: Enemy = by_id.get(projectile.target_enemy_id)
		if target == null:
			continue
		projectile.prev_pos = projectile.pos
		var target_xy := Path.pos_to_xy(target.path_pos)
		var to_target := target_xy - projectile.pos
		var dist := to_target.length()
		if dist <= projectile.speed or dist == 0.0:
			projectile.pos = target_xy
			target.hp -= projectile.damage
			events.append(ProjectileHit.new(projectile.id, target.id, target_xy))
			events.append(EnemyDamaged.new(target.id, projectile.damage, target.hp))
			# consumed: not carried into survivors
		else:
			projectile.pos += to_target / dist * projectile.speed
			survivors.append(projectile)
	world.projectiles = survivors
