extends BaseUnit
class_name EnemyUnit

var player_units_identified: Array

func _ready() -> void:
	super()
	find_new_random_attack_target()
	add_to_group("enemy_units")
	

#-10, 0.15, -10 === 50, 0.15, 10

func _physics_process(delta: float) -> void:
	super(delta)

func find_new_random_attack_target() -> void:
	var enemies = get_tree().get_nodes_in_group("player_units")
	if enemies.size() > 0:
		enemies.shuffle()
		set_attack_target(enemies.front())
	else:
		clear_attack_target()
