class_name ProceduralLegs
extends Node
## Procedural leg stepping for a model: one SkeletonIK3D per leg, each with a
## magnet (pole target) so the knees bend upward instead of flipping around.
##
## Put this node in the MODEL scene (next to ModelAnimator) and fill in `legs`.
## At runtime it creates, per leg, a SkeletonIK3D under the Skeleton3D and a
## top-level foot-target marker. While the unit is walking, feet stay planted on
## the ground and step forward in an alternating (tripod) pattern as the body
## moves away from them. In every other state the IK fades out and the normal
## animation takes over again.
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
## spot (fraction of the leg's length). A full stride is about twice this, so
## smaller = quicker, shorter steps.
@export var step_trigger_ratio: float = 0.3
## A foot steps no matter what once it is this far (fraction of leg length).
@export var force_step_ratio: float = 0.5
## Step time follows the unit's speed (fast unit = quick steps), within these
## limits in seconds.
@export var min_step_duration: float = 0.08
@export var max_step_duration: float = 0.3
## How high the foot lifts mid-step (fraction of leg length).
@export var step_height_ratio: float = 0.25
## Targets are never placed farther than this fraction of the leg's length from
## its hip, so the solver never chases an impossible target.
@export_range(0.5, 1.0) var max_reach_ratio: float = 0.97

@export_group("Ground")
## Physics layers the feet can stand on. Put your floor and terrain on these
## layers (and keep units off them), or feet may land on other units.
@export_flags_3d_physics var ground_mask: int = 1
## The ground ray starts this far above the landing spot (fraction of leg length)...
@export var ground_ray_up_ratio: float = 0.6
## ...and ends this far below it.
@export var ground_ray_down_ratio: float = 1.0

@export_group("Solver")
@export var max_iterations: int = 10
## Only used for legs WITHOUT a pole bone. The magnet starts at the knee's rest
## position and is lifted along the leg's own bend direction (fraction of leg
## length). 0 = exact rest angle, higher = knee bent up further.
@export var knee_push_ratio: float = 0.3
## How fast the IK fades in and out when switching to or from walking.
@export var blend_speed: float = 8.0

@export_group("Debug")
## Prints the skeleton's bones and the IK setup once.
@export var debug_print: bool = false
## Shows a sphere on every foot target (big) and every magnet (small).
@export var debug_show_targets: bool = false


class Foot:
	var target: Node3D
	var magnet_marker: Node3D  # only used by the debug view
	var ik: SkeletonIK3D
	var root_bone: int
	var home_skel: Vector3    # rest position of the foot tip, in skeleton space
	var magnet_skel: Vector3  # knee magnet position, in skeleton space
	var use_magnet: bool = true
	var reach: float          # leg length in world units
	var group: int = 0
	var planted: Vector3      # world position the foot is standing on
	var step_from: Vector3
	var step_to: Vector3
	var step_time: float = 0.0
	var step_duration: float = 0.2
	var stepping: bool = false
	var body_offset: Vector3
	var tip_rest_basis: Basis
	var pole_bone: int = -1


var _unit: CharacterBody3D
var _feet: Array[Foot] = []
var _blend: float = 0.0
var _was_active: bool = false
var _debug_printed: bool = false


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
	_build()


func _build() -> void:
	var world_scale := skeleton.global_transform.basis.get_scale().x
	for leg in legs:
		var root_id := skeleton.find_bone(leg.root_bone)
		var tip_id := skeleton.find_bone(leg.end_bone)
		if root_id < 0 or tip_id < 0:
			push_error("ProceduralLegs: bone '%s' or '%s' not found in the skeleton." % [leg.root_bone, leg.end_bone])
			continue
		var chain := _chain_bones(root_id, tip_id)

		var names := []
		for bone_id in chain:
			names.append(skeleton.get_bone_name(bone_id))
		print("Chain:", names)

		if chain.size() < 2:
			push_error("ProceduralLegs: '%s' is not a parent of '%s'." % [leg.root_bone, leg.end_bone])
			continue
		var length := _chain_length(chain)
		
		var foot := Foot.new()
		foot.group = leg.gait_group
		foot.root_bone = root_id
		foot.reach = length * world_scale
		var hip_rest := skeleton.get_bone_global_rest(root_id).origin
		foot.home_skel = skeleton.get_bone_global_rest(tip_id).origin
		foot.tip_rest_basis = skeleton.get_bone_global_rest(tip_id).basis
		foot.body_offset = foot.home_skel
		foot.use_magnet = chain.size() > 2
		var pole_id := skeleton.find_bone(leg.pole_bone) if leg.pole_bone != "" else -1
		foot.pole_bone = pole_id
		if leg.pole_bone != "" and pole_id < 0:
			push_warning("ProceduralLegs: pole bone '%s' not found, using the knee's rest position." % leg.pole_bone)
		if pole_id >= 0:
			# The rig's own pole bone: the magnet sits exactly on it.
			foot.magnet_skel = skeleton.get_bone_global_rest(pole_id).origin
		else:
			var knee_rest := skeleton.get_bone_global_rest(_middle_bone(chain, length)).origin
			var chord := foot.home_skel - hip_rest
			var along := clampf((knee_rest - hip_rest).dot(chord) / maxf(chord.length_squared(), 0.0001), 0.0, 1.0)
			var bend := knee_rest - (hip_rest + chord * along)
			var bend_dir := bend.normalized() if bend.length() > 0.001 else Vector3.UP
			foot.magnet_skel = knee_rest + bend_dir * length * knee_push_ratio
		
		var marker := Node3D.new()
		marker.name = "FootTarget%d" % _feet.size()
		marker.top_level = true  # lives in world space, not carried by the unit
		add_child(marker)
		foot.target = marker
		if debug_show_targets:
			marker.add_child(_make_debug_sphere(0.05))
			var magnet_marker := Node3D.new()
			magnet_marker.name = "Magnet%d" % _feet.size()
			magnet_marker.top_level = true
			magnet_marker.add_child(_make_debug_sphere(0.025))
			add_child(magnet_marker)
			foot.magnet_marker = magnet_marker
		
		# One SkeletonIK3D per leg. It must be added to the skeleton before it
		# is configured, because it looks for its parent skeleton on entering.
		var ik := SkeletonIK3D.new()
		ik.name = "LegIK%d" % _feet.size()
		skeleton.add_child(ik)
		ik.root_bone = StringName(leg.root_bone)
		ik.tip_bone = StringName(leg.end_bone)
		ik.target_node = ik.get_path_to(marker)
		ik.use_magnet = foot.use_magnet
		ik.magnet = foot.magnet_skel
		ik.override_tip_basis = true
		ik.max_iterations = max_iterations
		ik.influence = 0.0
		ik.start()
		foot.ik = ik
		
		_feet.append(foot)
	_replant()


func _update_elbow_target(foot: Foot) -> void:
	if foot.pole_bone < 0:
		return

	foot.magnet_skel = skeleton.get_bone_global_pose(foot.pole_bone).origin

	foot.ik.magnet = foot.magnet_skel

	if foot.magnet_marker:
		foot.magnet_marker.global_position = skeleton.global_transform * foot.magnet_skel


func _make_debug_sphere(radius: float) -> MeshInstance3D:
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	sphere.mesh = mesh
	return sphere


# Bones from root down to tip, in order. Empty if root is not an ancestor of tip.
func _chain_bones(root_id: int, tip_id: int) -> Array[int]:
	var bones: Array[int] = []
	var bone := tip_id
	while bone != root_id:
		if bone < 0:
			return []
		bones.push_front(bone)
		bone = skeleton.get_bone_parent(bone)
	bones.push_front(root_id)
	return bones


# Length of the chain in skeleton units.
func _chain_length(chain: Array[int]) -> float:
	var length := 0.0
	for k in range(1, chain.size()):
		length += skeleton.get_bone_rest(chain[k]).origin.length()
	return length


# The bone SkeletonIK3D treats as the knee: the inner bone whose distance from
# the hip is closest to half the leg's length.
func _middle_bone(chain: Array[int], length: float) -> int:
	var best := chain[1]
	var best_gap := INF
	var travelled := 0.0
	for k in range(1, chain.size() - 1):
		travelled += skeleton.get_bone_rest(chain[k]).origin.length()
		var gap := absf(travelled - length * 0.5)
		if gap < best_gap:
			best_gap = gap
			best = chain[k]
	return best


func _process(delta: float) -> void:
	if _feet.is_empty():
		return
	var active := _wants_active()
	_blend = move_toward(_blend, 1.0 if active else 0.0, delta * blend_speed)
	for foot in _feet:
		foot.ik.influence = _blend
		_update_elbow_target(foot)
		if foot.magnet_marker:
			foot.magnet_marker.global_position = skeleton.global_transform * foot.magnet_skel
	
	if active and not _was_active:
		_replant()  # start walking with every foot at its home position
		_print_debug()
	elif not active and _blend <= 0.001:
		_replant()  # idle: keep the targets at home so they are ready
	_was_active = active
	
	if not active or _unit_is_paused():
		return
	_update_steps(delta)


func _wants_active() -> bool:
	return animator != null and String(animator.current_state) in active_states


func _unit_is_paused() -> bool:
	return "paused" in _unit and _unit.paused


# Puts every foot back at its home position, standing still.
func _replant() -> void:
	for foot in _feet:
		foot.stepping = false
		foot.planted = _ground_point(foot, _home_world(foot))
		foot.target.global_position = _clamp_to_reach(foot, foot.planted)
		_update_foot_basis(foot)


# Drops a ray straight down at this spot and returns the ground it hits (the
# spot itself if nothing is there, or only another unit).
func _ground_point(foot: Foot, pos: Vector3) -> Vector3:
	var exclude: Array[RID] = [_unit.get_rid()]
	var query := PhysicsRayQueryParameters3D.create(
		pos + Vector3.UP * foot.reach * ground_ray_up_ratio,
		pos - Vector3.UP * foot.reach * ground_ray_down_ratio,
		ground_mask, exclude)
	var hit := _unit.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit["collider"] is CharacterBody3D:
		return pos
	return hit["position"]


func _home_world(foot: Foot) -> Vector3:
	return (
		skeleton.global_transform.origin +
		skeleton.global_transform.basis * foot.body_offset
	)


func _update_foot_basis(foot: Foot) -> void:
	foot.target.global_basis = (
		skeleton.global_transform.basis *
		foot.tip_rest_basis
	).orthonormalized()


# Keeps a target within the leg's reach so the solver never has to chase a
# point it can't get to (which makes legs flail and twist).
func _clamp_to_reach(foot: Foot, pos: Vector3) -> Vector3:
	var hip := skeleton.global_transform * skeleton.get_bone_global_pose(foot.root_bone).origin
	var offset := pos - hip
	var max_length := foot.reach * max_reach_ratio
	if offset.length() > max_length:
		return hip + offset.normalized() * max_length
	return pos


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
			pos.y += sin(t * PI) * step_height_ratio * foot.reach
			foot.target.global_position = _clamp_to_reach(foot, pos)
			_update_foot_basis(foot)
			if t >= 1.0:
				foot.stepping = false
				foot.planted = foot.step_to
				foot.target.global_position = _clamp_to_reach(foot, foot.planted)
				_update_foot_basis(foot)
			continue
		
		foot.target.global_position = _clamp_to_reach(foot, foot.planted)
		_update_foot_basis(foot)
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
	# Land slightly ahead of where the body will have carried the home spot by
	# the end of the step, so the foot can trail behind it during the stance.
	var lead := (velocity * duration * 0.5).limit_length(trigger * 0.9)
	var landing := home + velocity * duration + lead
	foot.stepping = true
	foot.step_time = 0.0
	foot.step_duration = duration
	foot.step_from = foot.planted
	foot.step_to = _ground_point(foot, Vector3(landing.x, foot.planted.y, landing.z))


func _print_debug() -> void:
	if not debug_print or _debug_printed:
		return
	_debug_printed = true
	var bones: Array[String] = []
	for b in skeleton.get_bone_count():
		bones.append(skeleton.get_bone_name(b))
	print("[ProceduralLegs] skeleton bones: ", bones)
	for foot in _feet:
		print("[ProceduralLegs] %s: %s -> %s | reach %.2f | magnet (skeleton space) %s" % [
			foot.ik.name, foot.ik.root_bone, foot.ik.tip_bone, foot.reach, foot.magnet_skel])


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
