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

# TODO(M1 save/replay): clone() and JSON serialize/deserialize land with §10.
# Not on the M0 critical path; World is designed to round-trip once we need it.
