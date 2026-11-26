class_name BodyWobbleModifier
extends SkeletonModifier3D
## Adds a small movement and rotation on top of a bone's current pose each
## frame. It is created under the Skeleton3D BEFORE the leg IK, so the hips move
## first and the IK then keeps the planted feet on the ground. ProceduralLegs
## feeds it the wobble every frame.

# bone index -> [offset in skeleton space (Vector3), rotation in skeleton space (Basis)]
# Bones are processed in the order they were first set (the body before the abdomen).
var _bones: Dictionary = {}


func set_bone(bone: int, offset: Vector3, rotation: Basis) -> void:
	_bones[bone] = [offset, rotation]


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for bone in _bones:
		var entry: Array = _bones[bone]
		var parent := skeleton.get_bone_parent(bone)
		var parent_basis := Basis.IDENTITY
		if parent >= 0:
			parent_basis = skeleton.get_bone_global_pose(parent).basis.orthonormalized()
		var to_parent_space := parent_basis.inverse()
		
		# Offset and rotation are given in skeleton space; the bone's pose is in
		# its parent's space.
		var local_offset: Vector3 = to_parent_space * entry[0]
		var local_rotation: Basis = to_parent_space * entry[1] * parent_basis
		skeleton.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone) + local_offset)
		skeleton.set_bone_pose_rotation(bone,
			(local_rotation.get_rotation_quaternion() * skeleton.get_bone_pose_rotation(bone)).normalized())
