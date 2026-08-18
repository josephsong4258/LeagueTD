class_name Content
extends RefCounted

# Typed content container (ARCHITECTURE.md §8). content/loader.gd parses
# res://content/*.json into this at startup; no balance numbers live in code.
#
# Kept minimal for M0 so the tick contract has something to consume without
# inventing a schema ahead of the design. The real tables (enemy types, heroes,
# items, anvils, waves, rewards) and the JSON loader land with M1.

var alive_cap: int = 200
var starting_gold: int = 0
