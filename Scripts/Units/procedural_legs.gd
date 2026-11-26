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

@export_group("Leg zones")
## Each leg may only roam inside its own zone along the body, so neighbouring
## legs on the same side never cross. 1.0 = the zone reaches halfway to the
## next leg; lower keeps the legs further apart.
@export_range(0.1, 1.0) var zone_ratio: float = 0.9
## Feet must stay at least this fraction of their normal sideways distance from
## the body's centre line, so they never end up under the model (also while
## turning). 0 = no limit.
@export_range(0.0, 1.0) var min_lateral_ratio: float = 0.55
## The same limit while the unit is TURNING: tighter, so the feet on the inside of
## the turn stay well out from under the body.
@export_range(0.0, 1.0) var min_lateral_ratio_turning: float = 0.8
## The turning rate (radians per second) at which the tighter limit fully applies.
@export var turn_tighten_rate: float = 1.0

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

@export_group("Body wobble")
## Makes the body sway while walking, like a beetle's alternating tripod gait:
## the body leans and turns slightly toward the side of the legs that are
## holding it up, then the other side, and bobs a little with every step.
@export var wobble_enabled: bool = true
## The bone that moves the whole body (the root of the body in the skeleton).
@export var body_bone: String = "HeadBase"
## Optional. The abdomen's bone, which sways against the body for a looser feel.
@export var abdomen_bone: String = "BackLegsBase"
## Sideways lean in degrees. Positive leans toward the side with two supporting
## legs; negative the other way.
@export var wobble_roll_degrees: float = 4.0
## Turning of the body left and right in degrees. Positive turns the head away
## from the side of the front supporting leg; flip the sign if it looks wrong.
@export var wobble_yaw_degrees: float = 3.0
## How much the abdomen turns the opposite way, in degrees.
@export var wobble_abdomen_yaw_degrees: float = 4.0
## Sideways shift of the body toward the leaning side (fraction of leg length).
@export var wobble_sway_ratio: float = 0.03
## Up and down bob with every step (fraction of leg length). Negative makes the
## body dip instead of rise.
@export var wobble_bob_ratio: float = 0.02
## How quickly the wobble follows the legs. Higher = snappier, lower = smoother.
@export var wobble_smoothing: float = 20.0

@export_group("Finger lag")
## While walking, the fingers (the foot's tip bones) lag behind the foot's up and
## down movement, on a single axis: they tilt DOWN while the foot rises (first
## half of a step), UP while it comes back down (second half), then settle.
@export var finger_lag_enabled: bool = true
## How far the fingers tilt down while the foot rises, in degrees.
@export var finger_down_degrees: float = 12.0
## How far the fingers tilt up while the foot comes down, in degrees.
@export var finger_up_degrees: float = 12.0
## Seconds the fingers take to tilt all the way down.
@export var finger_down_time: float = 0.12
## Seconds the fingers take to tilt all the way up.
@export var finger_up_time: float = 0.12
## Seconds the fingers take to settle back to normal once the foot has landed.
@export var finger_return_time: float = 0.15
## Flips the tilt direction (down becomes up).
@export var finger_lag_invert: bool = false

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
	var side: float = 1.0       # +1 or -1: which side of the body the leg is on
	var leg_skel: float = 1.0   # leg length in skeleton units
	var z_back_room: float = 1.0   # how far behind its home spot the foot may go (skeleton units)
	var z_front_room: float = 1.0  # ...and how far ahead
	var planted: Vector3        # world position of the foot tip on the ground
	var normal: Vector3 = Vector3.UP
	var tip_bone: int = -1          # the finger bone
	var finger_phase: float = 0.0   # -1 foot rising (fingers go down), +1 foot falling (fingers go up), 0 planted
	var finger_pos: float = 0.0     # -1 fully down ... +1 fully up
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
	var needs_step: bool = false          # far enough from home (or out of its zone) to step
	var stepped_this_round: bool = false  # already had its step in the current round


var _unit: CharacterBody3D
var _ik: TwoBoneIK3D
var _aligner: FootAligner
var _feet: Array[Foot] = []
var _blend: float = 0.0
var _was_active: bool = false
var _debug_printed: bool = false
var _debug_lines: Array[String] = []
var _angular_velocity: float = 0.0  # the unit's turning rate, rad/s
var _lateral_ratio: float = 0.55    # the sideways limit in use right now
var _turn: int = 0                  # the gait group whose turn it is to step
var _wobble: BodyWobbleModifier
var _fingers: FingerLagModifier
var _body_bone: int = -1
var _abdomen_bone: int = -1
var _leg_skel_average: float = 1.0
var _wobble_lean: float = 0.0
var _wobble_bob: float = 0.0
var _prev_yaw: float = 0.0


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
		foot.tip_bone = tip_id
		foot.reach = (upper + lower) * world_scale
		foot.leg_skel = upper + lower
		foot.home_skel = tip_rest.origin
		foot.side = signf(tip_rest.origin.x) if absf(tip_rest.origin.x) > 0.001 else 1.0
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
	
	_compute_zones()
	
	# One TwoBoneIK3D handles every leg; the FootAligner is added after it so it
	# runs after the IK.
	var leg_total := 0.0
	for foot in _feet:
		leg_total += foot.leg_skel
	_leg_skel_average = leg_total / maxf(float(_feet.size()), 1.0)
	_setup_wobble()
	
	_ik = TwoBoneIK3D.new()
	_ik.name = "LegIK"
	skeleton.add_child(_ik)
	_aligner = FootAligner.new()
	_aligner.name = "FootAligner"
	skeleton.add_child(_aligner)
	_fingers = FingerLagModifier.new()
	_fingers.name = "FingerLag"
	skeleton.add_child(_fingers)  # after the IK and the aligner
	_fingers.influence = 0.0
	_fingers.active = false
	
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


# Legs on the same side are ordered along the body (skeleton +Z is forward).
# Each leg gets room up to the middle of the gap to its neighbours.
func _compute_zones() -> void:
	for foot in _feet:
		var back_gap := INF
		var front_gap := INF
		for other in _feet:
			if other == foot or other.side != foot.side:
				continue
			var gap := other.home_skel.z - foot.home_skel.z
			if gap > 0.0:
				front_gap = minf(front_gap, gap)
			elif gap < 0.0:
				back_gap = minf(back_gap, -gap)
		# Outermost legs have no neighbour on that side: half a leg of room.
		foot.z_front_room = foot.leg_skel * 0.5 if front_gap == INF else front_gap * 0.5 * zone_ratio
		foot.z_back_room = foot.leg_skel * 0.5 if back_gap == INF else back_gap * 0.5 * zone_ratio
		_debug_lines.append("zone side %+.0f z %.2f: %.2f back, %.2f ahead" % [
			foot.side, foot.home_skel.z, foot.z_back_room, foot.z_front_room])


# The fingers follow the two halves of a step: while the foot rises they tilt
# down, while it comes back down they tilt up, and once it has landed they settle
# back. Each tilt takes the time set in the inspector. One axis only.
func _update_fingers(delta: float) -> void:
	for foot in _feet:
		if foot.stepping:
			var rise := clampf(foot.step_time / foot.lift_time, 0.0, 1.0)
			var fall := clampf((foot.step_duration - foot.step_time) / foot.lower_time, 0.0, 1.0)
			if rise < fall:
				foot.finger_phase = -1.0   # still rising
			elif fall < rise:
				foot.finger_phase = 1.0    # coming down
			# (equal = the top of the step: keep the current direction)
		else:
			foot.finger_phase = 0.0
		
		var time := finger_return_time
		if foot.finger_phase < 0.0:
			time = finger_down_time
		elif foot.finger_phase > 0.0:
			time = finger_up_time
		foot.finger_pos = move_toward(foot.finger_pos, foot.finger_phase, delta / maxf(time, 0.001))
		
		var amount := absf(foot.finger_pos)
		var eased := amount * amount * (3.0 - 2.0 * amount)
		var degrees := finger_up_degrees if foot.finger_pos > 0.0 else finger_down_degrees
		var angle := signf(foot.finger_pos) * eased * deg_to_rad(degrees)
		_fingers.set_angle(foot.tip_bone, -angle if finger_lag_invert else angle)


func _setup_wobble() -> void:
	_body_bone = skeleton.find_bone(body_bone)
	if _body_bone < 0:
		push_warning("ProceduralLegs: body bone '%s' not found, so there is no body wobble." % body_bone)
		return
	_abdomen_bone = skeleton.find_bone(abdomen_bone) if abdomen_bone != "" else -1
	_wobble = BodyWobbleModifier.new()
	_wobble.name = "BodyWobble"
	skeleton.add_child(_wobble)  # added before the IK, so it runs before it
	_wobble.influence = 0.0
	_wobble.active = false


# The wobble follows the gait: while one tripod swings, the other holds the body
# up and the body leans toward the side with two supporting legs.
func _update_wobble(delta: float) -> void:
	if _wobble == null:
		return
	var swing := [0.0, 0.0]
	var side_sum := [0.0, 0.0]
	for foot in _feet:
		side_sum[foot.group] += foot.side
		if foot.stepping:
			var t := clampf(foot.step_time / foot.step_duration, 0.0, 1.0)
			swing[foot.group] = maxf(swing[foot.group], sin(t * PI))
	
	var lean_target: float = swing[1] * signf(side_sum[0]) + swing[0] * signf(side_sum[1])
	var bob_target: float = maxf(swing[0], swing[1])
	var follow := 1.0 - exp(-wobble_smoothing * delta)
	_wobble_lean = lerpf(_wobble_lean, lean_target, follow)
	_wobble_bob = lerpf(_wobble_bob, bob_target, follow)
	
	# Skeleton space: +X is the left side, +Y up, +Z forward.
	var roll := -_wobble_lean * deg_to_rad(wobble_roll_degrees)
	var yaw := -_wobble_lean * deg_to_rad(wobble_yaw_degrees)
	var body_rotation := Basis(Vector3.UP, yaw) * Basis(Vector3(0.0, 0.0, 1.0), roll)
	var offset := Vector3(
		_wobble_lean * wobble_sway_ratio * _leg_skel_average,
		_wobble_bob * wobble_bob_ratio * _leg_skel_average,
		0.0)
	_wobble.set_bone(_body_bone, offset, body_rotation)
	if _abdomen_bone >= 0:
		_wobble.set_bone(_abdomen_bone, Vector3.ZERO,
			Basis(Vector3.UP, _wobble_lean * deg_to_rad(wobble_abdomen_yaw_degrees)))


func _physics_process(delta: float) -> void:
	if _unit == null:
		return
	var yaw := _unit.global_rotation.y
	var rate := angle_difference(_prev_yaw, yaw) / maxf(delta, 0.0001)
	_angular_velocity = lerpf(_angular_velocity, rate, 0.5)
	_prev_yaw = yaw
	var turning := clampf(absf(_angular_velocity) / maxf(turn_tighten_rate, 0.01), 0.0, 1.0)
	_lateral_ratio = lerpf(min_lateral_ratio, maxf(min_lateral_ratio, min_lateral_ratio_turning), turning)


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
	if _wobble:
		_wobble.influence = _blend
		_wobble.active = wobble_enabled and _blend > 0.001
	_ik.active = _blend > 0.001
	_aligner.active = _blend > 0.001
	_fingers.influence = _blend
	_fingers.active = finger_lag_enabled and _blend > 0.001
	
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
	if not _unit_is_paused():
		_update_wobble(delta)
		_update_fingers(delta)


func _wants_active() -> bool:
	return animator != null and String(animator.current_state) in active_states


func _unit_is_paused() -> bool:
	return "paused" in _unit and _unit.paused


# Puts every foot back at its home position, standing still.
func _replant() -> void:
	_turn = 0
	for foot in _feet:
		var hit := _ground_hit(foot, _home_world(foot))
		foot.stepping = false
		foot.planted = hit["position"]
		foot.normal = hit["normal"]
		foot.tip = foot.planted
		foot.finger_phase = 0.0
		foot.finger_pos = 0.0
		foot.stepped_this_round = false
		_apply_foot(foot)


# The foot's home spot in skeleton space, with the home offsets applied.
func _home_skel(foot: Foot) -> Vector3:
	var shift := Vector3(foot.side * home_outward_ratio, 0.0, home_forward_ratio) * foot.leg_skel
	return foot.home_skel + shift


func _home_world(foot: Foot) -> Vector3:
	return skeleton.global_transform * _home_skel(foot)


# Keeps a spot (skeleton space) inside the foot's zone: not under the body and
# not past the middle of the gap to the neighbouring legs.
func _constrain_skel(foot: Foot, pos: Vector3) -> Vector3:
	var home := _home_skel(foot)
	var min_x := absf(home.x) * _lateral_ratio
	if foot.side * pos.x < min_x:
		pos.x = foot.side * min_x
	pos.z = clampf(pos.z, home.z - foot.z_back_room, home.z + foot.z_front_room)
	return pos


# True when a planted foot has been carried outside its zone by the body
# moving or turning, so it has to step now.
func _outside_zone(foot: Foot) -> bool:
	var pos := skeleton.global_transform.affine_inverse() * foot.planted
	var margin := foot.leg_skel * 0.02
	var constrained := _constrain_skel(foot, pos)
	return absf(constrained.x - pos.x) > margin or absf(constrained.z - pos.z) > margin


# Sends a foot's current state to the IK: the ankle target, the pole, and the
# orientation the foot bone should have.
func _apply_foot(foot: Foot) -> void:
	var skeleton_basis := skeleton.global_transform.basis
	var tilt := Basis(Quaternion(Vector3.UP, foot.normal))  # flat -> slope
	
	# The foot tip should touch the ground, so the ankle sits one foot-length
	# above it, in the direction the (tilted) foot points.
	var foot_world := tilt * (skeleton_basis * foot.foot_vec_skel)
	
	# Hard safety limit: a foot that is still waiting for its turn is dragged out
	# rather than left under the body.
	var tip := foot.tip
	var tip_skel := skeleton.global_transform.affine_inverse() * tip
	var min_x := absf(_home_skel(foot).x) * _lateral_ratio
	if foot.side * tip_skel.x < min_x:
		tip_skel.x = foot.side * min_x
		tip = skeleton.global_transform * tip_skel
	foot.target.global_position = _clamp_to_reach(foot, tip - foot_world)
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


# Walking rules that can never be broken:
#  - Legs step in ROUNDS: only one gait group (a tripod) steps at a time, and the
#    other group, which holds the adjacent legs, stays planted until it has landed.
#  - Within a round a foot steps at most once. Its group has to wait for the
#    other group's round before it can step again, so a leg never double steps.
# A foot that has to wait is not forced: it just stretches (and is kept in reach
# and out from under the body) until its turn comes.
func _update_steps(delta: float) -> void:
	var velocity := Vector3(_unit.velocity.x, 0.0, _unit.velocity.z)
	
	# 1) Move the feet that are in the air.
	for foot in _feet:
		if not foot.stepping:
			continue
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
	
	# 2) Which planted feet want to step?
	var stepping := [false, false]
	var pending := [false, false]  # wants to step and has not had its step this round
	var wants := [false, false]    # wants to step
	for foot in _feet:
		if foot.stepping:
			stepping[foot.group] = true
			continue
		foot.tip = foot.planted
		foot.needs_step = _needs_step(foot)
		if foot.needs_step:
			wants[foot.group] = true
			if not foot.stepped_this_round:
				pending[foot.group] = true
	
	# 3) The turn passes once the group whose turn it is has nothing left to do
	# and the other group needs to step.
	var other := 1 - _turn
	if not stepping[_turn] and not stepping[other] and not pending[_turn] and wants[other]:
		_turn = other
		for foot in _feet:
			foot.stepped_this_round = false
	
	# 4) Start steps, only for the group whose turn it is, and never while the
	# other group is in the air.
	if stepping[1 - _turn]:
		return
	for foot in _feet:
		if foot.group != _turn or foot.stepping or not foot.needs_step or foot.stepped_this_round:
			continue
		_begin_step(foot, _home_world(foot), velocity, foot.reach * step_trigger_ratio)
		foot.stepped_this_round = true


# Far enough from its home spot, or carried out of its zone, that it should step.
func _needs_step(foot: Foot) -> bool:
	var offset := foot.planted - _home_world(foot)
	offset.y = 0.0
	return offset.length() > foot.reach * step_trigger_ratio or _outside_zone(foot)


func _begin_step(foot: Foot, home: Vector3, velocity: Vector3, trigger: float) -> void:
	# How fast this foot's home spot is travelling: the unit's own movement plus
	# the swing from turning. Turning moves feet sideways, along arcs around the
	# body, instead of back to front.
	var from_centre := home - _unit.global_position
	from_centre.y = 0.0
	var foot_velocity := velocity + Vector3.UP.cross(from_centre) * _angular_velocity
	var speed := foot_velocity.length()
	var duration := max_step_duration
	if speed > 0.01:
		# One group is planted while the other swings, so a swing should take
		# about as long as a planted foot needs to cover a stride.
		duration = clampf(2.0 * trigger / speed * 0.9, min_step_duration, max_step_duration)
	duration /= maxf(horizontal_speed, 0.05)
	
	# Land slightly ahead of the home spot along the foot's own direction of
	# travel, so the foot can trail behind it during the stance.
	var lead := (foot_velocity * duration * 0.5 * landing_lead_scale).limit_length(foot.reach * landing_lead_max_ratio)
	
	# Where the body will be when the step ends (it moves and turns meanwhile).
	# The landing spot is worked out in that future skeleton space, and kept
	# inside this foot's zone there.
	var unit_now := _unit.global_transform
	var unit_after := Transform3D(
		Basis(Vector3.UP, _angular_velocity * duration) * unit_now.basis,
		unit_now.origin + velocity * duration)
	var skeleton_after := unit_after * unit_now.affine_inverse() * skeleton.global_transform
	var landing_skel := _home_skel(foot) + skeleton_after.basis.inverse() * lead
	landing_skel = _constrain_skel(foot, landing_skel)
	var landing := skeleton_after * landing_skel
	
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
