extends Node3D
class_name BaseBattleLevel
 
const BATTLE_UI = preload("uid://tx46vr0ac1ho")
const ActionSelectedEnum = preload("uid://nf7pc7tlapya")

@onready var turn_timer: Timer = $Timer
var turn_duration: float = 5.0

@onready var player_units_node: Node = $"Player Units"
@onready var enemy_units_node: Node = $"Enemy Units"

@onready var camera_origin: Node3D = $"Camera Position"

@onready var tween_node: Tween

var player_units_array: UnitArray = UnitArray.new([], 0)
var enemy_units_array: UnitArray = UnitArray.new([], 0)

var selected_enemy_unit: EnemyUnit
var selected_player_unit: PlayerUnit
var camera_can_follow_unit: bool = false

var game_paused: bool = false

var battle_ui: Node

var total_time_spent: float = 0

func _ready() -> void:
	# make camera not copy the unit array, make it know which one it is looking at, but do not copy it!
	#print("fazer ataques")
	#print("fazer habilidades")
	battle_ui = BATTLE_UI.instantiate()
	add_child(battle_ui)
	
	GlobalSignals.camera_moved.connect(release_camera)
	
	GlobalSignals.move_button_pressed.connect(move_button_signal_emitted)
	GlobalSignals.attack_button_pressed.connect(attack_button_signal_emitted)
	GlobalSignals.skill_button_pressed.connect(skill_button_signal_emitted)
	GlobalSignals.confirm_target_pressed.connect(confirm_target_signal_emitted)
	GlobalSignals.unit_died.connect(remove_dead_unit_from_groups)
	
	update_player_units_array()
	update_enemy_units_array()
	update_camera_unit_array(player_units_array)
	
	selected_enemy_unit = enemy_units_array.array[enemy_units_array.position]
	
	selected_player_unit = player_units_array.array[player_units_array.position]
	selected_player_unit.set_selected_true()
	
	move_camera_to_unit(selected_player_unit)
	
	pause_game()

func _process(delta: float) -> void:
	if not game_paused:
		total_time_spent += delta
		battle_ui.update_time_label(format_time(total_time_spent))
	
	if camera_can_follow_unit and selected_player_unit:
		camera_origin.position = selected_player_unit.position
		camera_origin.move_target = selected_player_unit.position

func format_time(time: float) -> String:
	@warning_ignore("integer_division")
	var mins := int(time) / 60
	var secs := int(time) % 60
	var ms := int((time - int(time)) * 1000)
	return "%02d:%02d.%03d" % [mins, secs, ms]   

func pause_pressed() -> void:
	if game_paused:
		unpause_game()
	else:
		pause_game()

func pause_game() -> void:
	game_paused = true
	get_tree().call_group("all_units", "pause")
	get_tree().call_group("player_units", "turn_started")
	battle_ui.show_buttons_container()
	battle_ui.update_pause_label("Paused")
	battle_ui.show_pause_label()

func unpause_game() -> void:
	game_paused = false
	get_tree().call_group("all_units", "resume")
	get_tree().call_group("player_units", "turn_started")
	battle_ui.show_buttons_container()
	battle_ui.hide_pause_label()

func move_button_signal_emitted() -> void:
	if selected_player_unit:
		if selected_player_unit.combat_action_selected != ActionSelectedEnum.ActionSelected.MOVE:
			selected_player_unit.combat_action_selected = ActionSelectedEnum.ActionSelected.MOVE
		else:
			selected_player_unit.combat_action_selected = ActionSelectedEnum.ActionSelected.NONE

func attack_button_signal_emitted() -> void:
	if not selected_player_unit:
		select_new_player_unit(player_units_array.array[player_units_array.position])
	if enemy_units_array.array.size() <= 0:
		return
	if selected_player_unit.combat_action_selected != ActionSelectedEnum.ActionSelected.ATTACK:
		selected_player_unit.combat_action_selected = ActionSelectedEnum.ActionSelected.ATTACK
		swap_camera_unit_array(enemy_units_array)
		camera_origin.can_move = false
	else:
		selected_player_unit.combat_action_selected = ActionSelectedEnum.ActionSelected.NONE
		selected_enemy_unit.set_selected_false()
		swap_camera_unit_array(player_units_array)
		camera_origin.can_move = true

func confirm_target_signal_emitted() -> void:
	if not selected_player_unit:
		return
	if enemy_units_array.array.size() <= 0:
		battle_ui.confirm_target_button.hide()
		battle_ui.reset_buttons_colors()
		return
	selected_player_unit.set_attack_target(selected_enemy_unit)
	selected_enemy_unit.set_selected_false()
	swap_camera_unit_array(player_units_array)
	selected_player_unit.reset_combat_action_selected()
	battle_ui.confirm_target_button.hide()
	battle_ui.reset_buttons_colors()

func skill_button_signal_emitted() -> void:
	if not selected_player_unit:
		return
	if selected_player_unit.combat_action_selected != ActionSelectedEnum.ActionSelected.SKILL:
		selected_player_unit.combat_action_selected = ActionSelectedEnum.ActionSelected.SKILL
	else:
		selected_player_unit.combat_action_selected = ActionSelectedEnum.ActionSelected.NONE

func remove_dead_unit_from_groups(dead_unit: BaseUnit) -> void:
	if dead_unit is PlayerUnit:
		if camera_origin.current_unit_array == player_units_array:
			dead_unit.remove_from_group("player_units")
			dead_unit.free_after_death()
			update_player_units_array()
			update_camera_unit_array(player_units_array)
		else:
			dead_unit.remove_from_group("player_units")
			dead_unit.free_after_death()
			update_player_units_array()
	elif dead_unit is EnemyUnit:
		if camera_origin.current_unit_array == enemy_units_array:
			dead_unit.remove_from_group("enemy_units")
			dead_unit.free_after_death()
			update_camera_unit_array(enemy_units_array)
			update_enemy_units_array()
		else:
			dead_unit.remove_from_group("enemy_units")
			dead_unit.free_after_death()
			update_enemy_units_array()

func swap_camera_unit_array(new_unit_array: UnitArray) -> void:
	camera_origin.current_unit_array = new_unit_array
	move_camera_to_unit(camera_origin.current_unit_array.array[camera_origin.current_unit_array.position])

func update_player_units_array() -> void:
	player_units_array.array = get_tree().get_nodes_in_group("player_units")
	player_units_array.position = 0
	if player_units_array.array.size() > 0:
		move_camera_to_unit(player_units_array.array[player_units_array.position])

func update_enemy_units_array() -> void:
	enemy_units_array.array = get_tree().get_nodes_in_group("enemy_units")
	enemy_units_array.position = 0
	if enemy_units_array.array.size() > 0:
		selected_enemy_unit = enemy_units_array.array[enemy_units_array.position]

func release_camera() -> void:
	camera_can_follow_unit = false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_unpause"):
		pause_pressed()
	
	if event.is_action_pressed("next unit"):
		if camera_origin.current_unit_array.position + 1 <= camera_origin.current_unit_array.array.size() - 1:
			camera_origin.current_unit_array.position += 1
		else:
			camera_origin.current_unit_array.position = 0
		move_camera_to_next_unit_in_array()
		if camera_origin.current_unit_array == player_units_array:
			get_tree().call_group("player_units", "reset_combat_action_selected")
			if selected_player_unit:
				selected_player_unit.reset_combat_action_selected()
			battle_ui.reset_buttons_colors()
		
	if event.is_action_pressed("previous unit"):
		if camera_origin.current_unit_array.position - 1 >= 0:
			camera_origin.current_unit_array.position -= 1
		else:
			camera_origin.current_unit_array.position = camera_origin.current_unit_array.array.size() - 1
		move_camera_to_previous_unit_in_array()
		if camera_origin.current_unit_array == player_units_array:
			get_tree().call_group("player_units", "reset_combat_action_selected")
			if selected_player_unit:
				selected_player_unit.reset_combat_action_selected()
			battle_ui.reset_buttons_colors()
		
	if event.is_action_pressed("camera_follow_unit"):
		move_camera_to_unit(selected_player_unit)

func _unhandled_input(event: InputEvent) -> void:
	if selected_player_unit:
		if event.is_action_pressed("left click") and selected_player_unit.selected:
			match selected_player_unit.combat_action_selected:
				# No action/inspection
				ActionSelectedEnum.ActionSelected.NONE: pass
				# Move
				ActionSelectedEnum.ActionSelected.MOVE: 
					var ray := selected_player_unit._mouse_screen_to_world(camera_origin.camera, 1)
					selected_player_unit.set_manual_move_target(ray)
					
				# Attack
				#ActionSelectedEnum.ActionSelected.ATTACK: print("attack")
				
				# Skill
				ActionSelectedEnum.ActionSelected.SKILL: print("skill")
		
		if event.is_action_pressed("right click") and selected_player_unit.selected and selected_player_unit.paused and selected_player_unit.combat_action_selected != 0:
			GlobalSignals.cancel_action_pressed.emit()
			battle_ui.reset_buttons_colors()
			battle_ui.confirm_target_button.hide()
			if selected_player_unit:
				selected_player_unit.reset_combat_action_selected()
			if selected_enemy_unit:
				selected_enemy_unit.set_selected_false()
			swap_camera_unit_array(player_units_array)

func select_new_enemy_unit(new_selected_enemy_unit: EnemyUnit) -> void:
	if selected_enemy_unit:
		selected_enemy_unit.set_selected_false()
	selected_enemy_unit = new_selected_enemy_unit
	selected_enemy_unit.set_selected_true()

func select_new_player_unit(new_selected_player_unit: PlayerUnit) -> void:
	if selected_player_unit:
		selected_player_unit.set_selected_false()
	camera_can_follow_unit = false
	selected_player_unit = new_selected_player_unit
	selected_player_unit.set_selected_true()

func update_camera_unit_array(new_unit_array: UnitArray) -> void:
	camera_origin.current_unit_array = new_unit_array
	camera_origin.current_unit_array.position = 0

func move_camera_to_next_unit_in_array() -> void:
	if camera_origin.current_unit_array.array.size() <= 0:
		return
	move_camera_to_unit(camera_origin.current_unit_array.array[camera_origin.current_unit_array.position])
	if camera_origin.current_unit_array == player_units_array:
		select_new_player_unit(camera_origin.current_unit_array.array[camera_origin.current_unit_array.position])
	elif camera_origin.current_unit_array == enemy_units_array:
		select_new_enemy_unit(camera_origin.current_unit_array.array[camera_origin.current_unit_array.position])

func move_camera_to_previous_unit_in_array() -> void:
	if camera_origin.current_unit_array.array.size() <= 0:
		return
	move_camera_to_unit(camera_origin.current_unit_array.array[camera_origin.current_unit_array.position])
	if camera_origin.current_unit_array == player_units_array:
		select_new_player_unit(camera_origin.current_unit_array.array[camera_origin.current_unit_array.position])
	elif camera_origin.current_unit_array == enemy_units_array:
		select_new_enemy_unit(camera_origin.current_unit_array.array[camera_origin.current_unit_array.position])

func move_camera_to_unit(unit: BaseUnit) -> void:
	if camera_origin.current_unit_array == enemy_units_array:
		camera_can_follow_unit = false
	
	if tween_node:
		tween_node.kill()
	
	# Create a new tween
	var tween := create_tween()
	# Animate the 'position' property to the target over 0.4 seconds
	#camera_position.position = char_1.position
	
	tween.tween_property(camera_origin, "position", Vector3(unit.position.x, camera_origin.position.y, unit.position.z), 0.4)
	camera_origin.move_target = Vector3(unit.position.x, camera_origin.position.y, unit.position.z)
	await tween.finished
	
	if camera_origin.current_unit_array == player_units_array:
		camera_can_follow_unit = true
