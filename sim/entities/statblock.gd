class_name StatBlock
extends RefCounted

# Derived combat stats for a Unit (ARCHITECTURE.md §5). Base values come from the
# hero content table; items and anvils modify them. Recomputed only on equip,
# unequip, combine, or anvil — cached on Unit.stats, never rebuilt per tick.
# `attack_range` avoids shadowing GDScript's built-in range().

var damage: float = 0.0
var attack_speed: float = 0.0           # attacks per second
var attack_range: float = 0.0           # perimeter / world units
var crit_chance: float = 0.0
var crit_damage: float = 0.0
var mana_per_attack: float = 0.0
var mana_max: float = 0.0
var projectile_speed: float = 0.0
