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
const BenchView := preload("res://game/board/bench_view.gd")
const CoverageView := preload("res://game/board/coverage_view.gd")
const UnitView := preload("res://game/units/unit_view.gd")
const Hud := preload("res://game/ui/hud.gd")

# Board-local distance within which a click/press grabs a unit view for a drag.
const _PICK_RADIUS := 34.0

const _BOARD_PADDING := 80.0
const _SPEED_MULTIPLIER := 1          # game speed = extra step() calls, never time_scale (§9)

var world: World
var _content: Content
var _commands: Array[Command] = []

var _board: Node2D
var _hud: Hud
var _bench: BenchView
var _coverage_layer: CoverageView
var _unit_layer: Node2D
var _enemy_layer: Node2D
var _projectile_layer: Node2D

# id -> live view, plus free lists so nothing is instantiated during a wave (§9).
var _enemy_views: Dictionary = {}
var _projectile_views: Dictionary = {}
var _unit_views: Dictionary = {}
var _enemy_pool: Array[Node2D] = []
var _projectile_pool: Array[Node2D] = []
var _unit_pool: Array[Node2D] = []

# Where each live unit sits, mirrored from UnitBought/UnitMoved events (never diffed
# from World): Vector2i(tile, slot) with tile == -1 meaning benched at that slot. Drives
# where a view snaps back to and whether a drop is a PLACE (from bench) or a MOVE.
var _unit_loc: Dictionary = {}

var _drag_id: int = 0                    # 0 = not dragging; else the unit being dragged

func _ready() -> void:
	Engine.physics_ticks_per_second = 30
	# Client-side seed; the sim's determinism is per-seed, and replays (M1/§10) will
	# pin this. Time is fine here — this is the host, not sim/.
	var seed_value := int(Time.get_unix_time_from_system())
	_content = ContentLoader.load_default()
	world = Sim.new_world(seed_value, _content)
	_build_layers()
	_hud = Hud.new()
	_hud.world = world
	_hud.command_issued.connect(_queue_command)
	add_child(_hud)
	get_viewport().size_changed.connect(_layout_board)
	_layout_board()

func _build_layers() -> void:
	_board = Node2D.new()
	add_child(_board)
	_board.add_child(TrackView.new())
	_board.add_child(TilesView.new())
	_bench = BenchView.new()
	_board.add_child(_bench)
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
	# The bench hangs below the arena; reserve its height so the row isn't clipped.
	world_size.y += _bench.bottom_extent()
	var fit_scale := minf(
		(vp.x - 2.0 * _BOARD_PADDING) / world_size.x,
		(vp.y - 2.0 * _BOARD_PADDING) / world_size.y)
	_board.scale = Vector2(fit_scale, fit_scale)
	# The ring is centered on the origin, so centering the board on the viewport is
	# just translating to the middle.
	_board.position = vp * 0.5

func _physics_process(_delta: float) -> void:
	for _i in _SPEED_MULTIPLIER:
		var events := Sim.step(world, _drain_commands(), _content)
		_handle_events(events)

func _drain_commands() -> Array[Command]:
	var out := _commands
	_commands = []
	return out

# The one sink for player intent: the HUD buy button, the 'B' shortcut, and drag drops
# all funnel here. Commands are applied at the top of the next tick and either take
# (emitting a result event) or are dropped silently — this never touches World.
func _queue_command(command: Command) -> void:
	_commands.append(command)

# --- drag-and-drop placement (M1 step 8) ---
#
# Board-space, so bench and board are one coordinate system. Press grabs the unit view
# under the cursor; motion drags it; release resolves a target (a tile inside the arena,
# or the bench band below it) and emits PLACE/MOVE. The dragged view is snapped back to
# its last event-confirmed home on release — the accepted command's UnitMoved event
# repositions it next tick, and a rejected drop just stays home. Uses _unhandled_input
# so the HUD's buttons (GUI input) win their own clicks.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_B:
			_queue_command(BuyUnit.new())
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_begin_drag(_board.to_local(mb.position))
		else:
			_end_drag(_board.to_local(mb.position))
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT and (event as InputEventMouseButton).pressed:
		# Right-click a unit (bench or board) to sell it for the refund.
		var sell_id := _pick_unit_at(_board.to_local((event as InputEventMouseButton).position))
		if sell_id != 0:
			_queue_command(SellUnit.new(sell_id))
	elif event is InputEventMouseMotion and _drag_id != 0:
		(_unit_views[_drag_id] as Node2D).position = _board.to_local((event as InputEventMouseMotion).position)

func _begin_drag(local: Vector2) -> void:
	var id := _pick_unit_at(local)
	if id == 0:
		return
	_drag_id = id
	var view := _unit_views[id] as Node2D
	view.z_index = 10                       # lift above the other units while dragging
	view.position = local

func _end_drag(local: Vector2) -> void:
	if _drag_id == 0:
		return
	var id := _drag_id
	_drag_id = 0
	var view := _unit_views[id] as Node2D
	view.z_index = 0
	view.position = _unit_home(id)          # let the resulting event move it, or stay put
	var from_bench := (_unit_loc[id] as Vector2i).x == -1
	if _bench.is_bench_point(local):
		if not from_bench:
			_queue_command(MoveUnit.new(id, -1))
		return
	if not Path.point_inside(local, 0.0):
		return                              # dropped off the board and not on the bench
	var tile := BoardGrid.nearest_tile(local)
	if tile == -1:
		return
	if from_bench:
		_queue_command(PlaceUnit.new(id, tile))
	else:
		_queue_command(MoveUnit.new(id, tile))

# Nearest live unit view within the pick radius, or 0 if the cursor is over empty space.
func _pick_unit_at(local: Vector2) -> int:
	var best := 0
	var best_dist := _PICK_RADIUS * _PICK_RADIUS
	for id in _unit_views:
		var d := local.distance_squared_to((_unit_views[id] as Node2D).position)
		if d < best_dist:
			best_dist = d
			best = id
	return best

# Board-space home of a unit, from its mirrored location: a tile center, or a bench slot.
func _unit_home(id: int) -> Vector2:
	var loc := _unit_loc[id] as Vector2i
	if loc.x >= 0:
		return BoardGrid.tile_center(loc.x)
	return _bench.slot_center(loc.y)

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
			SimEvent.Kind.UNIT_BOUGHT:
				_on_unit_bought(event as UnitBought)
			SimEvent.Kind.UNIT_MOVED:
				_on_unit_moved(event as UnitMoved)
			SimEvent.Kind.UNIT_SOLD:
				_on_unit_sold(event as UnitSold)

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

# --- unit views (driven by UnitBought / UnitMoved / UnitSold, never by diffing World) ---

func _on_unit_bought(event: UnitBought) -> void:
	var view: Node2D
	if _unit_pool.is_empty():
		view = UnitView.new()
		_unit_layer.add_child(view)
	else:
		view = _unit_pool.pop_back()
		view.visible = true
	view.z_index = 0
	_unit_views[event.unit_id] = view
	_unit_loc[event.unit_id] = Vector2i(-1, event.slot)
	view.position = _bench.slot_center(event.slot)

func _on_unit_moved(event: UnitMoved) -> void:
	if not _unit_views.has(event.unit_id):
		return
	_unit_loc[event.unit_id] = Vector2i(event.tile, event.slot)
	(_unit_views[event.unit_id] as Node2D).position = _unit_home(event.unit_id)
	_coverage_layer.queue_redraw()          # coverage arcs follow deployment changes

func _on_unit_sold(event: UnitSold) -> void:
	if not _unit_views.has(event.unit_id):
		return
	var view: Node2D = _unit_views[event.unit_id]
	view.visible = false
	view.z_index = 0
	_unit_pool.append(view)
	_unit_views.erase(event.unit_id)
	_unit_loc.erase(event.unit_id)
	if _drag_id == event.unit_id:
		_drag_id = 0
	_coverage_layer.queue_redraw()
