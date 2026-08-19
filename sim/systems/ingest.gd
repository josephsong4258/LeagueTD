class_name Ingest
extends RefCounted

# ARCHITECTURE.md §4 step 1. Validate commands against current state and apply
# economy/board changes at the top of the tick. Invalid or unrecognized commands
# are dropped, never asserted (§4) — a stale command from a laggy client must not
# crash the sim.
#
# M0 handles only the debug spawn. The economy and board commands (buy, place,
# move, sell, equip, choose reward, start wave) land with M1.

static func run(world: World, commands: Array[Command], events: Array[SimEvent]) -> void:
	for command in commands:
		match command.kind:
			Command.Kind.DEBUG_SPAWN_ENEMY:
				_spawn_debug_enemy(world, command as DebugSpawnEnemy, events)
			_:
				pass  # M1 command handlers; unknown kinds are dropped by design.

static func _spawn_debug_enemy(world: World, command: DebugSpawnEnemy, events: Array[SimEvent]) -> void:
	if command == null:
		return
	var enemy := Enemy.new()
	enemy.id = world.next_id()
	enemy.type_id = command.type_id
	enemy.path_pos = command.path_pos
	enemy.prev_path_pos = command.path_pos
	enemy.hp = command.hp
	enemy.max_hp = command.hp
	enemy.speed = command.speed
	world.enemies.append(enemy)
	events.append(EnemySpawned.new(enemy.id, enemy.type_id, enemy.path_pos))
