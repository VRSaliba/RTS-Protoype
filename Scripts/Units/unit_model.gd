class_name UnitModel
extends Node3D
## Attach this to the ROOT node of every model scene (the inherited scene made
## from your .glb). It describes this particular model so BaseUnit can resize
## its collision, health bar and selection rings to fit.
##
## Convention: the model's origin sits at its FEET (the Blender default).
## Add a ModelAnimator node to the model scene as well.

@export_group("Body")
## Collision capsule radius for this model.
@export var radius: float = 0.4
## Collision capsule height for this model (should cover the whole model).
@export var height: float = 1.5

@export_group("Layout")
## Space between the top of the capsule and the health bar.
@export var health_bar_gap: float = 0.374
## How far the selection rings float above the ground.
@export var ring_ground_offset: float = 0.08
## Rotate the model if it faces the wrong way in-game.
@export var yaw_offset_degrees: float = 0.0

@export_group("Animation")
## Leave empty to auto-find a ModelAnimator inside this model scene.
@export var animator: ModelAnimator


func _ready() -> void:
	rotation_degrees.y += yaw_offset_degrees
	if animator == null:
		animator = _find_animator(self)
	if animator == null:
		push_warning("UnitModel '%s' has no ModelAnimator." % name)


func _find_animator(node: Node) -> ModelAnimator:
	for child in node.get_children():
		if child is ModelAnimator:
			return child
		var found := _find_animator(child)
		if found:
			return found
	return null
