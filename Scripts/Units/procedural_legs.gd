class_name ProceduralLegs
extends Node
## Procedural leg stepping for a model, driven by TwoBoneIK3D (Godot 4.6+).
##
## Each leg is solved as hip -> knee -> ankle with a pole target, so the knee
## always bends toward the pole (the rig's "elbow target" bone). The foot bone
## below the ankle is kept flat on the ground by FootAligner.
##
## Put this node in the MODEL scene (next to ModelAnimator) and fill in `legs`.
## At runtime it creates one TwoBoneIK3D and one FootAligner under the
## Skeleton3D, plus an ankle target and a pole marker per leg. While the unit
## walks, feet stay planted on the ground and step in an alternating (tripod)
## pattern as the body moves away from them. In every other state the IK fades
## out and the normal animation takes over again.
##
## All step sizes are fractions of each leg's own length, so they keep working
## if you rescale the model.

## One entry per leg.
@export var legs: Array[LegSetup] = []
## Leave empty to auto-find the Skeleton3D inside this model.
@export var skeleton: Skeleton3D
## Leave empty to auto-find the ModelAnimator in this model.
@export var animator: ModelAnimator
## IK is active while the animator is in one of these states.
@export var active_states: PackedStringArray = ["walk"]

@export_group("Stepping")
## A planted foot steps once the body has carried it this far from its home
## spot (fraction of the leg's length): how far the leg STRETCHES before it
## moves. A full stride is about this plus the landing lead below.
@export var step_trigger_ratio: float = 0.3
## A foot steps no matter what once it is this far (fraction of leg length).
@export var force_step_ratio: float = 0.5
## Targets are never placed farther than this fraction of the leg's length from
## its hip. This is the furthest the leg can ever stretch.
@export_range(0.5, 1.0) var max_reach_ratio: float = 0.97

@export_group("Step speed")
## Speed of the foot's swing forward. 1 = automatic (follows the unit's speed),
## 2 = twice as fast, 0.5 = half as fast.
@export var horizontal_speed: float = 1.0
## How fast the foot rises. 1 = it takes half of the swing to reach full height.
@export var lift_speed: float = 1.0
## How fast the foot comes back down. 1 = it takes half of the swing.
@export var lower_speed: float = 1.0
## How high the foot lifts mid-step (fraction of leg length).
@export var step_height_ratio: float = 0.25
## Limits, in seconds, for the automatic swing time (before horizontal_speed).
@export var min_step_duration: float = 0.08
@export var max_step_duration: float = 0.3

@export_group("Landing")
## How far AHEAD of its home spot the foot lands, as a multiplier of the
## automatic value. 0 = lands right on the home spot, 2 = twice as far ahead.
@export var landing_lead_scale: float = 1.0
## The most the landing spot can lead the home spot (fraction of leg length).
@export var landing_lead_max_ratio: float = 0.27
## Moves every foot's home spot forward (+) or back (-) relative to the body
## (fraction of leg length).
@export var home_forward_ratio: float = 0.0
## Moves every foot's home spot away from (+) or toward (-) the body's centre
## line (fraction of leg length).
@export var home_outward_ratio: float = 0.0

@export_group("Ground")
## Physics layers the feet can stand on. Put your floor and terrain on these
## layers (and keep units off them), or feet may land on other units.
@export_flags_3d_physics var ground_mask: int = 1
## The ground ray starts this far above the landing spot (fraction of leg length)...
@export var ground_ray_up_ratio: float = 0.6
## ...and ends this far below it.
@export var ground_ray_down_ratio: float = 1.0

@export_group("Knee")
## Only used for legs WITHOUT a pole bone: the pole starts at the knee's rest
## position and is lifted along the leg's own bend direction (fraction of leg
## length).
@export var knee_push_ratio: float = 0.3
## Keeps the knee bone's twist facing the pole, as it does in the rest pose.
## Turn off if the leg meshes look twisted.
@export var use_pole_twist: bool = true

@export_group("Blend")
## How fast the IK fades in and out when switching to or from walking.
@export var blend_speed: float = 8.0

@export_group("Debug")
## Prints the skeleton's bones and the IK setup once.
@export var debug_print: bool = false
## Shows a sphere on every ankle target (big) and every pole (small).
@export var debug_show_targets: bool = false


class Foot:
	var target: Node3D          # where the ankle should go (world)
	var pole: Node3D            # the pole the knee bends toward (world)
	var root_bone: int          # hip
	var end_bone: int           # ankle: last bone of the IK
	var home_skel: Vector3      # rest position of the foot tip, skeleton space
	var foot_vec_skel: Vector3  # rest vector ankle -> foot tip, skeleton space
	var ankle_basis_skel: Basis # rest orientation of the ankle bone, skeleton space
	var pole_skel: Vector3      # pole position, skeleton space
	var reach: float            # hip -> knee -> ankle length, world units
	var group: int = 0
	var planted: Vector3        # world position of the foot tip on the ground
	var normal: Vector3 = Vector3.UP
	var tip: Vector3            # current foot tip position (planted or mid-step)
	var step_from: Vector3
	var step_to: Vector3
	var step_from_normal: Vector3 = Vector3.UP
	var step_to_normal: Vector3 = Vector3.UP
	var step_time: float = 0.0
	var step_duration: float = 0.2  # horizontal swing time
	var lift_time: float = 0.1
	var lower_time: float = 0.1
	var stepping: bool = false


var _unit: CharacterBody3D
var _ik: TwoBoneIK3D
var _aligner: FootAligner
var _feet: Array[Foot] = []
var _blend: float = 0.0
var _was_active: bool = false
var _debug_printed: bool = false
var _debug_lines: Array[String] = []


func _ready() -> void:
	var root: Node = owner if owner != null else get_parent()
	if skeleton == null:
		skeleton = _find_skeleton(root)
	if animator == null:
		animator = _find_animator(root)
	_unit = _find_unit()
	if skeleton == null or _unit == null or legs.is_empty():
		push_warning("ProceduralLegs: needs a Skeleton3D, a CharacterBody3D parent and legs.")
		set_process(false)
		return
	if not ClassDB.class_exists("TwoBoneIK3D"):
		push_error("ProceduralLegs: this Godot version has no TwoBoneIK3D (it needs 4.6 or newer).")
		set_process(false)
		return
	_build()


func _build() -> void:
	var world_scale := skeleton.global_transform.basis.get_scale().x
	var valid_legs: Array[LegSetup] = []
	var middle_names: Array[String] = []
	var pole_twist: Array[Vector3] = []
	
	for leg in legs:
		var root_id := skeleton.find_bone(leg.root_bone)
		var end_id := skeleton.find_bone(leg.end_bone)
		if root_id < 0 or end_id < 0:
			push_error("ProceduralLegs: bone '%s' or '%s' not found in the skeleton." % [leg.root_bone, leg.end_bone])
			continue
		var middle_id := skeleton.get_bone_parent(end_id)
		if middle_id < 0 or skeleton.get_bone_parent(middle_id) != root_id:
			push_error("ProceduralLegs: '%s' must be the parent of the parent of '%s' (hip -> knee -> ankle)." % [leg.root_bone, leg.end_bone])
			continue
		var tip_id := skeleton.find_bone(leg.tip_bone) if leg.tip_bone != "" else -1
		if tip_id < 0:
			var kids := skeleton.get_bone_children(end_id)
			if kids.is_empty():
				push_error("ProceduralLegs: '%s' has no foot bone below it." % leg.end_bone)
				continue
			tip_id = kids[0]
		
		var hip_rest := skeleton.get_bone_global_rest(root_id)
		var knee_rest := skeleton.get_bone_global_rest(middle_id)
		var ankle_rest := skeleton.get_bone_global_rest(end_id)
		var tip_rest := skeleton.get_bone_global_rest(tip_id)
		var upper := (knee_rest.origin - hip_rest.origin).length()
		var lower := (ankle_rest.origin - knee_rest.origin).length()
		
		var foot := Foot.new()
		foot.group = leg.gait_group
		foot.root_bone = root_id
		foot.end_bone = end_id
		foot.reach = (upper + lower) * world_scale
		foot.home_skel = tip_rest.origin
		foot.foot_vec_skel = tip_rest.origin - ankle_rest.origin
		foot.ankle_basis_skel = ankle_rest.basis.orthonormalized()
		
		# Where the knee should point: the rig's own pole bone if there is one.
		var pole_id := skeleton.find_bone(leg.pole_bone) if leg.pole_bone != "" else -1
		if leg.pole_bone != "" and pole_id < 0:
			push_warning("ProceduralLegs: pole bone '%s' not found, using the knee's rest position." % leg.pole_bone)
		if pole_id >= 0:
			foot.pole_skel = skeleton.get_bone_global_rest(pole_id).origin
		else:
			var chord := ankle_rest.origin - hip_rest.origin
			var along := clampf((knee_rest.origin - hip_rest.origin).dot(chord) / maxf(chord.length_squared(), 0.0001), 0.0, 1.0)
			var bend := knee_rest.origin - (hip_rest.origin + chord * along)
			var bend_dir := bend.normalized() if bend.length() > 0.001 else Vector3.UP
			foot.pole_skel = knee_rest.origin + bend_dir * (upper + lower) * knee_push_ratio
		
		# Which side of the knee bone faces the pole in the rest pose, in the knee
		# bone's own space. It is made perpendicular to the lower leg, so it never
		# lines up with the bone's own direction.
		var twist := Vector3.ZERO
		if use_pole_twist:
			var lower_dir := (ankle_rest.origin - knee_rest.origin).normalized()
			var toward_pole := foot.pole_skel - knee_rest.origin
			toward_pole -= lower_dir * toward_pole.dot(lower_dir)
			if toward_pole.length() > 0.001:
				twist = knee_rest.basis.orthonormalized().inverse() * toward_pole.normalized()
		
		valid_legs.append(leg)
		_feet.append(foot)
		middle_names.append(skeleton.get_bone_name(middle_id))
		pole_twist.append(twist)
		_debug_lines.append("%s -> %s -> %s (foot %s) | reach %.2f | pole (skeleton space) %s" % [
			leg.root_bone, skeleton.get_bone_name(middle_id), leg.end_bone,
			skeleton.get_bone_name(tip_id), foot.reach, foot.pole_skel])
	
	# One TwoBoneIK3D handles every leg; the FootAligner is added after it so it
	# runs after the IK.
	_ik = TwoBoneIK3D.new()
	_ik.name = "LegIK"
	skeleton.add_child(_ik)
	_aligner = FootAligner.new()
	_aligner.name = "FootAligner"
	skeleton.add_child(_aligner)
	
	_ik.setting_count = valid_legs.size()
	for i in valid_legs.size():
		var foot := _feet[i]
		
		var target := Node3D.new()
		target.name = "AnkleTarget%d" % i
		target.top_level = true  # lives in world space, not carried by the unit
		add_child(target)
		foot.target = target
		var pole := Node3D.new()
		pole.name = "Pole%d" % i
		pole.top_level = true
		add_child(pole)
		foot.pole = pole
		if debug_show_targets:
			target.add_child(_make_debug_sphere(0.05))
			pole.add_child(_make_debug_sphere(0.025))
		
		_ik.set_root_bone_name(i, valid_legs[i].root_bone)
		_ik.set_middle_bone_name(i, middle_names[i])
		_ik.set_end_bone_name(i, valid_legs[i].end_bone)
		_ik.set_target_node(i, _ik.get_path_to(target))
		_ik.set_pole_node(i, _ik.get_path_to(pole))
		if pole_twist[i] != Vector3.ZERO and _ik.has_method("set_pole_direction_vector"):
			_ik.set_pole_direction_vector(i, pole_twist[i])
	
	_ik.influence = 0.0
	_aligner.influence = 0.0
	_replant()


func _make_debug_sphere(radius: float) -> MeshInstance3D:
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	sphere.mesh = mesh
	return sphere


func _process(delta: float) -> void:
	if _feet.is_empty():
		return
	var active := _wants_active()
	_blend = move_toward(_blend, 1.0 if active else 0.0, delta * blend_speed)
	_ik.influence = _blend
	_aligner.influence = _blend
	_ik.active = _blend > 0.001
	_aligner.active = _blend > 0.001
	
	if active and not _was_active:
		_replant()  # start walking with every foot at its home position
		_print_debug()
	elif not active and _blend <= 0.001:
		_replant()  # idle: keep the targets at home so they are ready
	_was_active = active
	
	if active and not _unit_is_paused():
		_update_steps(delta)
	for foot in _feet:
		_apply_foot(foot)


func _wants_active() -> bool:
	return animator != null and String(animator.current_state) in active_states


func _unit_is_paused() -> bool:
	return "paused" in _unit and _unit.paused


# Puts every foot back at its home position, standing still.
func _replant() -> void:
	for foot in _feet:
		var hit := _ground_hit(foot, _home_world(foot))
		foot.stepping = false
		foot.planted = hit["position"]
		foot.normal = hit["normal"]
		foot.tip = foot.planted
		_apply_foot(foot)


func _home_world(foot: Foot) -> Vector3:
	var scale_factor := maxf(skeleton.global_transform.basis.get_scale().x, 0.0001)
	var leg_length := foot.reach / scale_factor  # in skeleton units
	var shift := Vector3(signf(foot.home_skel.x) * home_outward_ratio, 0.0, home_forward_ratio) * leg_length
	return skeleton.global_transform * (foot.home_skel + shift)


# Sends a foot's current state to the IK: the ankle target, the pole, and the
# orientation the foot bone should have.
func _apply_foot(foot: Foot) -> void:
	var skeleton_basis := skeleton.global_transform.basis
	var tilt := Basis(Quaternion(Vector3.UP, foot.normal))  # flat -> slope
	
	# The foot tip should touch the ground, so the ankle sits one foot-length
	# above it, in the direction the (tilted) foot points.
	var foot_world := tilt * (skeleton_basis * foot.foot_vec_skel)
	foot.target.global_position = _clamp_to_reach(foot, foot.tip - foot_world)
	foot.pole.global_position = skeleton.global_transform * foot.pole_skel
	
	var ortho := skeleton_basis.orthonormalized()
	_aligner.set_foot(foot.end_bone, ortho.inverse() * tilt * ortho * foot.ankle_basis_skel)


# Keeps the ankle within the leg's reach so the solver never has to chase a
# point it can't get to (which makes legs flail and twist).
func _clamp_to_reach(foot: Foot, pos: Vector3) -> Vector3:
	var hip := skeleton.global_transform * skeleton.get_bone_global_pose(foot.root_bone).origin
	var offset := pos - hip
	var max_length := foot.reach * max_reach_ratio
	if offset.length() > max_length:
		return hip + offset.normalized() * max_length
	return pos


# Drops a ray straight down at this spot and returns the ground point and its
# surface normal (the spot itself, facing up, if nothing is there or it is
# only another unit).
func _ground_hit(foot: Foot, pos: Vector3) -> Dictionary:
	var exclude: Array[RID] = [_unit.get_rid()]
	var query := PhysicsRayQueryParameters3D.create(
		pos + Vector3.UP * foot.reach * ground_ray_up_ratio,
		pos - Vector3.UP * foot.reach * ground_ray_down_ratio,
		ground_mask, exclude)
	var hit := _unit.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit["collider"] is CharacterBody3D:
		return {"position": pos, "normal": Vector3.UP}
	return {"position": hit["position"], "normal": hit["normal"]}


func _update_steps(delta: float) -> void:
	var velocity := Vector3(_unit.velocity.x, 0.0, _unit.velocity.z)
	var group_stepping := [false, false]
	for foot in _feet:
		if foot.stepping:
			group_stepping[foot.group] = true
	
	for foot in _feet:
		if foot.stepping:
			foot.step_time += delta
			var t := clampf(foot.step_time / foot.step_duration, 0.0, 1.0)
			var eased := t * t * (3.0 - 2.0 * t)
			var pos := foot.step_from.lerp(foot.step_to, eased)
			# Height: rises for lift_time from the start and comes back down during
			# the last lower_time, so lifting and lowering have their own speeds.
			var rise := clampf(foot.step_time / foot.lift_time, 0.0, 1.0)
			var fall := clampf((foot.step_duration - foot.step_time) / foot.lower_time, 0.0, 1.0)
			var height := minf(rise, fall)
			pos.y += height * height * (3.0 - 2.0 * height) * step_height_ratio * foot.reach
			foot.tip = pos
			foot.normal = foot.step_from_normal.slerp(foot.step_to_normal, eased)
			if t >= 1.0:
				foot.stepping = false
				foot.planted = foot.step_to
				foot.normal = foot.step_to_normal
				foot.tip = foot.planted
			continue
		
		foot.tip = foot.planted
		var home := _home_world(foot)
		var offset := foot.planted - home
		offset.y = 0.0
		var distance := offset.length()
		var trigger := foot.reach * step_trigger_ratio
		var force := foot.reach * force_step_ratio
		var other_group_busy: bool = group_stepping[1 - foot.group]
		if distance > force or (distance > trigger and not other_group_busy):
			_begin_step(foot, home, velocity, trigger)
			group_stepping[foot.group] = true


func _begin_step(foot: Foot, home: Vector3, velocity: Vector3, trigger: float) -> void:
	var speed := velocity.length()
	var duration := max_step_duration
	if speed > 0.01:
		# One group is planted while the other swings, so a swing should take
		# about as long as a planted foot needs to cover a stride.
		duration = clampf(2.0 * trigger / speed * 0.9, min_step_duration, max_step_duration)
	duration /= maxf(horizontal_speed, 0.05)
	# Land slightly ahead of where the body will have carried the home spot by
	# the end of the step, so the foot can trail behind it during the stance.
	var lead := (velocity * duration * 0.5 * landing_lead_scale).limit_length(foot.reach * landing_lead_max_ratio)
	var landing := home + velocity * duration + lead
	var hit := _ground_hit(foot, Vector3(landing.x, foot.planted.y, landing.z))
	foot.stepping = true
	foot.step_time = 0.0
	foot.step_duration = duration
	foot.lift_time = maxf(duration * 0.5 / maxf(lift_speed, 0.05), 0.001)
	foot.lower_time = maxf(duration * 0.5 / maxf(lower_speed, 0.05), 0.001)
	foot.step_from = foot.planted
	foot.step_to = hit["position"]
	foot.step_from_normal = foot.normal
	foot.step_to_normal = hit["normal"]


func _print_debug() -> void:
	if not debug_print or _debug_printed:
		return
	_debug_printed = true
	var bones: Array[String] = []
	for b in skeleton.get_bone_count():
		bones.append(skeleton.get_bone_name(b))
	print("[ProceduralLegs] skeleton bones: ", bones)
	for line in _debug_lines:
		print("[ProceduralLegs] ", line)


func _find_unit() -> CharacterBody3D:
	var node: Node = get_parent()
	while node != null:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null


func _find_animator(node: Node) -> ModelAnimator:
	for child in node.get_children():
		if child is ModelAnimator:
			return child
		var found := _find_animator(child)
		if found:
			return found
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null
