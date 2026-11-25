extends BaseBattleLevel

@onready var navigation_region_3d: NavigationRegion3D = $Terrain/NavigationRegion3D

var can_command: bool = true

func _ready() -> void:
	super()
