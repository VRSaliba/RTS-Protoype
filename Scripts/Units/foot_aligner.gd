class_name FootAligner
extends SkeletonModifier3D
## Runs after the leg IK (it is created right below it under the Skeleton3D).
## It sets the orientation of each foot bone, so feet stay flat on the ground
## instead of turning with the leg. ProceduralLegs feeds it the target
## orientations every frame.

# bone index -> Basis (in skeleton space)
var _targets: Dictionary = {}


func set_foot(bone: int, basis_in_skeleton: Basis) -> void:
	_targets[bone] = basis_in_skeleton


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for bone in _targets:
		var pose := skeleton.get_bone_global_pose(bone)
		pose.basis = _targets[bone]
		skeleton.set_bone_global_pose(bone, pose)
