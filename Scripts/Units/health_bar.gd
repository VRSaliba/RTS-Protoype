extends Sprite3D

@onready var progress_bar: ProgressBar = $SubViewport/Panel/ProgressBar
@onready var state_label: Label = $"SubViewport/State Label"

func _ready() -> void:
	pass

#func take_damage(damage: int) -> void:
	#real_hp -= damage
	#create_tween().tween_property(progress_bar, "value", real_hp, 0.3)

func _process(_delta: float) -> void:
	pass
