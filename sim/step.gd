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
	return world

# System order is part of the spec (§4). Steps land as they are built; the order
# below is fixed so replays stay valid.
static func step(world: World, commands: Array[Command]) -> Array[SimEvent]:
	var events: Array[SimEvent] = []
	# 1. Ingest commands           (M0: debug spawn only; economy/board in M1)
	Ingest.run(world, commands, events)
	# 2. Spawn                     (M1 — wave scheduler; M0 spawns via ingest above)
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
	# 10. Deaths
	Deaths.run(world, events)
	# 11. Win / loss               (M1)
	world.tick += 1
	return events
