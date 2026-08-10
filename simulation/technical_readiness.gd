extends RefCounted

# Technical Readiness / Rust
# --------------------------
# Represents access to already-learned technique after inactivity. Rust reduces
# currently usable technical skill without deleting the golfer's durable learned
# skill. Returning activity removes rust much faster than ordinary development
# can create new durable ability.
#
# Time is measured continuously in days so a week away and a year away are not
# treated as equivalent annual states. The inactivity curve is intentionally
# accelerating through short/medium layoffs and then saturates: a golfer can get
# very rusty, but does not forget an entire golf education merely by being away.

const SHOT_TYPES := [0, 1, 2, 3]
const MAX_RUST_PENALTY := 12.0
const RUST_HALF_SCALE_DAYS := 180.0
const RUST_CURVE_POWER := 1.35
const RECOVERY_REPS_HALF_LIFE := 220.0

var days_since_activity: Dictionary = {}
var rust_penalty: Dictionary = {}

func _init() -> void:
	reset()

func reset() -> void:
	days_since_activity.clear()
	rust_penalty.clear()
	for shot_type in SHOT_TYPES:
		days_since_activity[shot_type] = 0.0
		rust_penalty[shot_type] = 0.0

func advance_days(days: float) -> void:
	var elapsed := maxf(days, 0.0)
	if elapsed <= 0.0:
		return
	for shot_type in SHOT_TYPES:
		var total_days := float(days_since_activity.get(shot_type, 0.0)) + elapsed
		days_since_activity[shot_type] = total_days
		rust_penalty[shot_type] = inactivity_penalty_for_days(total_days)

func record_activity(shot_type: int, repetitions: int) -> void:
	if not rust_penalty.has(shot_type):
		return
	var reps := maxi(repetitions, 0)
	if reps <= 0:
		return
	var current_rust := float(rust_penalty.get(shot_type, 0.0))
	# Reacquisition is intentionally faster than new learning. Repetition removes
	# a fraction of existing rust rather than awarding durable skill.
	var retained_fraction := pow(0.5, float(reps) / RECOVERY_REPS_HALF_LIFE)
	rust_penalty[shot_type] = current_rust * retained_fraction
	# Meaningful contact resets elapsed inactivity for that skill family. Any
	# remaining rust represents incomplete reacquisition rather than continued layoff.
	days_since_activity[shot_type] = 0.0

func usable_skill(durable_skill: float, shot_type: int) -> float:
	return clampf(durable_skill - float(rust_penalty.get(shot_type, 0.0)), 0.0, 100.0)

func inactivity_penalty_for_days(days: float) -> float:
	var elapsed := maxf(days, 0.0)
	if elapsed <= 0.0:
		return 0.0
	var ratio := elapsed / RUST_HALF_SCALE_DAYS
	var powered := pow(ratio, RUST_CURVE_POWER)
	return MAX_RUST_PENALTY * powered / (1.0 + powered)

func state_for(shot_type: int) -> Dictionary:
	return {
		"days_since_activity": float(days_since_activity.get(shot_type, 0.0)),
		"rust_penalty": float(rust_penalty.get(shot_type, 0.0))
	}

func state() -> Dictionary:
	return {
		"days_since_activity": days_since_activity.duplicate(true),
		"rust_penalty": rust_penalty.duplicate(true)
	}
