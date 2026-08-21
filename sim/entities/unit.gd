class_name Unit
extends RefCounted

# ARCHITECTURE.md §5. `stats` is a derived cache: recompute on equip, unequip,
# combine, or anvil — never per tick. `coverage` and `buckets` are computed once
# at placement (§6).

var id: int = 0
var hero_id: StringName = &""
var tier: int = 1                       # 1 or 2 (combined)
var copies: int = 1                     # 1..5
var price_paid: int = 0                 # what this unit cost at buy; drives the sell refund
var tile: int = -1                      # -1 = on bench
var pos: Vector2 = Vector2.ZERO         # center in sim space; set at placement,
                                        # feeds coverage math and projectile origin
var mana: float = 0.0
var attack_cooldown: float = 0.0        # ticks until next auto-attack; <= 0 = ready
var target_enemy_id: int = 0            # transient, set by Targeting each tick (0 = none)
var items: Array[StringName] = [&"", &"", &"", &""]   # length 4
var stats: StatBlock = null             # derived cache
var coverage: Array[Vector2] = []       # perimeter [start, end] intervals
var buckets: PackedInt32Array = PackedInt32Array()    # bucket indices coverage touches

# Save/replay serialization (ARCHITECTURE.md §10). `coverage` and `buckets` are derived
# from pos + range, so they are NOT stored — from_dict recomputes them exactly the way
# placement does (§6), which keeps the save small and can't drift from the stored pos.
func to_dict() -> Dictionary:
	var items_out: Array = []
	for it in items:
		items_out.append(String(it))
	return {
		"id": id, "hero_id": String(hero_id), "tier": tier, "copies": copies,
		"price_paid": price_paid, "tile": tile, "pos": [pos.x, pos.y],
		"mana": mana, "attack_cooldown": attack_cooldown, "target_enemy_id": target_enemy_id,
		"items": items_out, "stats": stats.to_dict() if stats != null else null,
	}

static func from_dict(d: Dictionary) -> Unit:
	var u := Unit.new()
	u.id = int(d.get("id", 0))
	u.hero_id = StringName(d.get("hero_id", ""))
	u.tier = int(d.get("tier", 1))
	u.copies = int(d.get("copies", 1))
	u.price_paid = int(d.get("price_paid", 0))
	u.tile = int(d.get("tile", -1))
	var xy: Array = d.get("pos", [0.0, 0.0])
	u.pos = Vector2(xy[0], xy[1])
	u.mana = d.get("mana", 0.0)
	u.attack_cooldown = d.get("attack_cooldown", 0.0)
	u.target_enemy_id = int(d.get("target_enemy_id", 0))
	var items_in: Array = d.get("items", [])
	u.items = [&"", &"", &"", &""]
	for i in mini(items_in.size(), 4):
		u.items[i] = StringName(items_in[i])
	var sd = d.get("stats", null)
	u.stats = StatBlock.from_dict(sd) if sd != null else null
	# Recompute the derived coverage/buckets from the stored placement, exactly as
	# Ingest does on PLACE_UNIT. Benched units (tile == -1) have none.
	if u.tile >= 0 and u.stats != null:
		u.coverage = Path.coverage_intervals(u.pos, u.stats.attack_range)
		u.buckets = Path.buckets_for_intervals(u.coverage)
	return u
