class_name Ingest
extends RefCounted

# ARCHITECTURE.md §4 step 1. Validate commands against current state and apply the
# economy/board changes at the top of the tick. Invalid or unrecognized commands are
# dropped, never asserted (§4) — a stale command from a laggy client, an unaffordable
# buy, or a click on an occupied tile must be a silent no-op, not a crash.
#
# M1 handles the economy/board set: buy a random unit, place/move it on the grid, and
# sell it. Equip/combine/anvil (M3) and reward choices (M4) are still dropped. Result
# events (bought/placed/sold, and rejection feedback for the HUD) land with the client
# wiring in M1 step 9, which owns what the UI needs to hear.

static func run(world: World, commands: Array[Command], content: Content, events: Array[SimEvent]) -> void:
	for command in commands:
		match command.kind:
			Command.Kind.BUY_UNIT:
				_buy_unit(world, content)
			Command.Kind.PLACE_UNIT:
				_relocate(world, (command as PlaceUnit).unit_id, (command as PlaceUnit).tile)
			Command.Kind.MOVE_UNIT:
				_relocate(world, (command as MoveUnit).unit_id, (command as MoveUnit).tile)
			Command.Kind.SELL_UNIT:
				_sell_unit(world, content, (command as SellUnit).unit_id)
			Command.Kind.DEBUG_SPAWN_ENEMY:
				_spawn_debug_enemy(world, command as DebugSpawnEnemy, events)
			_:
				pass  # equip / reward / start_wave: dropped in M1 by design.

# --- economy ---

# Buy one random hero onto the bench. Price escalates with units_purchased (§7); both
# the affordability check and the roll happen here so replaying the same command log
# reproduces the same unit. Dropped (no-op) when the roster is empty, the player can't
# afford it, or the bench is full.
static func _buy_unit(world: World, content: Content) -> void:
	if content == null or content.heroes.is_empty():
		return
	var price := content.unit_price(world.units_purchased)
	if world.gold < price:
		return
	var slot := _first_empty_bench(world)
	if slot == -1:
		return
	var rng: RandomNumberGenerator = world.rng[&"unit_purchase"]
	var hero: HeroDef = content.heroes[rng.randi_range(0, content.heroes.size() - 1)]
	var unit := Unit.new()
	unit.id = world.next_id()
	unit.hero_id = hero.id
	unit.stats = hero.to_statblock()
	unit.price_paid = price
	world.bench[slot] = unit
	world.gold -= price
	world.units_purchased += 1

# Sell: remove from wherever it sits and refund sell_refund_ratio of the unit's paid
# price (§ economy). units_purchased is left as-is, so the price curve keeps climbing —
# a buy/sell churn loses the refund gap each cycle instead of resetting the cost.
static func _sell_unit(world: World, content: Content, unit_id: int) -> void:
	var unit := _find_unit(world, unit_id)
	if unit == null:
		return
	_detach(world, unit)
	var ratio := content.sell_refund_ratio if content != null else 0.0
	world.gold += int(round(float(unit.price_paid) * ratio))

# --- board ---

# Move a unit to a tile (dest >= 0) or back to the bench (dest == -1). Shared by
# PLACE_UNIT (bench -> tile) and MOVE_UNIT (tile -> tile / bench); the split is client
# intent, the relocation is one operation. If the destination tile holds another unit
# they SWAP: the occupant takes the mover's old spot — its tile, or the bench when the
# mover came off the bench — matching the TFT drag. Dropped as a silent no-op when the
# unit is gone, the destination is out of range, or a needed bench slot is full.
# Placement recomputes coverage/buckets from the new position (§6).
static func _relocate(world: World, unit_id: int, dest: int) -> void:
	var unit := _find_unit(world, unit_id)
	if unit == null:
		return
	if dest == -1:
		if unit.tile == -1:
			return                                  # already benched
		if _first_empty_bench(world) == -1:
			return                                  # bench full
		_detach(world, unit)
		_place_on_bench(world, unit)
		return
	if dest < 0 or dest >= BoardGrid.tile_count():
		return
	if unit.tile == dest:
		return                                      # already there
	var origin := unit.tile                         # -1 (bench) or the mover's tile
	var occupant := _tile_occupant(world, dest)
	if occupant == null:
		_detach(world, unit)
		_place_on_tile(world, unit, dest)
		return
	# Swap. Detaching the mover first frees its bench slot, so a bench-bound occupant
	# always has room; a tile<->tile swap just trades the two tiles.
	_detach(world, unit)
	_detach(world, occupant)
	if origin == -1:
		_place_on_bench(world, occupant)
	else:
		_place_on_tile(world, occupant, origin)
	_place_on_tile(world, unit, dest)

static func _place_on_tile(world: World, unit: Unit, tile: int) -> void:
	unit.tile = tile
	unit.pos = BoardGrid.tile_center(tile)
	unit.coverage = Path.coverage_intervals(unit.pos, unit.stats.attack_range)
	unit.buckets = Path.buckets_for_intervals(unit.coverage)
	unit.target_enemy_id = 0
	world.insert_unit_sorted(unit)

# Put a detached unit on the first empty bench slot; the caller guarantees a slot.
static func _place_on_bench(world: World, unit: Unit) -> void:
	_clear_placement(unit)
	world.bench[_first_empty_bench(world)] = unit

# --- helpers ---

static func _find_unit(world: World, unit_id: int) -> Unit:
	for unit in world.units:
		if unit.id == unit_id:
			return unit
	for unit in world.bench:
		if unit != null and unit.id == unit_id:
			return unit
	return null

# Remove a unit from its current home (a bench slot or the deployed array) without
# touching its placement fields — the caller sets those for the new home.
static func _detach(world: World, unit: Unit) -> void:
	if unit.tile == -1:
		for i in world.bench.size():
			if world.bench[i] == unit:
				world.bench[i] = null
				return
	else:
		world.units.erase(unit)

static func _clear_placement(unit: Unit) -> void:
	unit.tile = -1
	unit.pos = Vector2.ZERO
	unit.coverage.clear()
	unit.buckets.clear()
	unit.target_enemy_id = 0

static func _tile_occupant(world: World, tile: int) -> Unit:
	for unit in world.units:
		if unit.tile == tile:
			return unit
	return null

static func _first_empty_bench(world: World) -> int:
	for i in world.bench.size():
		if world.bench[i] == null:
			return i
	return -1

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
