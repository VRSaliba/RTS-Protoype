extends Node3D

@onready var camera_rotation: Node3D = $"Camera Rotation"
@onready var camera_zoom_pivot: Node3D = $"Camera Rotation/Camera Zoom Pivot"
@onready var camera: Camera3D = $"Camera Rotation/Camera Zoom Pivot/Camera3D"

var min_move_speed := 0.1
var max_move_speed := 0.8
var proportional_speed_to_zoom: float
var move_target: Vector3

var rotate_keys_speed = 2
var rotate_keys_target: float

var zoom_speed := 3.0
var zoom_target: float
var min_zoom := -13.0
var max_zoom := 20.0

var mouse_sensitivity := 0.2

var edge_size := 5.0
var scroll_speed := 0.6

var current_unit_array: UnitArray = UnitArray.new([], 0)

var can_move: bool = true

func _ready() -> void:
	move_target = position
	rotate_keys_target = rotation_degrees.y
	zoom_target = camera.position.z

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_action_pressed("rotate mouse"):
		rotate_keys_target -= event.relative.x * mouse_sensitivity
		camera_rotation.rotation_degrees.x -= event.relative.y * mouse_sensitivity
		camera_rotation.rotation_degrees.x = clamp(camera_rotation.rotation_degrees.x, -35, 15)
	
	if event is InputEventKey and (Input.is_action_just_pressed("up") or Input.is_action_just_pressed("down") or Input.is_action_just_pressed("left") or Input.is_action_just_pressed("right")):
		GlobalSignals.camera_moved.emit()
	
	#if event is InputEventKey and (Input.is_action_just_released("up") or Input.is_action_just_released("down") or Input.is_action_just_released("left") or Input.is_action_just_released("right")):
		#move_target = position

func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("rotate mouse"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if Input.is_action_just_released("rotate mouse"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Trecho que define movimento da camera quando mouse encosta na borda da camera
	#var mouse_pos = get_viewport().get_mouse_position()
	#var viewport_size = get_viewport().get_visible_rect().size
	#var scroll_direction = Vector3.ZERO
	#if mouse_pos.x < edge_size:
		#scroll_direction.x = -1
	#elif mouse_pos.x > viewport_size.x - edge_size:
		#scroll_direction.x = 1
	#
	#if mouse_pos.y < edge_size:
		#scroll_direction.z = -1
	#elif mouse_pos.y > viewport_size.y - edge_size:
		#scroll_direction.z = 1
	#move_target += transform.basis * scroll_direction * scroll_speed
	#==============================================
	
	var input_directions = Input.get_vector("left", "right", "up", "down")
	var movement_direction = (transform.basis * Vector3(input_directions.x, 0, input_directions.y)).normalized()
	var rotate_keys = Input.get_axis("rotate left", "rotate right")
	var zoom_dir = float(Input.is_action_just_released("camera zoom out")) - int(Input.is_action_just_released("camera zoom in"))
	
	rotate_keys_target += rotate_keys * rotate_keys_speed
	zoom_target += zoom_dir * zoom_speed
	zoom_target = clamp(zoom_target, min_zoom, max_zoom)
	
	proportional_speed_to_zoom = remap(zoom_target, min_zoom, max_zoom, min_move_speed, max_move_speed)
	
	move_target += proportional_speed_to_zoom * movement_direction
	
	position = lerp(position, move_target, 0.2)
	rotation_degrees.y = lerp(rotation_degrees.y, rotate_keys_target, 0.5)
	camera.position.z = lerp(camera.position.z, zoom_target, 0.15)
