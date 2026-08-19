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
	print("- Path.pos_to_xy")
	_check(Path.pos_to_xy(0.0).is_equal_approx(Vector2(0, 0)), "origin (top-left)")
	_check(Path.pos_to_xy(Path.SIDE).is_equal_approx(Vector2(Path.SIDE, 0)), "top-right corner")
	_check(Path.pos_to_xy(2.0 * Path.SIDE).is_equal_approx(Vector2(Path.SIDE, Path.SIDE)), "bottom-right corner")
	_check(Path.pos_to_xy(3.0 * Path.SIDE).is_equal_approx(Vector2(0, Path.SIDE)), "bottom-left corner")
	_check(Path.pos_to_xy(Path.PERIMETER).is_equal_approx(Vector2(0, 0)), "full lap wraps to origin")
	_check(Path.pos_to_xy(Path.SIDE * 0.5).is_equal_approx(Vector2(Path.SIDE * 0.5, 0)), "mid top edge")

func _test_nearest_pos() -> void:
	print("- Path.nearest_pos")
	for d: float in [0.0, 123.4, Path.SIDE + 50.0, 2.5 * Path.SIDE, 3.9 * Path.SIDE]:
		var xy := Path.pos_to_xy(d)
		var back := Path.nearest_pos(xy)
		var same := _approx(fposmod(back, Path.PERIMETER), fposmod(d, Path.PERIMETER), 0.01)
		_check(same, "roundtrip d=%.1f" % d)
	# A point outside the loop projects onto the nearest edge.
	_check(_approx(Path.nearest_pos(Vector2(Path.SIDE * 0.5, -100.0)), Path.SIDE * 0.5, 0.01),
		"point above top edge projects straight down")

func _test_coverage_and_buckets() -> void:
	print("- Path.coverage_intervals / buckets")
	# Unit just inside the top edge, mid-span: a symmetric arc around its projection.
	var center := Vector2(Path.SIDE * 0.5, 60.0)
	var radius := 100.0
	var intervals := Path.coverage_intervals(center, radius)
	_check(intervals.size() == 1, "one interval on one edge")
	if intervals.size() == 1:
		var half := sqrt(radius * radius - 60.0 * 60.0)
		_check(_approx(intervals[0].x, Path.SIDE * 0.5 - half, 0.01), "interval start")
		_check(_approx(intervals[0].y, Path.SIDE * 0.5 + half, 0.01), "interval end")
	# Out of reach of the track -> no coverage.
	_check(Path.coverage_intervals(Vector2(Path.SIDE * 0.5, 400.0), 50.0).is_empty(),
		"no coverage when the track is out of range")
	# Near a corner: arcs on two adjacent edges merge into one interval.
	var corner := Path.coverage_intervals(Vector2(Path.SIDE - 20.0, 20.0), 120.0)
	_check(corner.size() == 1, "adjacent edges merge across a corner")
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
	var steps_for_a_lap := int(ceil(Path.PERIMETER / enemy.speed)) + 1
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

func _test_buckets() -> void:
	print("- Buckets.rebuild")
	var world := Sim.new_world(1, Content.new())
	var a := _spawn_enemy(world, 10.0, 10.0)                       # bucket 0
	var b := _spawn_enemy(world, Path.BUCKET_SIZE + 5.0, 10.0)     # bucket 1
	var c := _spawn_enemy(world, Path.PERIMETER - 1.0, 10.0)       # last bucket
	Buckets.rebuild(world)
	_check(world.buckets.size() == Path.BUCKET_COUNT, "allocates BUCKET_COUNT buckets")
	_check(Array(world.buckets[0]) == [0], "enemy a lands in bucket 0")
	_check(Array(world.buckets[1]) == [1], "enemy b lands in bucket 1")
	_check(Array(world.buckets[Path.BUCKET_COUNT - 1]) == [2], "enemy c lands in the last bucket")
	# A second rebuild must clear the previous contents, not accumulate.
	a.path_pos = Path.BUCKET_SIZE + 1.0                            # move a into bucket 1
	Buckets.rebuild(world)
	_check(world.buckets[0].is_empty(), "moved-out bucket is cleared on rebuild")
	_check(Array(world.buckets[1]) == [0, 1], "rebuild reflects new positions in array order")

func _test_targeting() -> void:
	print("- Targeting.run (first / furthest-along policy)")
	var world := Sim.new_world(1, Content.new())
	# Unit just inside the top edge at mid-span, range 100 -> a ~150-wide arc.
	var unit := _deploy_unit(world, Vector2(Path.SIDE * 0.5, 60.0), 5.0, 1.0, 100.0, 400.0, 0)
	var in_near := _spawn_enemy(world, Path.SIDE * 0.5 - 40.0, 10.0)
	var in_far := _spawn_enemy(world, Path.SIDE * 0.5 + 40.0, 10.0)   # further along
	var out := _spawn_enemy(world, Path.SIDE * 0.5 + 400.0, 10.0)     # out of range
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
	_deploy_unit(world, Vector2(Path.SIDE * 0.5, 60.0), 5.0, 30.0, 100.0, 4000.0, 0)
	var enemy := _spawn_enemy(world, Path.SIDE * 0.5, 10.0, 0.0)
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
