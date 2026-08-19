class_name Content
extends RefCounted

# Typed content container (ARCHITECTURE.md §8). content/loader.gd parses
# res://content/*.json into this at startup; no balance numbers live in code.
# Constructible empty (defaults below) so pure-sim tests that don't need the tables
# can still do Content.new(); the loader fills the tables for a real game.

# Globals (config.json).
var alive_cap: int = 200
var starting_gold: int = 0

# Economy (config.json). M1 is kill-gold only; stipend/interest are stubbed to 0
# and stay off until M4/M5 turn them on (§1).
var unit_base_price: int = 3
var unit_price_growth: float = 0.20      # escalates per purchase, §7 says +15–25%
var per_wave_stipend: int = 0            # stubbed
var interest_per_10: int = 0             # stubbed

# Tables.
var enemy_types: Dictionary = {}         # StringName -> EnemyType
var heroes: Array[HeroDef] = []          # roster order; unit_purchase RNG indexes this
var waves: Array[WaveDef] = []           # index = wave number - 1

# Populated by the loader when validation fails; empty means clean load.
var load_errors: Array[String] = []

var _hero_by_id: Dictionary = {}         # StringName -> HeroDef

func register_hero(hero: HeroDef) -> void:
	heroes.append(hero)
	_hero_by_id[hero.id] = hero

func get_hero(id: StringName) -> HeroDef:
	return _hero_by_id.get(id)

func get_enemy_type(id: StringName) -> EnemyType:
	return enemy_types.get(id)

# Escalating unit price (§7): base * (1 + growth)^purchases, rounded. Buying units
# should get pricier or late-game gold trivializes every combine.
func unit_price(purchases: int) -> int:
	return int(round(float(unit_base_price) * pow(1.0 + unit_price_growth, float(purchases))))
