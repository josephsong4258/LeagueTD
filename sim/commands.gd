class_name Command
extends RefCounted

# Player intents ingested at the top of the tick and validated against current
# state; invalid commands are dropped and logged, never asserted (ARCHITECTURE.md
# §4 step 1). Concrete typed command classes land with the M1 economy/board
# systems — this is the seam, kept minimal.

enum Kind {
	BUY_UNIT,
	PLACE_UNIT,
	MOVE_UNIT,
	SELL_UNIT,
	EQUIP_ITEM,
	CHOOSE_REWARD,
	START_WAVE,
}

var kind: int = -1

func _init(p_kind: int = -1) -> void:
	kind = p_kind
