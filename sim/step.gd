class_name Sim
extends RefCounted

# The tick contract (ARCHITECTURE.md §3). Pure function of (world, commands,
# content). new_world builds the initial state; step mutates world in place and
# returns the events that occurred this tick. Nothing here may touch Node,
# get_tree(), Input, OS, Time, or Engine — the balance runner loads this with no
# scene tree and crashes on the first accidental reference (§2, §10).

static func new_world(seed_value: int, content: Content) -> World:
	var world := World.new()
	world.seed_value = seed_value
	world.rng = Rng.make_streams(seed_value)
	world.alive_cap = content.alive_cap
	world.gold = content.starting_gold
	# Kick straight into wave 1 when the content defines waves. A pre-wave build-phase
	# intermission lands with buy/place (M1 step 5) — until commands exist it would be
	# an empty pause. Empty content (pure-subsystem tests) stays in INTERMISSION with
	# no auto-spawn.
	if not content.waves.is_empty():
		world.phase = World.Phase.COMBAT
		world.wave = 1
		world.wave_timer = 0
		var first: WaveDef = content.waves[0]
		world.spawn_corner = first.spawn_corner
		world.direction = first.direction
	return world

# System order is part of the spec (§4). Steps land as they are built; the order
# below is fixed so replays stay valid.
static func step(world: World, commands: Array[Command], content: Content = null) -> Array[SimEvent]:
	var events: Array[SimEvent] = []
	# 1. Ingest commands           (buy/place/move/sell + debug spawn; M1 step 5)
	Ingest.run(world, commands, content, events)
	# 2. Spawn                     (time-based wave scheduler; no-ops without content)
	Spawn.run(world, content, events)
	# 3. Movement
	Movement.run(world)
	# 4. Rebuild buckets
	Buckets.rebuild(world)
	# 5. Targeting
	Targeting.run(world)
	# 6. Mana / auto-attack        (mana accrual: M2; auto-attack fires now)
	Combat.run(world, events)
	# 7. Abilities                 (M2)
	# 8. Projectiles
	Projectiles.run(world, events)
	# 9. Status effects            (M2)
	# 10. Deaths                   (remove + pay kill-gold + alive_count--; M1 step 4)
	Deaths.run(world, events)
	# 11. Win / loss               (alive-cap loss / final-wave win -> phase OVER; M1 step 6)
	Outcome.run(world, content, events)
	world.tick += 1
	return events
