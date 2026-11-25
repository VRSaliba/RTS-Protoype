extends BaseUnit
class_name PlayerUnit

const ActionSelectedEnum = preload("uid://nf7pc7tlapya")

@onready var confirmed_mesh: MeshInstance3D = $"Confirmed Mesh"

var combat_action_selected: ActionSelectedEnum.ActionSelected

func _ready() -> void:
	super()
	add_to_group("player_units")

func _physics_process(delta: float) -> void:
	super(delta)

# Also fit the confirmed ring to the model's size.
func _fit_to_model(model: UnitModel) -> void:
	super(model)
	_fit_ring(confirmed_mesh, model)

func _mouse_screen_to_world(camera: Camera3D, ray_collision_mask: int = 0xFFFFFFFF) -> Dictionary:
	var mouse_position = camera.get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_position)
	var ray_end = ray_origin + camera.project_ray_normal(mouse_position) * 100
	var space_state = camera.get_world_3d().direct_space_state

	var query := PhysicsRayQueryParameters3D.new()
	query.from = ray_origin
	query.to = ray_end
	query.collision_mask = ray_collision_mask
	var raycast = space_state.intersect_ray(query)
	return raycast

func set_manual_move_target(ray: Dictionary) -> void:
	if ray:
		nav_agent.target_position = ray["position"]
		set_move_target(nav_agent.target_position)
		clear_attack_target()
		change_state(UnitState.MOVING)

func reset_combat_action_selected() -> void:
	combat_action_selected = ActionSelectedEnum.ActionSelected.NONE

func find_new_random_attack_target() -> void:
	var enemies = get_tree().get_nodes_in_group("enemy_units")
	if enemies.size() > 0:
		enemies.shuffle()
		set_attack_target(enemies.front())
	else:
		clear_attack_target()
