class_name World
extends RefCounted

# Pure simulation state (ARCHITECTURE.md §5). Plain serializable data only:
# ints, floats, strings, Array, Dictionary, and RefCounted entity objects with
# plain fields. No Node, no Callable, no Signal — so the whole thing round-trips
# through JSON, which gives the save format and the future co-op wire format for
# free (§3).

enum Phase { COMBAT, INTERMISSION, REWARD, OVER }

var tick: int = 0
var seed_value: int = 0
var rng: Dictionary = {}                # StringName -> RandomNumberGenerator

var wave: int = 0
var wave_timer: int = 0
var spawn_corner: int = 0               # 0..3
var direction: int = 1                  # 1 or -1

var enemies: Array[Enemy] = []
var units: Array[Unit] = []             # deployed, kept in tile index order (§3)
var bench: Array[Unit] = [null, null, null, null, null, null, null, null]
var projectiles: Array[Projectile] = []

# Transient spatial index (§6): bucket i holds the indices into `enemies` of every
# enemy currently in that perimeter bucket. Rebuilt from scratch each tick by
# Buckets.rebuild before targeting reads it; not part of the persisted save.
var buckets: Array[PackedInt32Array] = []

var gold: int = 0
var units_purchased: int = 0            # drives escalating price
var alive_count: int = 0
var alive_cap: int = 200

var next_entity_id: int = 1
var phase: int = Phase.INTERMISSION
var won: bool = false                   # meaningful once phase == OVER (win vs loss)
var pending_choices: Array = []         # anvil or elite reward, empty when none

# Entity IDs come from a monotonic counter, never object identity (§3).
func next_id() -> int:
	var id := next_entity_id
	next_entity_id += 1
	return id

# Deployed units are kept in tile index order so per-tick systems (targeting,
# combat) iterate deterministically (§3). Bench units (tile == -1) live in
# `bench`, not here. Placement (M1) routes through this; M0 tests call it directly.
func insert_unit_sorted(unit: Unit) -> void:
	var i := 0
	while i < units.size() and units[i].tile <= unit.tile:
		i += 1
	units.insert(i, unit)

# Save/replay serialization (ARCHITECTURE.md §10). World is plain data, so it round-trips
# to a Dictionary of JSON-native types and back. Two things are NOT stored: `buckets` is a
# transient spatial index rebuilt every tick (§4 step 4), and `pending_choices` is empty
# in M1 (rewards are M4). RNG streams save their `state` (as a string, since it is a full
# 64-bit value JSON would lose precision on) and resume exactly (§7).
func to_dict() -> Dictionary:
	var rng_out: Dictionary = {}
	for name in rng:
		rng_out[String(name)] = str((rng[name] as RandomNumberGenerator).state)
	var enemies_out: Array = []
	for e in enemies:
		enemies_out.append(e.to_dict())
	var units_out: Array = []
	for u in units:
		units_out.append(u.to_dict())
	var bench_out: Array = []
	for b in bench:
		bench_out.append(b.to_dict() if b != null else null)
	var proj_out: Array = []
	for p in projectiles:
		proj_out.append(p.to_dict())
	return {
		"tick": tick, "seed_value": seed_value, "rng": rng_out,
		"wave": wave, "wave_timer": wave_timer, "spawn_corner": spawn_corner, "direction": direction,
		"enemies": enemies_out, "units": units_out, "bench": bench_out, "projectiles": proj_out,
		"gold": gold, "units_purchased": units_purchased,
		"alive_count": alive_count, "alive_cap": alive_cap,
		"next_entity_id": next_entity_id, "phase": phase, "won": won,
	}

static func from_dict(d: Dictionary) -> World:
	var w := World.new()
	w.seed_value = int(d.get("seed_value", 0))
	# Reseed the streams from the run seed (so each has its correct seed), then overwrite
	# each state with the saved position to resume the exact sequence.
	w.rng = Rng.make_streams(w.seed_value)
	var rng_in: Dictionary = d.get("rng", {})
	for name in rng_in:
		var key := StringName(name)
		if w.rng.has(key):
			(w.rng[key] as RandomNumberGenerator).state = String(rng_in[name]).to_int()
	w.tick = int(d.get("tick", 0))
	w.wave = int(d.get("wave", 0))
	w.wave_timer = int(d.get("wave_timer", 0))
	w.spawn_corner = int(d.get("spawn_corner", 0))
	w.direction = int(d.get("direction", 1))
	for ed in d.get("enemies", []):
		w.enemies.append(Enemy.from_dict(ed))
	for ud in d.get("units", []):
		w.units.append(Unit.from_dict(ud))
	w.bench = [null, null, null, null, null, null, null, null]
	var bench_in: Array = d.get("bench", [])
	for i in mini(bench_in.size(), 8):
		if bench_in[i] != null:
			w.bench[i] = Unit.from_dict(bench_in[i])
	for pd in d.get("projectiles", []):
		w.projectiles.append(Projectile.from_dict(pd))
	w.gold = int(d.get("gold", 0))
	w.units_purchased = int(d.get("units_purchased", 0))
	w.alive_count = int(d.get("alive_count", 0))
	w.alive_cap = int(d.get("alive_cap", 200))
	w.next_entity_id = int(d.get("next_entity_id", 1))
	w.phase = int(d.get("phase", Phase.INTERMISSION))
	w.won = bool(d.get("won", false))
	return w

# Deep copy via the serialization round-trip — the same data path as a save, so a clone
# and a reloaded save are provably identical. Used by replay verification and any future
# rollback (§10, §11).
func clone() -> World:
	return World.from_dict(to_dict())
