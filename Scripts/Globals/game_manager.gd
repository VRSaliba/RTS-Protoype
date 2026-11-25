extends Node
class_name GameManager

const LEVEL_1 = preload("uid://b63f3b4bu2vdi")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	add_child(LEVEL_1.instantiate())
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass
