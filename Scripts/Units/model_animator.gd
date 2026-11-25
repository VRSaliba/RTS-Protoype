class_name ModelAnimator
extends Node
## Put this on the root of each imported model scene (or as a child of it).
## Gameplay code only calls play("walk") etc. Each model maps those generic
## states to its own animation names in the inspector.
##
## SETUP PER MODEL:
##  1. Add a Node child to the model's scene, attach this script.
##  2. Leave animation_player empty to auto-find it, or assign it.
##  3. Edit animation_map: key = generic state, value = animation name in Blender.
##     (If your animations live in a library, use "libname/AnimName".)
##
## USAGE FROM A PLAYER/ENEMY SCRIPT:
##   @onready var animator: ModelAnimator = $Model/ModelAnimator
##
##   func _physics_process(delta):
##       if not is_on_floor():
##           animator.play("jump")
##       elif velocity.length() > 5.0:
##           animator.play("run")
##       elif velocity.length() > 0.1:
##           animator.play("walk")
##       else:
##           animator.play("idle")
##
##   # One-shot action that returns to idle when finished:
##   animator.play("attack")
##   await animator.state_finished

signal state_finished(state: StringName)
## Fired by "Call Method" tracks inside the animations (see fire_event).
signal event_fired(event: String)

@export var animation_player: AnimationPlayer
@export var blend_time: float = 0.2
## Generic state -> actual animation name on this model.
@export var animation_map: Dictionary = {
	"idle": "Idle",
	"idle_look": "IdleLookAround",
	"attack": "AttackHornSwipe",
	"special": "SpecialAttack",
	"hurt": "TakingDamage",
	"death": "Death",
	"walk": "RESET",  # placeholder body pose while the legs are driven by IK
}
## States that loop. Everything else plays once.
@export var looping_states: PackedStringArray = ["idle", "walk"]
## Where to go after a one-shot state ends.
@export var fallback_state: StringName = &"idle"

var current_state: StringName = &""


func _ready() -> void:
	if animation_player == null:
		animation_player = _find_animation_player()
	if animation_player == null:
		push_error("ModelAnimator: no AnimationPlayer found under %s" % get_path())
		return
	animation_player.animation_finished.connect(_on_animation_finished)
	_apply_loop_modes()
	if fallback_state != &"":
		play(fallback_state)


## Returns true if the state exists on this model.
func play(state: StringName, speed: float = 1.0, restart: bool = false) -> bool:
	if animation_player == null:
		return false
	if not animation_map.has(state):
		push_warning("ModelAnimator: state '%s' is not mapped" % state)
		return false
	var anim_name: String = animation_map[state]
	if not animation_player.has_animation(anim_name):
		push_warning("ModelAnimator: animation '%s' not found" % anim_name)
		return false
	if state == current_state and animation_player.is_playing() and not restart:
		return true
	current_state = state
	animation_player.play(anim_name, blend_time, speed)
	return true


## Target of Call Method tracks in the animations. Add a key that calls
## fire_event("hit") at the frame where an attack connects.
func fire_event(event: String) -> void:
	event_fired.emit(event)


## True if the animation for this state has a Call Method key that calls
## fire_event with this event name.
func has_event(state: StringName, event: String) -> bool:
	if not has_state(state):
		return false
	var anim := animation_player.get_animation(animation_map[state])
	for track in anim.get_track_count():
		if anim.track_get_type(track) != Animation.TYPE_METHOD:
			continue
		for key in anim.track_get_key_count(track):
			if anim.method_track_get_name(track, key) == &"fire_event" \
					and event in anim.method_track_get_params(track, key):
				return true
	return false


## Length in seconds of the animation mapped to this state (0 if missing).
func get_state_length(state: StringName) -> float:
	if not has_state(state):
		return 0.0
	return animation_player.get_animation(animation_map[state]).length


## Freezes or resumes the current animation (used for the game's pause).
func set_paused(is_paused: bool) -> void:
	if animation_player:
		animation_player.speed_scale = 0.0 if is_paused else 1.0


func has_state(state: StringName) -> bool:
	return animation_map.has(state) \
		and animation_player != null \
		and animation_player.has_animation(animation_map[state])


func is_looping_state(state: StringName) -> bool:
	return state in looping_states


func _apply_loop_modes() -> void:
	for state in animation_map:
		var anim_name: String = animation_map[state]
		if not animation_player.has_animation(anim_name):
			continue
		var anim := animation_player.get_animation(anim_name)
		anim.loop_mode = Animation.LOOP_LINEAR if state in looping_states \
			else Animation.LOOP_NONE


func _on_animation_finished(anim_name: StringName) -> void:
	for state in animation_map:
		if animation_map[state] == String(anim_name):
			if not is_looping_state(state):
				state_finished.emit(state)
				if fallback_state != &"":
					play(fallback_state)
			return


func _find_animation_player() -> AnimationPlayer:
	var root: Node = owner if owner != null else get_parent()
	var found := root.find_children("*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if found.size() > 0 else null
