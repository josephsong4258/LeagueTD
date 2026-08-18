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
const Content := preload("res://sim/content.gd")
const Sim := preload("res://sim/step.gd")

var _failures: int = 0

func _initialize() -> void:
	print("== league-td sim checks ==")
	_test_pos_to_xy()
	_test_nearest_pos()
	_test_coverage_and_buckets()
	_test_tick_and_movement()
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
