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
	DEBUG_SPAWN_ENEMY,   # M0 dev-only: puts an enemy on the track so the client
	                     # loop has something to render. M1's wave scheduler replaces it.
}

var kind: int = -1

func _init(p_kind: int = -1) -> void:
	kind = p_kind

# Save/replay serialization (ARCHITECTURE.md §10): the command log is what makes a run
# reproducible from its seed. The base carries just the kind; subclasses with fields
# override to_dict to add them. from_dict is the factory the log is rebuilt through.
func to_dict() -> Dictionary:
	return {"kind": kind}

static func from_dict(d: Dictionary) -> Command:
	match int(d.get("kind", -1)):
		Kind.BUY_UNIT:
			return BuyUnit.new()
		Kind.PLACE_UNIT:
			return PlaceUnit.new(int(d.get("unit_id", 0)), int(d.get("tile", -1)))
		Kind.MOVE_UNIT:
			return MoveUnit.new(int(d.get("unit_id", 0)), int(d.get("tile", -1)))
		Kind.SELL_UNIT:
			return SellUnit.new(int(d.get("unit_id", 0)))
		_:
			return null  # equip/reward/start_wave/debug: not part of the M1 replay log
