extends SceneTree

# Headless entry point (ARCHITECTURE.md §10). Run with:
#   godot --headless --path . --script res://runner/balance.gd
#
# Two jobs today:
#   1. Purity guard — this loads and steps sim/ with no scene tree. Any accidental
#      Node / get_tree() / Input / OS / Time / Engine reference in sim/ crashes the
#      run (§2). If this script completes, sim/ stayed pure.
#   2. Unit tests for the path math and the tick contract, until a scripted bot
#      policy and CSV output land in M5.

const Path := preload("res://sim/path.gd")
const World := preload("res://sim/world.gd")
const Enemy := preload("res://sim/entities/enemy.gd")
const Unit := preload("res://sim/entities/unit.gd")
const StatBlock := preload("res://sim/entities/statblock.gd")
const Content := preload("res://sim/content.gd")
const Sim := preload("res://sim/step.gd")
const Buckets := preload("res://sim/systems/buckets.gd")
const Targeting := preload("res://sim/systems/targeting.gd")

var _failures: int = 0

func _initialize() -> void:
	print("== league-td sim checks ==")
	_test_pos_to_xy()
	_test_nearest_pos()
	_test_coverage_and_buckets()
	_test_tick_and_movement()
	_test_content_loader()
	_test_board_grid()
	_test_ingest_spawn()
	_test_wave_scheduler()
	_test_buckets()
	_test_targeting()
	_test_combat_loop()
	_test_determinism()
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		printerr("%d CHECK(S) FAILED" % _failures)
		quit(1)

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		printerr("  FAIL ", label)

func _approx(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) <= eps

func _test_pos_to_xy() -> void:
	print("- Path.pos_to_xy (hexagon ring)")
	var r := Path.circumradius()
	var a := Path.apothem()
	# Six equal sides of length r; vertex i sits at perimeter distance i*r. Positions
	# carry a little accumulated-float error along the ring, so compare within 0.5px.
	_check(_approx(Path.perimeter(), 6.0 * r, 0.5), "perimeter is six equal sides")
	_check(Path.pos_to_xy(0.0).distance_to(Vector2(r, 0.0)) < 0.5, "origin (right vertex)")
	_check(Path.pos_to_xy(3.0 * r).distance_to(Vector2(-r, 0.0)) < 0.5, "half a lap is the opposite vertex")
	# The top edge runs between vertices 4 and 5; its mid-span is straight above center.
	_check(Path.pos_to_xy(4.5 * r).distance_to(Vector2(0.0, -a)) < 0.5, "mid top edge")
	_check(Path.pos_to_xy(Path.perimeter()).distance_to(Vector2(r, 0.0)) < 0.5, "full lap wraps to origin")

func _test_nearest_pos() -> void:
	print("- Path.nearest_pos")
	var perim := Path.perimeter()
	var r := Path.circumradius()
	var a := Path.apothem()
	for d: float in [0.0, 0.7 * r, 3.0 * r, 4.5 * r, perim * 0.5, perim * 0.9]:
		var xy := Path.pos_to_xy(d)
		var back := Path.nearest_pos(xy)
		var same := _approx(fposmod(back, perim), fposmod(d, perim), 0.5)
		_check(same, "roundtrip d=%.1f" % d)
	# A point above the top edge projects straight down onto its mid-span (d = 4.5r).
	_check(_approx(Path.nearest_pos(Vector2(0.0, -a - 100.0)), 4.5 * r, 0.5),
		"point above top edge projects straight down")

func _test_coverage_and_buckets() -> void:
	print("- Path.coverage_intervals / buckets")
	var r := Path.circumradius()
	var a := Path.apothem()
	var mid := 4.5 * r                          # perimeter distance of the mid top edge
	# Unit just inside the top edge, mid-span: a symmetric arc around its projection.
	var perp := 60.0
	var center := Vector2(0.0, -a + perp)
	var radius := 100.0
	var intervals := Path.coverage_intervals(center, radius)
	_check(intervals.size() == 1, "one interval on the top edge")
	if intervals.size() == 1:
		var half := sqrt(radius * radius - perp * perp)
		_check(_approx(intervals[0].x, mid - half, 0.5), "interval start")
		_check(_approx(intervals[0].y, mid + half, 0.5), "interval end")
	# Sitting at the arena center, the track is far on every side -> no coverage.
	_check(Path.coverage_intervals(Vector2.ZERO, 50.0).is_empty(),
		"no coverage when the track is out of range")
	# Near a vertex (here vertex 5, at d = 5r) the two edges meeting there are
	# contiguous in perimeter space, so coverage spanning the vertex is one interval.
	var vertex5 := Vector2(0.5 * r, -a)
	var corner := Path.coverage_intervals(vertex5 * 0.8, 170.0)
	var spans := false
	for iv in corner:
		if iv.x < 5.0 * r and iv.y > 5.0 * r:
			spans = true
	_check(spans, "coverage merges across a vertex into one interval")
	# Buckets touched by the top-edge coverage are all in range.
	var buckets := Path.buckets_for_intervals(intervals)
	_check(buckets.size() >= 1, "coverage touches at least one bucket")
	var all_in_range := true
	for b in buckets:
		if b < 0 or b >= Path.BUCKET_COUNT:
			all_in_range = false
	_check(all_in_range, "every bucket index is in [0, BUCKET_COUNT)")

func _test_tick_and_movement() -> void:
	print("- Sim.step movement + lap counter")
	var content := Content.new()
	var world := Sim.new_world(8837421, content)
	var enemy := Enemy.new()
	enemy.id = world.next_id()
	enemy.type_id = &"runner"
	enemy.speed = 3.0
	enemy.hp = 10.0
	enemy.max_hp = 10.0
	world.enemies.append(enemy)
	var no_commands: Array[Command] = []
	for i in 10:
		Sim.step(world, no_commands)
	_check(world.tick == 10, "tick advanced by 10")
	_check(_approx(enemy.path_pos, 30.0), "enemy advanced speed * ticks")
	_check(_approx(enemy.prev_path_pos, 27.0), "prev_path_pos trails by one tick")
	var lap_before := enemy.lap
	var steps_for_a_lap := int(ceil(Path.perimeter() / enemy.speed)) + 1
	for i in steps_for_a_lap:
		Sim.step(world, no_commands)
	_check(enemy.lap == lap_before + 1, "lap increments exactly once on wrap")

func _spawn_enemy(world: World, path_pos: float, hp: float, speed: float = 0.0) -> Enemy:
	var enemy := Enemy.new()
	enemy.id = world.next_id()
	enemy.type_id = &"runner"
	enemy.path_pos = path_pos
	enemy.prev_path_pos = path_pos
	enemy.hp = hp
	enemy.max_hp = hp
	enemy.speed = speed
	world.enemies.append(enemy)
	return enemy

func _deploy_unit(world: World, unit_pos: Vector2, damage: float, attack_speed: float,
		attack_range: float, projectile_speed: float, tile: int) -> Unit:
	var unit := Unit.new()
	unit.id = world.next_id()
	unit.hero_id = &"test"
	unit.tile = tile
	unit.pos = unit_pos
	var stats := StatBlock.new()
	stats.damage = damage
	stats.attack_speed = attack_speed
	stats.attack_range = attack_range
	stats.projectile_speed = projectile_speed
	unit.stats = stats
	# Placement math (M1 will do this when a PLACE_UNIT command is ingested).
	unit.coverage = Path.coverage_intervals(unit_pos, attack_range)
	unit.buckets = Path.buckets_for_intervals(unit.coverage)
	world.insert_unit_sorted(unit)
	return unit

func _test_board_grid() -> void:
	print("- BoardGrid (hex grid filling the stadium)")
	var count := BoardGrid.tile_count()
	print("    tile_count = %d" % count)
	_check(count > 40 and count < 200, "reasonable tile count (%d)" % count)
	# Every tile center sits clear of the path band (inside the stadium inset by the
	# band half-width). point_inside is the exact stadium test the grid builds from.
	var band := Path.TRACK_WIDTH * 0.5
	var all_clear := true
	for i in count:
		if not Path.point_inside(BoardGrid.tile_center(i), band):
			all_clear = false
	_check(all_clear, "every tile center is inside the arena and clear of the path band")
	# No two tile centers coincide.
	var unique := true
	for i in count:
		for j in range(i + 1, count):
			if BoardGrid.tile_center(i).distance_to(BoardGrid.tile_center(j)) < 1.0:
				unique = false
	_check(unique, "no duplicate tile centers")
	# Symmetric fill: a stadium is symmetric about both axes, so every tile's mirror
	# across the vertical axis must also be a tile.
	var has_mirror := true
	for i in count:
		var c := BoardGrid.tile_center(i)
		var mirror := Vector2(-c.x, c.y)
		var nearest := BoardGrid.tile_center(BoardGrid.nearest_tile(mirror))
		if nearest.distance_to(mirror) > 1.0:
			has_mirror = false
	_check(has_mirror, "grid is mirror-symmetric across the vertical axis")
	# nearest_tile round-trips: a point at a tile's center returns that tile.
	if count > 0:
		var mid := count / 2
		_check(BoardGrid.nearest_tile(BoardGrid.tile_center(mid)) == mid, "nearest_tile finds an exact center")
	# Cached: two calls return the same list length.
	_check(BoardGrid.tiles().size() == count, "tiles() is stable across calls")
	# Hex hit-test: center is inside, the neighbouring cell's center is not.
	_check(BoardGrid.point_in_tile(Vector2.ZERO), "hex contains its center")
	_check(not BoardGrid.point_in_tile(Vector2(sqrt(3.0) * BoardGrid.hex_size(), 0.0)), "hex excludes the next cell's center")

func _test_content_loader() -> void:
	print("- ContentLoader (parse + validate content/*.json)")
	var content := ContentLoader.load_default()
	_check(content.load_errors.is_empty(),
		"content loads clean" if content.load_errors.is_empty() else "content errors: %s" % str(content.load_errors))
	_check(content.enemy_types.has(&"runner"), "runner enemy type present")
	_check(content.heroes.size() == 4, "four heroes in the roster")
	_check(content.waves.size() >= 1, "at least one wave defined")
	var runner: EnemyType = content.get_enemy_type(&"runner")
	_check(runner != null and runner.hp > 0.0, "runner has positive hp")
	var hero: HeroDef = content.get_hero(&"ashe")
	_check(hero != null and hero.attack_range > 0.0, "ashe looked up by id, has range")
	if hero != null:
		var stats := hero.to_statblock()
		_check(_approx(stats.attack_range, hero.attack_range), "to_statblock carries range")
	# Time-based waves carry a duration.
	_check(content.waves[0].duration_ticks > 0, "wave 1 has a positive duration")
	# Escalating price grows with purchases (§7).
	_check(content.unit_price(0) == content.unit_base_price, "first purchase is base price")
	_check(content.unit_price(5) > content.unit_price(0), "price escalates with purchases")
	# Validation catches a wave referencing an unknown enemy.
	var bad := ContentLoader.build(
		{"alive_cap": 200, "starting_gold": 0},
		{"runner": {"hp": 10, "speed": 1}},
		{"archer": {"damage": 1, "attack_speed": 1, "attack_range": 1, "projectile_speed": 1}},
		{"waves": [{"wave": 1, "groups": [{"type_id": "ghost", "count": 1, "interval_ticks": 1}]}]})
	_check(not bad.load_errors.is_empty(), "wave referencing unknown enemy is flagged")

func _test_ingest_spawn() -> void:
	print("- Ingest.run (debug spawn command -> ENEMY_SPAWNED)")
	var world := Sim.new_world(1, Content.new())
	var commands: Array[Command] = [DebugSpawnEnemy.new(&"runner", 12.0, 2.0, 0.0)]
	var events := Sim.step(world, commands)
	_check(world.enemies.size() == 1, "command adds one enemy to the world")
	_check(world.enemies[0].max_hp == 12.0, "enemy carries the commanded hp")
	var spawned := 0
	for event in events:
		if event.kind == SimEvent.Kind.ENEMY_SPAWNED:
			spawned += 1
	_check(spawned == 1, "ENEMY_SPAWNED emitted once")
	# An unrecognized command kind is dropped, never fatal (§4).
	var junk: Array[Command] = [Command.new(Command.Kind.START_WAVE)]
	var before := world.enemies.size()
	Sim.step(world, junk)
	_check(world.enemies.size() == before, "unhandled command kind is dropped without error")

func _test_wave_scheduler() -> void:
	print("- Spawn.run (time-based wave scheduler)")
	# Two short waves. Wave 1: 3 runners from t=0 every 2 ticks, spawned at corner 0.
	# Wave 2: 2 brutes from corner 1, starting delay 1, every 3 ticks. duration 10.
	var content := ContentLoader.build(
		{"alive_cap": 200, "starting_gold": 0},
		{"runner": {"hp": 10, "speed": 1}, "brute": {"hp": 50, "speed": 1}},
		{"archer": {"damage": 1, "attack_speed": 1, "attack_range": 1, "projectile_speed": 1}},
		{"wave_duration_ticks": 10, "spawn_corner": 0, "direction": 1, "waves": [
			{"wave": 1, "groups": [{"type_id": "runner", "count": 3, "interval_ticks": 2}]},
			{"wave": 2, "spawn_corner": 1,
				"groups": [{"type_id": "brute", "count": 2, "interval_ticks": 3, "delay_ticks": 1}]}
		]})
	_check(content.load_errors.is_empty(),
		"scheduler content loads clean" if content.load_errors.is_empty() else "errors: %s" % str(content.load_errors))
	var world := Sim.new_world(1, content)
	_check(world.phase == World.Phase.COMBAT, "new_world enters COMBAT when waves exist")
	_check(world.wave == 1, "starts on wave 1")
	var no_commands: Array[Command] = []
	# Wave 1 runs its 10-tick duration. runner group fires at wave_timer 0, 2, 4.
	var wave1_spawns := 0
	var first_spawn_pos := -1.0
	for i in 10:
		var events := Sim.step(world, no_commands, content)
		for e in events:
			if e.kind == SimEvent.Kind.ENEMY_SPAWNED:
				wave1_spawns += 1
				if first_spawn_pos < 0.0:
					first_spawn_pos = (e as EnemySpawned).path_pos
	_check(wave1_spawns == 3, "wave 1 spawns exactly `count` enemies (got %d)" % wave1_spawns)
	_check(_approx(first_spawn_pos, 0.0), "wave 1 enemies enter at corner 0 (path_pos 0)")
	_check(world.wave == 2, "auto-advances to wave 2 after duration_ticks")
	_check(world.wave_timer == 0, "wave_timer resets on advance")
	_check(world.spawn_corner == 1, "spawn_corner updates to the new wave's corner")
	var runner_hp_ok := true
	for enemy in world.enemies:
		if enemy.type_id == &"runner" and enemy.max_hp != 10.0:
			runner_hp_ok = false
	_check(runner_hp_ok, "spawned enemies carry hp from the enemy type")
	# Step through wave 2. brute group fires at wave_timer 1 and 4, at corner 1 (SIDE).
	var wave2_spawns := 0
	var brute_pos := -1.0
	for i in 10:
		var events := Sim.step(world, no_commands, content)
		for e in events:
			if e.kind == SimEvent.Kind.ENEMY_SPAWNED:
				wave2_spawns += 1
				if (e as EnemySpawned).type_id == &"brute":
					brute_pos = (e as EnemySpawned).path_pos
	_check(wave2_spawns == 2, "wave 2 spawns its `count` after a delay (got %d)" % wave2_spawns)
	_check(_approx(brute_pos, Path.perimeter() / 4.0), "wave 2 enemies enter at corner 1 (quarter of the loop)")
	_check(world.wave == 3, "advances past the last wave; scheduler then idles")
	# No waves -> no auto-spawn, and the 2-arg call still type-checks (content defaults
	# to null), so the subsystem tests that pass no content are unaffected.
	var bare := Sim.new_world(1, Content.new())
	for i in 5:
		Sim.step(bare, no_commands)
	_check(bare.enemies.is_empty() and bare.phase == World.Phase.INTERMISSION,
		"empty content stays in INTERMISSION with no spawns")

func _test_buckets() -> void:
	print("- Buckets.rebuild")
	var world := Sim.new_world(1, Content.new())
	var bs := Path.bucket_size()
	var a := _spawn_enemy(world, 10.0, 10.0)                       # bucket 0
	var b := _spawn_enemy(world, bs + 5.0, 10.0)                   # bucket 1
	var c := _spawn_enemy(world, Path.perimeter() - 1.0, 10.0)     # last bucket
	Buckets.rebuild(world)
	_check(world.buckets.size() == Path.BUCKET_COUNT, "allocates BUCKET_COUNT buckets")
	_check(Array(world.buckets[0]) == [0], "enemy a lands in bucket 0")
	_check(Array(world.buckets[1]) == [1], "enemy b lands in bucket 1")
	_check(Array(world.buckets[Path.BUCKET_COUNT - 1]) == [2], "enemy c lands in the last bucket")
	# A second rebuild must clear the previous contents, not accumulate.
	a.path_pos = bs + 1.0                                          # move a into bucket 1
	Buckets.rebuild(world)
	_check(world.buckets[0].is_empty(), "moved-out bucket is cleared on rebuild")
	_check(Array(world.buckets[1]) == [0, 1], "rebuild reflects new positions in array order")

func _test_targeting() -> void:
	print("- Targeting.run (first / furthest-along policy)")
	var world := Sim.new_world(1, Content.new())
	var mid := 4.5 * Path.circumradius()                             # mid top edge
	# Unit just inside the top edge at mid-span, range 100 -> a ~150-wide arc.
	var unit := _deploy_unit(world, Vector2(0.0, -Path.apothem() + 60.0), 5.0, 1.0, 100.0, 400.0, 0)
	var in_near := _spawn_enemy(world, mid - 40.0, 10.0)
	var in_far := _spawn_enemy(world, mid + 40.0, 10.0)              # further along
	var out := _spawn_enemy(world, mid + 400.0, 10.0)               # out of range
	Buckets.rebuild(world)
	Targeting.run(world)
	_check(unit.target_enemy_id == in_far.id, "targets the furthest-along enemy in range")
	# Remove the far one; the near one becomes the only candidate.
	world.enemies.erase(in_far)
	Buckets.rebuild(world)
	Targeting.run(world)
	_check(unit.target_enemy_id == in_near.id, "falls back to the remaining in-range enemy")
	# Out-of-range only -> no target.
	world.enemies = [out] as Array[Enemy]
	Buckets.rebuild(world)
	Targeting.run(world)
	_check(unit.target_enemy_id == 0, "no target when every enemy is out of coverage")

func _test_combat_loop() -> void:
	print("- Sim.step combat loop (fire -> hit -> damage -> death)")
	var world := Sim.new_world(1, Content.new())
	# One shot per tick (attack_speed 30 at 30 Hz), fast projectile so it hits the
	# same tick it is fired. Enemy is stationary and takes two 5-damage hits.
	_deploy_unit(world, Vector2(0.0, -Path.apothem() + 60.0), 5.0, 30.0, 100.0, 4000.0, 0)
	var enemy := _spawn_enemy(world, 4.5 * Path.circumradius(), 10.0, 0.0)
	var enemy_id := enemy.id
	var no_commands: Array[Command] = []
	var fired := 0
	var hits := 0
	var damaged := 0
	var died := 0
	var kill_tick := -1
	for i in 10:
		if world.enemies.is_empty():
			break
		var events := Sim.step(world, no_commands)
		for event in events:
			match event.kind:
				SimEvent.Kind.PROJECTILE_FIRED: fired += 1
				SimEvent.Kind.PROJECTILE_HIT: hits += 1
				SimEvent.Kind.ENEMY_DAMAGED: damaged += 1
				SimEvent.Kind.ENEMY_DIED:
					died += 1
					kill_tick = world.tick
	_check(fired == 2, "fires exactly twice to deal 10 damage (got %d)" % fired)
	_check(hits == 2, "both projectiles hit")
	_check(damaged == 2, "two damage events emitted")
	_check(died == 1, "enemy dies once")
	_check(kill_tick == 2, "enemy removed on tick 2 (got %d)" % kill_tick)
	_check(world.enemies.is_empty(), "dead enemy removed from world")
	_check(world.projectiles.is_empty(), "projectiles consumed on hit")
	# The death event must carry the right id for the renderer to despawn it.
	var last_events := Sim.step(world, no_commands)
	_check(last_events.is_empty(), "no events once the board is clear")
	_check(enemy_id != 0, "sanity: enemy had a real id")

func _test_determinism() -> void:
	print("- determinism")
	var a := _run_signature(8837421)
	var b := _run_signature(8837421)
	var c := _run_signature(999)
	_check(a == b, "same seed -> identical result")
	_check(a != c, "different seed -> different rng stream")

func _run_signature(seed_value: int) -> String:
	var content := Content.new()
	var world := Sim.new_world(seed_value, content)
	var no_commands: Array[Command] = []
	for i in 20:
		Sim.step(world, no_commands)
	# Draw from a named stream (allowed — the ban is on the *global* randi()).
	var stream: RandomNumberGenerator = world.rng[&"unit_purchase"]
	return "%d:%d" % [world.tick, stream.randi()]
