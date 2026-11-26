class_name LegSetup
extends Resource
## Describes one leg for ProceduralLegs. Create one per leg in the model scene.
## The leg is solved as hip -> knee -> ankle, so the three bones must be a
## direct parent -> child -> child chain.

## The hip: the first bone of the leg.
@export var root_bone: String
## The ankle: the last bone of the IK, two bones below the hip. The foot bone
## hangs below it and is kept flat on the ground.
@export var end_bone: String
## The foot tip: the bone at the very end of the foot, which touches the ground.
## Leave empty to use the first bone below the ankle.
@export var tip_bone: String
## Optional. A bone whose rest position is where this leg's knee should point
## to (the "pole" or "elbow target" bone from the rig). If empty, the pole is
## derived from the knee's rest pose instead.
@export var pole_bone: String
## Legs in the same group step together. Use 0 and 1 and alternate them
## (tripod gait for six legs: front-left, middle-right, back-left vs the rest).
@export_range(0, 1) var gait_group: int = 0
