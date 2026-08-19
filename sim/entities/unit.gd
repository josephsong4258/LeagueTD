class_name Unit
extends RefCounted

# ARCHITECTURE.md §5. `stats` is a derived cache: recompute on equip, unequip,
# combine, or anvil — never per tick. `coverage` and `buckets` are computed once
# at placement (§6).

var id: int = 0
var hero_id: StringName = &""
var tier: int = 1                       # 1 or 2 (combined)
var copies: int = 1                     # 1..5
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
