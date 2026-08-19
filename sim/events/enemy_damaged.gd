class_name EnemyDamaged
extends SimEvent

# Emitted whenever an enemy loses hp (ARCHITECTURE.md §4 step 8/9). `remaining_hp`
# lets the renderer drive damage numbers and health bars straight from the event
# stream without reading World.

var enemy_id: int
var amount: float
var remaining_hp: float

func _init(p_enemy_id: int, p_amount: float, p_remaining_hp: float) -> void:
	super(SimEvent.Kind.ENEMY_DAMAGED)
	enemy_id = p_enemy_id
	amount = p_amount
	remaining_hp = p_remaining_hp
