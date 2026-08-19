extends Node2D

# M0 client root (ARCHITECTURE.md §9). This is the host: it owns the World, runs
# Sim.step at a fixed 30 Hz from _physics_process, and renders. The split is the
# whole point — this file may touch Node/Input/Time freely, but it only ever talks
# to the sim through commands in and events out. It never reaches into World to
# change state, and it creates/frees sprites from events, never by diffing.
#
# Scene setup: this script is attached to a Node2D that is the project's main
# scene. Everything below it is built in code, so the .tscn is just an empty root.

const EnemyView := preload("res://game/enemies/enemy_view.gd")
const ProjectileView := preload("res://game/projectiles/projectile_view.gd")
const TrackView := preload("res://game/board/track_view.gd")
const TilesView := preload("res://game/board/tiles_view.gd")
const CoverageView := preload("res://game/board/coverage_view.gd")
const UnitView := preload("res://game/units/unit_view.gd")
const Hud := preload("res://game/ui/hud.gd")

const _BOARD_PADDING := 80.0
const _SPEED_MULTIPLIER := 1          # game speed = extra step() calls, never time_scale (§9)

var world: World
var _content: Content
var _commands: Array[Command] = []

var _board: Node2D
var _hud: Hud
var _coverage_layer: CoverageView
var _unit_layer: Node2D
var _enemy_layer: Node2D
var _projectile_layer: Node2D

# id -> live view, plus free lists so nothing is instantiated during a wave (§9).
var _enemy_views: Dictionary = {}
var _projectile_views: Dictionary = {}
var _enemy_pool: Array[Node2D] = []
var _projectile_pool: Array[Node2D] = []

func _ready() -> void:
	Engine.physics_ticks_per_second = 30
	# Client-side seed; the sim's determinism is per-seed, and replays (M1/§10) will
	# pin this. Time is fine here — this is the host, not sim/.
	var seed_value := int(Time.get_unix_time_from_system())
	_content = ContentLoader.load_default()
	world = Sim.new_world(seed_value, _content)
	_build_layers()
	_deploy_demo_unit()
	_hud = Hud.new()
	_hud.world = world
	add_child(_hud)
	get_viewport().size_changed.connect(_layout_board)
	_layout_board()

func _build_layers() -> void:
	_board = Node2D.new()
	add_child(_board)
	_board.add_child(TrackView.new())
	_board.add_child(TilesView.new())
	_coverage_layer = CoverageView.new()
	_coverage_layer.world = world
	_board.add_child(_coverage_layer)
	_unit_layer = Node2D.new()
	_board.add_child(_unit_layer)
	_enemy_layer = Node2D.new()
	_board.add_child(_enemy_layer)
	_projectile_layer = Node2D.new()
	_board.add_child(_projectile_layer)

# Fit the stadium (centered on the origin) into the viewport with uniform scale.
func _layout_board() -> void:
	var vp := get_viewport_rect().size
	# The band overhangs the centerline ring by half its width; include it so the
	# outer edge of the terrain isn't clipped.
	var overhang := Path.TRACK_WIDTH * 0.5 + 24.0
	var bounds := Path.bounds()
	var world_size := bounds.size + Vector2(overhang, overhang) * 2.0
	var fit_scale := minf(
		(vp.x - 2.0 * _BOARD_PADDING) / world_size.x,
		(vp.y - 2.0 * _BOARD_PADDING) / world_size.y)
	_board.scale = Vector2(fit_scale, fit_scale)
	# The ring is centered on the origin, so centering the board on the viewport is
	# just translating to the middle.
	_board.position = vp * 0.5

func _deploy_demo_unit() -> void:
	var unit := Unit.new()
	unit.id = world.next_id()
	unit.hero_id = &"demo"
	# Snap onto a real hex near the top edge so placement is visible on the grid.
	var tile := BoardGrid.nearest_tile(Vector2(0.0, -Path.apothem() * 0.6))
	unit.tile = tile
	unit.pos = BoardGrid.tile_center(tile)
	var stats := StatBlock.new()
	stats.damage = 4.0
	stats.attack_speed = 1.5
	stats.attack_range = 240.0
	stats.projectile_speed = 16.0
	unit.stats = stats
	# Placement math (M1 does this on a PLACE_UNIT command).
	unit.coverage = Path.coverage_intervals(unit.pos, stats.attack_range)
	unit.buckets = Path.buckets_for_intervals(unit.coverage)
	world.insert_unit_sorted(unit)
	var view := UnitView.new()
	view.position = unit.pos
	_unit_layer.add_child(view)
	_coverage_layer.queue_redraw()

func _physics_process(_delta: float) -> void:
	for _i in _SPEED_MULTIPLIER:
		var events := Sim.step(world, _drain_commands(), _content)
		_handle_events(events)

func _drain_commands() -> Array[Command]:
	var out := _commands
	_commands = []
	return out

func _handle_events(events: Array[SimEvent]) -> void:
	for event in events:
		match event.kind:
			SimEvent.Kind.ENEMY_SPAWNED:
				_add_enemy_view((event as EnemySpawned).enemy_id)
			SimEvent.Kind.ENEMY_DIED:
				_remove_enemy_view((event as EnemyDied).enemy_id)
			SimEvent.Kind.PROJECTILE_FIRED:
				_add_projectile_view((event as ProjectileFired).projectile_id)
			SimEvent.Kind.PROJECTILE_HIT:
				_remove_projectile_view((event as ProjectileHit).projectile_id)

func _process(_delta: float) -> void:
	var alpha := Engine.get_physics_interpolation_fraction()
	var enemy_by_id := {}
	for enemy in world.enemies:
		enemy_by_id[enemy.id] = enemy
	for id in _enemy_views:
		var enemy: Enemy = enemy_by_id.get(id)
		if enemy != null:
			(_enemy_views[id] as EnemyView).update_interp(enemy, alpha)
	var proj_by_id := {}
	for projectile in world.projectiles:
		proj_by_id[projectile.id] = projectile
	for id in _projectile_views:
		var projectile: Projectile = proj_by_id.get(id)
		if projectile != null:
			(_projectile_views[id] as ProjectileView).update_interp(projectile, alpha)

# --- pooled view lifecycle ---

func _add_enemy_view(enemy_id: int) -> void:
	var view: Node2D
	if _enemy_pool.is_empty():
		view = EnemyView.new()
		_enemy_layer.add_child(view)
	else:
		view = _enemy_pool.pop_back()
		view.visible = true
	_enemy_views[enemy_id] = view

func _remove_enemy_view(enemy_id: int) -> void:
	if not _enemy_views.has(enemy_id):
		return
	var view: Node2D = _enemy_views[enemy_id]
	view.visible = false
	_enemy_pool.append(view)
	_enemy_views.erase(enemy_id)

func _add_projectile_view(projectile_id: int) -> void:
	var view: Node2D
	if _projectile_pool.is_empty():
		view = ProjectileView.new()
		_projectile_layer.add_child(view)
	else:
		view = _projectile_pool.pop_back()
		view.visible = true
	_projectile_views[projectile_id] = view

func _remove_projectile_view(projectile_id: int) -> void:
	if not _projectile_views.has(projectile_id):
		return
	var view: Node2D = _projectile_views[projectile_id]
	view.visible = false
	_projectile_pool.append(view)
	_projectile_views.erase(projectile_id)
