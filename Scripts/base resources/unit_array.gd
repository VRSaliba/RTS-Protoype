extends Resource
class_name UnitArray

var array: Array[Node]
var position: int

func _init(init_array: Array[Node], init_position: int) -> void:
	array = init_array
	position = init_position
