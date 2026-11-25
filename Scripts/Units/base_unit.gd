extends CharacterBody3D
class_name BaseUnit

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var selected_mesh: MeshInstance3D = $"Selected Mesh"
@onready var attack_cooldown_timer: Timer = $"Attack Cooldown Timer"
@onready var health_bar: Sprite3D = $"Health Bar"
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var model_holder: Node3D = $"Model Holder"

## Everything that defines this unit: model, stats and skills.
@export var unit_data: UnitData
## FALLBACK only: used when the attack animation has no "hit" event.
## Seconds after the attack animation starts before damage is applied.
@export var attack_hit_delay: float = 0.6
## How far past touching (the two body radii) a unit can still strike.
@export var attack_range_margin: float = 0.6
## How fast the unit turns toward where it is going, in radians per second.
@export var turn_speed: float = 10.0
## If true, taking damage plays the hurt animation even mid-swing. A swing cut
## short that way never connects, so no cooldown starts and the unit can attack
## again right after the hurt animation. If false, units finish their swing first.
@export var hurt_interrupts_attack: bool = true
## How long a dead unit stays on screen after its death animation ends.
@export var corpse_linger_time: float = 1.0

enum UnitState {IDLE, MOVING, ATTACKING, USING_SKILL, DEAD}
var current_state: UnitState = UnitState.IDLE

var move_target: Vector3

var can_attack: bool = false
var attack_target: BaseUnit
signal damage_dealt
signal damage_taken
signal death_animation_finished

var selected: bool = false
var paused: bool = false

# This unit's own copy of unit_data.base_stats, made in _ready().
# Change this one during play (health, speed), never the shared resource.
var base_stats: UnitBaseStats
var current_model: UnitModel
var animator: ModelAnimator
# True while a one-shot animation (attack, hurt, special, death) is playing.
var action_playing: bool = false
# The one-shot state currently playing ("attack", "hurt", ...), or empty.
var current_action: StringName = &""
# True between starting an attack and its animation firing the "hit" event.
var attack_hit_pending: bool = false
# True while the half-speed attack slowdown is applied.
var attack_slowdown_active: bool = false
# Counts swings so a cancelled swing's fallback timer can't affect a later one.
var swing_serial: int = 0

# The selection ring meshes were designed for a capsule of this radius.
const RING_BASE_RADIUS: float = 0.4

func _ready() -> void:
	# adjust movement to avoid other units
	attack_cooldown_timer.timeout.connect(on_attack_cooldown_timer_timeout)
	damage_taken.connect(check_unit_dead)
	
	if unit_data == null or unit_data.base_stats == null:
		push_error("BaseUnit '%s' needs a Unit Data with Base Stats." % name)
		set_physics_process(false)
		return
	# Every unit gets its own copy of its stats, so units never share health.
	base_stats = unit_data.base_stats.duplicate() as UnitBaseStats
	
	if unit_data.model_scene:
		set_model(unit_data.model_scene)
	else:
		_adopt_existing_model()
	
	health_bar.progress_bar.max_value = base_stats.max_health_points
	health_bar.progress_bar.value = base_stats.current_health_points
	
	add_to_group("all_units")

func _physics_process(_delta: float) -> void:
	health_bar.state_label.text = UnitState.find_key(current_state)
	match current_state:
		UnitState.IDLE: state_idle()
		UnitState.MOVING: state_moving()
		UnitState.ATTACKING: state_attacking()
		UnitState.USING_SKILL: state_using_skill()
		UnitState.DEAD: state_dead()
	_update_animation()

func set_move_target(new_move_target: Vector3) -> void:
	move_target = new_move_target

func clear_move_target() -> void:
	move_target = Vector3.ZERO
	change_state(UnitState.IDLE)

func set_attack_target(new_attack_target: BaseUnit) -> void:
	# Ignore missing or dead targets (a dead unit lingers during its death animation).
	if not is_instance_valid(new_attack_target) or new_attack_target.current_state == UnitState.DEAD:
		clear_attack_target()
		return
	attack_target = new_attack_target
	change_state(UnitState.ATTACKING)

func clear_attack_target() -> void:
	attack_target = null
	change_state(UnitState.IDLE)

func change_state(new_state: UnitState) -> void:
	# A dead unit lingers during its death animation; it must never act again.
	if current_state == UnitState.DEAD:
		return
	current_state = new_state

func state_idle() -> void:
	pass

func state_moving() -> void:
	if move_target:
		var next_path_pos := nav_agent.get_next_path_position()
		can_attack = false
		if not paused:
			var direction = global_position.direction_to(next_path_pos)
			velocity = direction * base_stats.movement_speed
			
			if direction.length() > 0.01:
				velocity = direction.normalized() * base_stats.movement_speed
			else:
				velocity = Vector3.ZERO
			
			if nav_agent.is_navigation_finished():
				clear_move_target()
				velocity = Vector3.ZERO
			
			_face_direction(direction)
			move_and_slide()

func state_attacking() -> void:
	if attack_target:
		nav_agent.target_position = attack_target.position
		var next_path_pos := nav_agent.get_next_path_position()
		can_attack = false
		if not paused:
			var direction = global_position.direction_to(next_path_pos)
			velocity = direction * base_stats.movement_speed
			
			if direction.length() > 0.01:
				velocity = direction.normalized() * base_stats.movement_speed
			else:
				velocity = Vector3.ZERO
			
			if nav_agent.is_navigation_finished() or _in_attack_range():
				if attack_cooldown_timer.is_stopped() and current_action != &"hurt" and not attack_hit_pending:
					can_attack = true
				velocity = Vector3.ZERO
			
			_face_direction(direction)
			move_and_slide()
	else:
		find_new_random_attack_target()
	if can_attack:
		attack()

## Turns the unit toward a movement direction at turn_speed. Only the flat
## (ground) part of the direction counts, so a path point below the unit can
## no longer flip or jitter the heading.
func _face_direction(direction: Vector3) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.01:
		return
	var target := atan2(flat.x, flat.z)
	var step := turn_speed * get_physics_process_delta_time()
	rotation.y += clampf(angle_difference(rotation.y, target), -step, step)

func state_using_skill() -> void:
	# When you implement skills, trigger the animation with:
	#   _play_action(&"special")
	pass

func state_dead() -> void:
	pass

func attack() -> void:
	can_attack = false
	_begin_attack_slowdown()
	swing_serial += 1
	var my_swing := swing_serial
	var anim_speed := get_attack_speed()
	_play_action(&"attack", anim_speed)
	attack_hit_pending = true
	
	# Preferred: the attack animation fires a "hit" event at the moment of contact.
	# The cooldown starts when that hit connects (see _apply_attack_hit).
	if animator and animator.has_event(&"attack", "hit"):
		return
	
	# Fallback for models without a hit event: wait a fixed delay.
	# Time only counts while the game is not paused.
	var hit_delay := attack_hit_delay / anim_speed
	var waited: float = 0.0
	while waited < hit_delay:
		await get_tree().physics_frame
		if not is_inside_tree() or current_state == UnitState.DEAD:
			return
		if my_swing != swing_serial or not attack_hit_pending:
			return  # this swing was cancelled
		if not paused:
			waited += get_physics_process_delta_time()
	if my_swing != swing_serial or not attack_hit_pending:
		return
	attack_hit_pending = false
	_apply_attack_hit()

# The swing was cut short before it connected: no hit, no cooldown. The unit
# gets its normal speed back and can attack again once it recovers.
func _cancel_pending_attack() -> void:
	attack_hit_pending = false
	_end_attack_slowdown()

# Units move at half speed from the start of a swing until its cooldown ends.
func _begin_attack_slowdown() -> void:
	if not attack_slowdown_active:
		attack_slowdown_active = true
		base_stats.movement_speed = base_stats.movement_speed / 2

func _end_attack_slowdown() -> void:
	if attack_slowdown_active:
		attack_slowdown_active = false
		base_stats.movement_speed = base_stats.movement_speed * 2

func _on_animator_event(event: String) -> void:
	if event == "hit" and attack_hit_pending:
		attack_hit_pending = false
		if current_state != UnitState.DEAD:
			_apply_attack_hit()

## Radius of this unit's body (from its model).
func get_body_radius() -> float:
	return current_model.radius if current_model else 0.4

# True when the target is close enough to strike. Uses flat (ground) distance
# and both body sizes, so bigger models don't get stuck outside their reach.
func _in_attack_range() -> bool:
	if not is_instance_valid(attack_target):
		return false
	var offset := attack_target.global_position - global_position
	offset.y = 0.0
	var reach := get_body_radius() + attack_target.get_body_radius() + attack_range_margin
	return offset.length() <= reach

func _apply_attack_hit() -> void:
	# The hit connected: the cooldown starts now.
	attack_cooldown_timer.start(get_attack_cooldown())
	deal_damage()
	if attack_target:
		if attack_target.current_state == UnitState.DEAD:
			clear_attack_target()
			find_new_random_attack_target()
	else:
		clear_attack_target()

## Playback speed of the attack animation (stat attack_speed).
## The "hit" event and the fallback delay both scale with it automatically.
func get_attack_speed() -> float:
	return maxf(base_stats.attack_speed, 0.1)

## Seconds between a hit connecting and the unit being able to attack again
## (stat attack_cooldown).
func get_attack_cooldown() -> float:
	return maxf(base_stats.attack_cooldown, 0.01)

func deal_damage() -> void:
	if attack_target:
		attack_target.take_damage(base_stats.attack)
		damage_dealt.emit()
	else:
		find_new_random_attack_target()

func take_damage(incoming_attack_stat: int) -> void:
	if current_state == UnitState.DEAD:
		return
	#print("self base stats: " + str(base_stats))
	#print("enemy base stats: " + str(enemy_unit_target.base_stats))
	base_stats.current_health_points -= incoming_attack_stat - base_stats.defense
	health_bar.progress_bar.value = base_stats.current_health_points
	if base_stats.current_health_points > 0:
		var can_flinch := animator != null and animator.has_state(&"hurt")
		var mid_swing := current_action == &"attack"
		if can_flinch and (hurt_interrupts_attack or not mid_swing):
			if attack_hit_pending:
				_cancel_pending_attack()
			_play_action(&"hurt")
	damage_taken.emit()

func check_unit_dead() -> void:
	if current_state == UnitState.DEAD:
		return
	if base_stats.current_health_points <= 0:
		change_state(UnitState.DEAD)
		_on_death_started()
		_play_action(&"death")
		GlobalSignals.unit_died.emit(self)

# The unit stays in the scene while its death animation plays, so switch off
# everything that would make it behave like a living unit.
func _on_death_started() -> void:
	velocity = Vector3.ZERO
	can_attack = false
	set_selected_false()
	health_bar.hide()
	nav_agent.avoidance_enabled = false
	collision_shape.set_deferred("disabled", true)

## Call this instead of queue_free() when a unit dies.
## Waits for the death animation (and a short linger), then removes the unit.
func free_after_death() -> void:
	if animator and animator.has_state(&"death"):
		await death_animation_finished
		if not is_inside_tree():
			return
	if corpse_linger_time > 0.0:
		await get_tree().create_timer(corpse_linger_time).timeout
	queue_free()

func on_attack_cooldown_timer_timeout() -> void:
	can_attack = true
	_end_attack_slowdown()

func find_new_random_attack_target() -> void:
	pass

func pause() -> void:
	paused = true
	velocity = Vector3.ZERO
	if animator:
		animator.set_paused(true)

func resume() -> void:
	paused = false
	if animator:
		animator.set_paused(false)

func set_selected_true() -> void:
	selected = true
	selected_mesh.visible = true

func set_selected_false() -> void:
	selected = false
	selected_mesh.visible = false

# --- Model -------------------------------------------------------------------

## Replaces the current model. Can also be called at runtime.
func set_model(scene: PackedScene) -> void:
	for child in model_holder.get_children():
		child.queue_free()
	var instance := scene.instantiate()
	if not instance is UnitModel:
		push_error("BaseUnit: the root of '%s' must use unit_model.gd" % scene.resource_path)
		instance.queue_free()
		return
	model_holder.add_child(instance)
	_apply_model(instance)

# Lets you drop a model scene into Model Holder by hand in the editor instead
# of using the Unit Data model.
func _adopt_existing_model() -> void:
	for child in model_holder.get_children():
		if child is UnitModel:
			_apply_model(child)
			return
	push_warning("BaseUnit '%s' has no model." % name)

func _apply_model(model: UnitModel) -> void:
	current_model = model
	animator = model.animator
	action_playing = false
	current_action = &""
	if animator:
		# The unit decides what plays next, not the animator.
		animator.fallback_state = &""
		if not animator.state_finished.is_connected(_on_action_finished):
			animator.state_finished.connect(_on_action_finished)
		if not animator.event_fired.is_connected(_on_animator_event):
			animator.event_fired.connect(_on_animator_event)
	_fit_to_model(model)

## Resizes everything that depends on the model's size.
## The unit's origin is the center of the collision capsule.
## Subclasses can override this (call super first) to fit extra nodes.
func _fit_to_model(model: UnitModel) -> void:
	var half_height := model.height / 2.0
	
	# New shape each time so units never share (and resize) the same resource.
	var capsule := CapsuleShape3D.new()
	capsule.radius = model.radius
	capsule.height = model.height
	collision_shape.shape = capsule
	
	# The model's origin is at its feet, so put it at the bottom of the capsule.
	model_holder.position.y = -half_height
	
	nav_agent.radius = model.radius
	health_bar.position.y = half_height + model.health_bar_gap
	_fit_ring(selected_mesh, model)

## Places a selection ring at the model's feet and scales it to its width.
func _fit_ring(ring: MeshInstance3D, model: UnitModel) -> void:
	var ring_scale := model.radius / RING_BASE_RADIUS
	ring.position.y = -model.height / 2.0 + model.ring_ground_offset
	ring.scale = Vector3(ring_scale, 1.0, ring_scale)

# --- Animation ---------------------------------------------------------------

func _update_animation() -> void:
	if animator == null or action_playing or paused or current_state == UnitState.DEAD:
		return
	var moving := current_state in [UnitState.MOVING, UnitState.ATTACKING] \
		and velocity.length() > 0.1
	if moving and animator.has_state(&"walk"):
		animator.play(&"walk")
	else:
		animator.play(&"idle")

func _play_action(state: StringName, speed: float = 1.0) -> void:
	if animator and animator.has_state(state):
		attack_hit_pending = false
		action_playing = true
		current_action = state
		animator.play(state, speed, true)

func _on_action_finished(state: StringName) -> void:
	action_playing = false
	current_action = &""
	if state == &"attack" and attack_hit_pending \
			and animator and animator.has_event(&"attack", "hit"):
		_cancel_pending_attack()  # swing ended without ever firing "hit"
	if state == &"death":
		death_animation_finished.emit()
