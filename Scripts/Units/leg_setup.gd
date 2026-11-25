class_name LegSetup
extends Resource
## Describes one leg for ProceduralLegs. Create one per leg in the model scene.

## First bone of the leg chain (the "hip").
@export var root_bone: String
## Last bone of the leg chain (the tip of the foot). It must be the root bone's
## descendant. This is the bone that gets planted on the ground.
@export var end_bone: String
## Optional. A bone whose rest position is where this leg's knee should point
## to (the "pole" or "elbow target" bone from the rig). The knee magnet is
## placed exactly on it. If empty, the magnet is derived from the knee's rest
## pose instead.
@export var pole_bone: String
## Legs in the same group step together. Use 0 and 1 and alternate them
## (tripod gait for six legs: front-left, middle-right, back-left vs the rest).
@export_range(0, 1) var gait_group: int = 0
