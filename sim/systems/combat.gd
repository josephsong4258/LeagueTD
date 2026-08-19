class_name Combat
extends RefCounted

# ARCHITECTURE.md §4 step 6. Auto-attack resolution: each ready unit with a target
# spawns a projectile aimed at it. This is where mana will accrue in M2 ("fixed
# gain per auto-attack" — §5); for M0 it only fires. Units iterate in tile order.
#
# Cooldown is measured in ticks: 30 Hz / attack_speed (attacks per second). It
# ticks down each frame and is topped up by one full period on fire, so cadence
# stays exact regardless of when a target appears.

static func run(world: World, events: Array[SimEvent]) -> void:
	for unit in world.units:
		var stats := unit.stats
		if stats == null or stats.attack_speed <= 0.0:
			continue
		unit.attack_cooldown -= 1.0
		if unit.attack_cooldown > 0.0:
			continue
		if unit.target_enemy_id == 0:
			# Ready but nothing to shoot: hold at 0 so the next target fires at
			# once, without the cooldown drifting arbitrarily negative while idle.
			unit.attack_cooldown = 0.0
			continue
		var target := _find_enemy(world, unit.target_enemy_id)
		if target == null:
			unit.target_enemy_id = 0
			unit.attack_cooldown = 0.0
			continue
		var projectile := Projectile.new()
		projectile.id = world.next_id()
		projectile.source_unit_id = unit.id
		projectile.target_enemy_id = target.id
		projectile.pos = unit.pos
		projectile.prev_pos = unit.pos
		projectile.speed = stats.projectile_speed
		projectile.damage = stats.damage
		world.projectiles.append(projectile)
		unit.attack_cooldown += 30.0 / stats.attack_speed
		events.append(ProjectileFired.new(projectile.id, unit.id, target.id))

static func _find_enemy(world: World, enemy_id: int) -> Enemy:
	for enemy in world.enemies:
		if enemy.id == enemy_id:
			return enemy
	return null
