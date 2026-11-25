extends Control

const ActionSelectedEnum = preload("uid://nf7pc7tlapya")

@onready var pause_label: Label = $"MarginContainer/VBoxContainer/Pause Label"
@onready var time_label: Label = $"MarginContainer/VBoxContainer2/Time Label"

@onready var buttons_container: HBoxContainer = $MarginContainer/VBoxContainer/HBoxContainer

@onready var move_button: Button = $"MarginContainer/VBoxContainer/HBoxContainer/Move Button"
@onready var attack_button: Button = $"MarginContainer/VBoxContainer/HBoxContainer/Attack Button"
@onready var skill_button: Button = $"MarginContainer/VBoxContainer/HBoxContainer/Skill Button"
@onready var confirm_target_button: Button = $"MarginContainer/VBoxContainer/Confirm Target Button"

var move_button_pressed: bool = false
var attack_button_pressed: bool = false
var skill_button_pressed: bool = false

func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	pass

func change_button_font_color(button: Button, color: Color) -> void:
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", color)

func show_time_label() -> void:
	if time_label:
		time_label.show()

func hide_time_label() -> void:
	if time_label:
		time_label.hide()

func update_time_label(new_text: String) -> void:
	if time_label:
		time_label.text = new_text

func show_pause_label() -> void:
	if pause_label:
		pause_label.show()

func hide_pause_label() -> void:
	if pause_label:
		pause_label.hide()

func update_pause_label(new_text: String) -> void:
	if pause_label:
		pause_label.text = new_text

func hide_buttons_container() -> void:
	if buttons_container:
		buttons_container.hide()

func show_buttons_container() -> void:
	if buttons_container:
		buttons_container.show()

func reset_buttons_colors() -> void:
	move_button_pressed = false
	change_button_font_color(move_button, Color.WHITE)
	attack_button_pressed = false
	change_button_font_color(attack_button, Color.WHITE)
	skill_button_pressed = false
	change_button_font_color(skill_button, Color.WHITE)

func _on_move_button_pressed() -> void:
	GlobalSignals.move_button_pressed.emit()
	attack_button_pressed = false
	skill_button_pressed = false
	confirm_target_button.hide()
	if move_button_pressed:
		move_button_pressed = false
		change_button_font_color(move_button, Color.WHITE)
		change_button_font_color(attack_button, Color.WHITE)
		change_button_font_color(skill_button, Color.WHITE)
	else:
		move_button_pressed = true
		change_button_font_color(move_button, Color.GREEN)
		change_button_font_color(attack_button, Color.WHITE)
		change_button_font_color(skill_button, Color.WHITE)

func _on_attack_button_pressed() -> void:
	GlobalSignals.attack_button_pressed.emit()
	move_button_pressed = false
	skill_button_pressed = false
	if attack_button_pressed:
		attack_button_pressed = false
		confirm_target_button.hide()
		change_button_font_color(move_button, Color.WHITE)
		change_button_font_color(attack_button, Color.WHITE)
		change_button_font_color(skill_button, Color.WHITE)
	else:
		attack_button_pressed = true
		confirm_target_button.show()
		change_button_font_color(move_button, Color.WHITE)
		change_button_font_color(attack_button, Color.GREEN)
		change_button_font_color(skill_button, Color.WHITE)

func _on_skill_button_pressed() -> void:
	GlobalSignals.skill_button_pressed.emit()
	move_button_pressed = false
	attack_button_pressed = false
	confirm_target_button.hide()
	if skill_button_pressed:
		skill_button_pressed = false
		change_button_font_color(move_button, Color.WHITE)
		change_button_font_color(attack_button, Color.WHITE)
		change_button_font_color(skill_button, Color.WHITE)
	else:
		skill_button_pressed = true
		change_button_font_color(move_button, Color.WHITE)
		change_button_font_color(attack_button, Color.WHITE)
		change_button_font_color(skill_button, Color.GREEN)

func _on_confirm_target_button_pressed() -> void:
	GlobalSignals.confirm_target_pressed.emit()
