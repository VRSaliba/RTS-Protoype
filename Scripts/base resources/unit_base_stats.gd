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

@export_group("Movement")
## How fast the unit turns toward where it is going, in radians per second.
@export var turn_speed: float = 6.0
## If the unit has to turn by this many degrees or more to face where it is
## going, it turns on the spot first. Below it, the unit moves while turning.
@export_range(0.0, 180.0) var turn_in_place_angle: float = 90.0
## Movement speed while turning, as a fraction of normal speed. It scales from
## 1.0 (facing the right way) down to this value (right at turn_in_place_angle).
@export_range(0.0, 1.0) var min_turn_move_ratio: float = 0.5

@export_group("Combat")
## How far past touching (the two body radii) the unit can still strike.
@export var attack_range_margin: float = 0.6
## FALLBACK only: used when the attack animation has no "hit" event.
## Seconds after the attack animation starts before damage is applied.
@export var attack_hit_delay: float = 0.6
