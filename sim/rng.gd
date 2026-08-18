class_name Rng
extends RefCounted

# Named independent RNG streams (ARCHITECTURE.md §7). Adding a roll to one system
# never shifts another's sequence, which is what makes cross-build balance
# comparisons meaningful.
#
# NEVER call the global randi()/randf()/randi_range()/randf_range()/randomize().
# They read a shared generator and destroy determinism. Always draw from one of
# these streams via World.rng[&"stream_name"].

const STREAMS: Array[StringName] = [
	&"unit_purchase",
	&"item_drop",
	&"anvil_stats",
	&"anvil_rarity",
	&"elite_reward",
	&"wave_composition",
]

# StringName -> RandomNumberGenerator, each seeded from the run seed plus its
# stream index. `state` is readable/writable so streams serialize into the save
# and resume exactly (§7).
static func make_streams(seed_value: int) -> Dictionary:
	var streams: Dictionary = {}
	for i in STREAMS.size():
		var generator := RandomNumberGenerator.new()
		generator.seed = seed_value + i
		streams[STREAMS[i]] = generator
	return streams
