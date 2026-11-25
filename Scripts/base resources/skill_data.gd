class_name SkillData
extends Resource
## Data describing one skill. Create one .tres per skill, then add it to a
## UnitData's "skills" array. (Data only for now; the effect logic comes later.)

@export var display_name: String
@export var icon: Texture2D
@export_multiline var description: String
@export var cooldown: float = 5.0
@export var mana_cost: float = 0.0
@export var cast_range: float = 3.0
## Generic animation state played on the model. It must be a key in that
## model's ModelAnimator animation_map (for example "special").
@export var animation_state: StringName = &"special"
