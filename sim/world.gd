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
var units: Array[Unit] = []             # deployed
var bench: Array[Unit] = [null, null, null, null, null, null, null, null]
var projectiles: Array[Projectile] = []

var gold: int = 0
var units_purchased: int = 0            # drives escalating price
var alive_count: int = 0
var alive_cap: int = 200

var next_entity_id: int = 1
var phase: int = Phase.INTERMISSION
var pending_choices: Array = []         # anvil or elite reward, empty when none

# Entity IDs come from a monotonic counter, never object identity (§3).
func next_id() -> int:
	var id := next_entity_id
	next_entity_id += 1
	return id

# TODO(M1 save/replay): clone() and JSON serialize/deserialize land with §10.
# Not on the M0 critical path; World is designed to round-trip once we need it.
