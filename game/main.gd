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

# Entity-local distance within which a click/press grabs a unit for a drag.
const _PICK_RADIUS := 34.0

# Isometric presentation (client-only; the sim stays flat 2D). A flat sim point is mapped
# to the screen by a 2:1 dimetric projection: +x sim goes down-right, +y sim goes
# down-left, and the vertical is squashed by ISO_V, so the square grid reads as diamonds.
# ISO_X / ISO_Y are the screen images of the sim basis vectors. The ground (tiles / track
# / coverage) is drawn in flat sim space under a node whose Transform2D IS this projection
# (squares become diamonds, range circles become correct ground ellipses). Pieces live on
# a separate uniform layer, positioned by _project() but drawn UPRIGHT and depth-sorted,
# so they stand on the board. The bench is a straight screen-space row below the diamond.
const ISO_V := 0.5                    # vertical squash of the 2:1 projection
const ISO_X := Vector2(1.0, ISO_V)    # screen image of sim +x (down-right)
const ISO_Y := Vector2(-1.0, ISO_V)   # screen image of sim +y (down-left)
const _BENCH_MARGIN := 52.0           # gap below the board's front tip to the bench row

const _BOARD_PADDING := 72.0
const _SPEED_MULTIPLIER := 1          # game speed = extra step() calls, never time_scale (§9)

var world: World
var _content: Content
var _commands: Array[Command] = []

var _board: Node2D                       # isometric ground plane (Transform2D projection)
var _bench: BenchView                     # straight bench row, shares the pieces' transform
var _entities: Node2D                     # upright, y-sorted pieces standing on the board
var _hud: Hud
var _coverage_layer: CoverageView

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

# Persistence (ARCHITECTURE.md §10). The command log is the replayable run record; it and
# the world snapshot are written to user:// (IndexedDB on web) so a run survives a reload.
const _AUTOSAVE_INTERVAL := 90           # ticks (~3s at 30 Hz); also saves on each command + game over
var _content_hash: String = ""
var _command_log: Array = []             # { tick, cmd } entries
var _autosave_ticks: int = 0

func _ready() -> void:
	Engine.physics_ticks_per_second = 30
	_content = ContentLoader.load_default()
	_content_hash = ContentLoader.content_hash()
	_load_or_new()
	_build_layers()
	_hud = Hud.new()
	_hud.world = world
	_hud.command_issued.connect(_queue_command)
	add_child(_hud)
	get_viewport().size_changed.connect(_layout_board)
	_layout_board()                      # sets the bench row-y that _home() reads
	_rehydrate_views()                   # recreate views for entities restored from a save

# Resume the saved run if there is a usable, current save; otherwise start fresh. A save is
# rejected when it is absent/corrupt, its content_hash no longer matches the balance JSON,
# or it is already OVER (a finished run shouldn't resurrect on next launch).
func _load_or_new() -> void:
	var save := SaveStore.read()
	var snapshot: World = save.get("world")
	if not save.is_empty() and snapshot != null \
			and save.get("content_hash", "") == _content_hash \
			and snapshot.phase != World.Phase.OVER:
		world = snapshot
		_command_log = save.get("command_log", [])
		return
	# Client-side seed; the sim's determinism is per-seed, and the seed is embedded in the
	# save so a replay reproduces the run. Time is fine here — this is the host, not sim/.
	world = Sim.new_world(int(Time.get_unix_time_from_system()), _content)

func _build_layers() -> void:
	# Ground plane: everything drawn flat in sim space, projected to isometric by the
	# node's Transform2D (set in _layout_board), so squares read as diamonds.
	_board = Node2D.new()
	add_child(_board)
	_board.add_child(TrackView.new())
	_board.add_child(TilesView.new())
	_coverage_layer = CoverageView.new()
	_coverage_layer.world = world
	_board.add_child(_coverage_layer)
	# Bench: a straight screen-space row of slots, drawn under the pieces. Uniform scale,
	# same transform as _entities, so its slot coordinates and piece positions agree.
	_bench = BenchView.new()
	add_child(_bench)
	# Pieces: units, enemies, projectiles all share this one layer so y-sort orders them
	# by depth together (nearer draws in front). Added last so pieces sit on top. Uniform
	# scale keeps them upright while the ground is projected; each is placed at _project().
	_entities = Node2D.new()
	_entities.y_sort_enabled = true
	add_child(_entities)

# Fit the stadium (centered on the origin) into the viewport with uniform scale.
func _layout_board() -> void:
	var vp := get_viewport_rect().size
	# The band overhangs the centerline ring by half its width; include it so the outer
	# edge of the terrain isn't clipped. `h` is the board's flat half-extent in sim space.
	var overhang := Path.TRACK_WIDTH * 0.5 + 24.0
	var h := Path.half_extent() + Vector2(overhang, overhang)
	# Under the projection the board is a diamond: its screen half-width is (h.x + h.y),
	# and its top/front tips sit at +-(h.x + h.y) * ISO_V. The bench row hangs below the
	# front tip; reserve down to the bottom of its slots.
	var span := h.x + h.y
	var top_y := -span * ISO_V
	var row_y := span * ISO_V + _BENCH_MARGIN
	var bottom_y := row_y + _bench.slot_radius()
	var content_w := 2.0 * span
	var content_h := bottom_y - top_y
	var fit := minf(
		(vp.x - 2.0 * _BOARD_PADDING) / content_w,
		(vp.y - 2.0 * _BOARD_PADDING) / content_h)
	# Center the whole content (board diamond + bench) vertically in the viewport.
	var mid_y := (top_y + bottom_y) * 0.5
	var origin := vp * 0.5 - Vector2(0.0, mid_y * fit)
	# The ground node's transform IS the isometric projection, scaled and centered.
	_board.transform = Transform2D(ISO_X * fit, ISO_Y * fit, origin)
	# Bench and pieces share a plain uniform transform (they position via _project).
	_bench.scale = Vector2(fit, fit)
	_bench.position = origin
	_bench.set_row_y(row_y)
	_entities.scale = Vector2(fit, fit)
	_entities.position = origin

# Project a flat sim-space point into the pieces layer's local space (the isometric
# screen frame, pre-scale). Inverse of _screen_to_sim's projection step.
func _project(sim: Vector2) -> Vector2:
	return ISO_X * sim.x + ISO_Y * sim.y

# Map a viewport point back to flat sim space: undo the pieces layer's transform, then
# invert the projection. Used for picking and for resolving a drag's board drop target.
func _screen_to_sim(screen: Vector2) -> Vector2:
	var l := _entities.to_local(screen)
	# Invert [x - y, (x + y) * ISO_V]: solve for the sim (x, y).
	var sum := l.y / ISO_V
	return Vector2((l.x + sum) * 0.5, (sum - l.x) * 0.5)

func _physics_process(_delta: float) -> void:
	for _i in _SPEED_MULTIPLIER:
		var cmds := _drain_commands()
		# Log each command against the tick it is ingested on, so the run replays (§10).
		for c in cmds:
			_command_log.append({"tick": world.tick, "cmd": c})
		var events := Sim.step(world, cmds, _content)
		_handle_events(events)
		if not cmds.is_empty():
			_autosave()                  # persist player actions promptly
	_autosave_ticks += _SPEED_MULTIPLIER
	if _autosave_ticks >= _AUTOSAVE_INTERVAL:
		_autosave_ticks = 0
		_autosave()

func _autosave() -> void:
	SaveStore.write(world, _command_log, _content_hash)

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
# Picking and drag-follow happen in the pieces layer's local (isometric-screen) space,
# where the bench row and the projected board tiles both live, so one space covers both.
# Only a board drop needs flat sim space, unprojected via _screen_to_sim, to find a tile.
# Press grabs the piece under the cursor; motion drags its view; release resolves a target
# (a tile inside the board, else the bench row below it) and emits PLACE/MOVE. The dragged
# view snaps back to its event-confirmed home on release — the accepted command's UnitMoved
# repositions it next tick, and a rejected drop just stays home. Uses _unhandled_input so
# the HUD's buttons (GUI input) win their own clicks.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_B:
			_queue_command(BuyUnit.new())
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_begin_drag(mb.position)
		else:
			_end_drag(mb.position)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT and (event as InputEventMouseButton).pressed:
		# Right-click a unit (bench or board) to sell it for the refund.
		var sell_id := _pick_unit_at(_entities.to_local((event as InputEventMouseButton).position))
		if sell_id != 0:
			_queue_command(SellUnit.new(sell_id))
	elif event is InputEventMouseMotion and _drag_id != 0:
		(_unit_views[_drag_id] as Node2D).position = _entities.to_local((event as InputEventMouseMotion).position)

func _begin_drag(screen: Vector2) -> void:
	var local := _entities.to_local(screen)
	var id := _pick_unit_at(local)
	if id == 0:
		return
	_drag_id = id
	var view := _unit_views[id] as Node2D
	view.z_index = 10                       # lift above the other pieces while dragging
	view.position = local

func _end_drag(screen: Vector2) -> void:
	if _drag_id == 0:
		return
	var id := _drag_id
	_drag_id = 0
	var view := _unit_views[id] as Node2D
	view.z_index = 0
	view.position = _home(id)               # let the resulting event move it, or stay put
	var from_bench := (_unit_loc[id] as Vector2i).x == -1
	# A board tile wins when the drop unprojects to somewhere inside the board rectangle;
	# otherwise, if the cursor is over the bench row, it benches.
	var sim := _screen_to_sim(screen)
	if Path.point_inside(sim, 0.0):
		var tile := BoardGrid.nearest_tile(sim)
		if tile == -1:
			return
		if from_bench:
			_queue_command(PlaceUnit.new(id, tile))
		else:
			_queue_command(MoveUnit.new(id, tile))
	elif _bench.is_bench_point(_entities.to_local(screen)):
		if not from_bench:
			_queue_command(MoveUnit.new(id, -1))

# Nearest live unit within the pick radius of an entity-local point, or 0 if none.
func _pick_unit_at(local: Vector2) -> int:
	var best := 0
	var best_dist := _PICK_RADIUS * _PICK_RADIUS
	for id in _unit_views:
		var d := local.distance_squared_to(_home(id))
		if d < best_dist:
			best_dist = d
			best = id
	return best

# Entity-local home of a unit, from its mirrored location: a projected board tile, or a
# bench slot (already entity-local). This is the space piece views position themselves in.
func _home(id: int) -> Vector2:
	var loc := _unit_loc[id] as Vector2i
	if loc.x >= 0:
		return _project(BoardGrid.tile_center(loc.x))
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
			SimEvent.Kind.GAME_OVER:
				_autosave()               # persist the final verdict once the run ends

func _process(_delta: float) -> void:
	var alpha := Engine.get_physics_interpolation_fraction()
	var enemy_by_id := {}
	for enemy in world.enemies:
		enemy_by_id[enemy.id] = enemy
	for id in _enemy_views:
		var enemy: Enemy = enemy_by_id.get(id)
		if enemy != null:
			var ev := _enemy_views[id] as EnemyView
			ev.position = _project(ev.interp_pos(enemy, alpha))
	var proj_by_id := {}
	for projectile in world.projectiles:
		proj_by_id[projectile.id] = projectile
	for id in _projectile_views:
		var projectile: Projectile = proj_by_id.get(id)
		if projectile != null:
			var pv := _projectile_views[id] as ProjectileView
			pv.position = _project(pv.interp_pos(projectile, alpha))

# --- pooled view lifecycle ---

func _add_enemy_view(enemy_id: int) -> void:
	var view: Node2D
	if _enemy_pool.is_empty():
		view = EnemyView.new()
		_entities.add_child(view)
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
		_entities.add_child(view)
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
	_spawn_unit_view(event.unit_id, Vector2i(-1, event.slot))

# Acquire a pooled unit view for `id` at location `loc` (Vector2i(tile, slot); tile -1 =
# benched). Shared by UnitBought and by save rehydration, which creates the same views for
# units restored from a snapshot instead of from a buy event.
func _spawn_unit_view(id: int, loc: Vector2i) -> void:
	var view: Node2D
	if _unit_pool.is_empty():
		view = UnitView.new()
		_entities.add_child(view)
	else:
		view = _unit_pool.pop_back()
		view.visible = true
	view.z_index = 0
	_unit_views[id] = view
	_unit_loc[id] = loc
	view.position = _home(id)

# Recreate views for the entities in a snapshot restored from a save. Events only fire for
# NEW entities, so a resumed world's existing enemies/projectiles/units have no views yet;
# this primes them once at load (the one place a view is built by reading World, §9).
func _rehydrate_views() -> void:
	for enemy in world.enemies:
		_add_enemy_view(enemy.id)
	for projectile in world.projectiles:
		_add_projectile_view(projectile.id)
	for unit in world.units:
		_spawn_unit_view(unit.id, Vector2i(unit.tile, -1))
	for i in world.bench.size():
		var benched: Unit = world.bench[i]
		if benched != null:
			_spawn_unit_view(benched.id, Vector2i(-1, i))
	_coverage_layer.queue_redraw()

func _on_unit_moved(event: UnitMoved) -> void:
	if not _unit_views.has(event.unit_id):
		return
	_unit_loc[event.unit_id] = Vector2i(event.tile, event.slot)
	(_unit_views[event.unit_id] as Node2D).position = _home(event.unit_id)
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
