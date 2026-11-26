class_name FingerLagModifier
extends SkeletonModifier3D
## Rotates the finger (foot tip) bones around their own X axis each frame, on top
## of whatever pose they already have. It runs after the leg IK and the foot
## alignment (it is created after them under the Skeleton3D). ProceduralLegs
## feeds it the angle for every finger.
##
## Every tip bone in the K-buto rig has its local X axis horizontal, which makes
## it the hinge that tilts the claws up and down.

# bone index -> angle in radians
var _angles: Dictionary = {}


func set_angle(bone: int, angle: float) -> void:
	_angles[bone] = angle


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for bone in _angles:
		var turn := Quaternion(Vector3(1.0, 0.0, 0.0), _angles[bone])
		skeleton.set_bone_pose_rotation(bone,
			(skeleton.get_bone_pose_rotation(bone) * turn).normalized())
