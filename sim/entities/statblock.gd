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

# Save/replay serialization (ARCHITECTURE.md §10). Plain floats, so this is a straight
# copy; JSON parses every number back as a float, matching these fields.
func to_dict() -> Dictionary:
	return {
		"damage": damage, "attack_speed": attack_speed, "attack_range": attack_range,
		"crit_chance": crit_chance, "crit_damage": crit_damage,
		"mana_per_attack": mana_per_attack, "mana_max": mana_max,
		"projectile_speed": projectile_speed,
	}

static func from_dict(d: Dictionary) -> StatBlock:
	var s := StatBlock.new()
	s.damage = d.get("damage", 0.0)
	s.attack_speed = d.get("attack_speed", 0.0)
	s.attack_range = d.get("attack_range", 0.0)
	s.crit_chance = d.get("crit_chance", 0.0)
	s.crit_damage = d.get("crit_damage", 0.0)
	s.mana_per_attack = d.get("mana_per_attack", 0.0)
	s.mana_max = d.get("mana_max", 0.0)
	s.projectile_speed = d.get("projectile_speed", 0.0)
	return s
