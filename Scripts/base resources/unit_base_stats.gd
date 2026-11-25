extends Resource
class_name UnitBaseStats

@export var max_health_points: float
@export var current_health_points: float
@export var mana_points: float
@export var mana_regen: float
@export var movement_speed: float
## Seconds the unit must wait after a hit connects before it can attack again.
@export var attack_cooldown: float = 1.0
## How fast the attack animation plays (1.0 = normal). Does not change the cooldown.
@export var attack_speed: float = 1.0
@export var attack: int
@export var defense: int
@export var skill_cooldown_reduction: float
