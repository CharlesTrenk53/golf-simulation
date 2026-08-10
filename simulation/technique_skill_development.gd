extends RefCounted

# Technique & Skill Development
# -----------------------------
# Comfort and confidence can move quickly. Technique moves slowly. Underlying
# skill moves slowest of all. Established experience makes true skill more
# resistant to decline, slower to acquire genuinely new ability, and better at
# self-correcting back toward an established pattern.

const DevelopmentPotential = preload("res://simulation/development_potential.gd")

const MIN_TECHNIQUE_EVIDENCE := 18
const MIN_SKILL_EVIDENCE := 60
const MAX_TRACKED_EVENTS := 240
const MAX_TRACKED_EVENTS_PER_SHOT := 240
const SKILL_STEP_SCALE := 0.0042
const TECHNIQUE_STEP_SCALE := 0.10
const COACHING_TRIGGER_DELTA := -2.5
const EXPERIENCE_STABILITY_HALF_LIFE := 1800.0
const DEVELOPMENT_RESISTANCE_SCALE := 6.0
const DEVELOPMENT_RESISTANCE_POWER := 1.35
const BASELINE_RECOVERY_EXPERIENCE_MAX := 1.75
const BASELINE_REGRESSION_MIN := 0.0008
const BASELINE_REGRESSION_MAX := 0.0018

# Age plasticity is deliberately separate from physical aging. It modifies only
# acquisition of genuinely new above-baseline skill. It does not accelerate a
# slump, worsen deterioration, or slow restoration toward established ability.
const AGE_PLASTICITY_POINTS := [
	[16.0, 1.25],
	[20.0, 1.15],
	[25.0, 1.05],
	[30.0, 1.00],
	[35.0, 0.95],
	[40.0, 0.90],
	[50.0, 0.80],
	[60.0, 0.70],
	[70.0, 0.60],
	[76.0, 0.55]
]

const AGE_RETENTION_POINTS := [
	[55.0, 0.0000],
	[60.0, 0.0010],
	[65.0, 0.0025],
	[70.0, 0.0045],
	[76.0, 0.0065]
]

var baseline_skill: Dictionary = {}
var skill_delta: Dictionary = {}
var technique_bias: Dictionary = {}
var evidence: Dictionary = {}
var prior_experience: Dictionary = {}
var supplemental_experience: Dictionary = {}
var learning_aptitude: Dictionary = {}
var history: Array = []
var shot_history: Dictionary = {}
var current_age: float = 30.0
var development_potential := DevelopmentPotential.new()

func initialize_from_golfer(golfer: Node) -> void:
	baseline_skill.clear()
	skill_delta.clear()
	technique_bias.clear()
	evidence.clear()
	prior_experience.clear()
	supplemental_experience.clear()
	learning_aptitude.clear()
	history.clear()
	shot_history.clear()
	development_potential.initialize(100.0)
	current_age = float(golfer.age) if "age" in golfer else 30.0
	for shot_type in [0, 1, 2, 3]:
		baseline_skill[shot_type] = float(golfer.get_shot_ability(shot_type))
		skill_delta[shot_type] = 0.0
		technique_bias[shot_type] = {"lateral": 0.0, "distance": 0.0, "dispersion": 0.0}
		evidence[shot_type] = {"count": 0, "quality_sum": 0.0, "persistent_quality_sum": 0.0, "lateral_sum": 0.0, "distance_sum": 0.0}
		prior_experience[shot_type] = int(golfer.skill_experience_for(shot_type)) if golfer.has_method("skill_experience_for") else 0
		supplemental_experience[shot_type] = 0
		learning_aptitude[shot_type] = clamp(float(golfer.skill_learning_rate_for(shot_type)), 0.25, 2.0) if golfer.has_method("skill_learning_rate_for") else 1.0
		if golfer.has_method("skill_potential_for"):
			development_potential.set_potential(shot_type, float(golfer.skill_potential_for(shot_type)))
		shot_history[shot_type] = []

func set_current_age(age: float) -> void:
	current_age = max(age, 0.0)

func set_skill_potential(shot_type: int, potential: float) -> void:
	development_potential.set_potential(shot_type, potential)

func skill_potential_for(shot_type: int) -> float:
	return development_potential.potential_for(shot_type)

func potential_resistance_for(shot_type: int) -> float:
	var base = float(baseline_skill.get(shot_type, 50.0))
	var delta = float(skill_delta.get(shot_type, 0.0))
	return development_potential.resistance_for(shot_type, clamp(base + delta, 0.0, 100.0))

func record_experience_only(shot_type: int, repetitions: int) -> void:
	if not supplemental_experience.has(shot_type):
		return
	supplemental_experience[shot_type] = int(supplemental_experience.get(shot_type, 0)) + maxi(repetitions, 0)

func advance_year() -> void:
	# Technical retention is a time-based annual effect, deliberately separate
	# from per-shot learning. Age-related retention pressure applies only to
	# acquired above-baseline skill; it does not punish additional practice by
	# making deterioration occur once per shot.
	var retention_rate = age_retention_rate()
	if retention_rate <= 0.0:
		return

	for shot_type in [0, 1, 2, 3]:
		var current_delta = float(skill_delta.get(shot_type, 0.0))
		if current_delta <= 0.0:
			continue
		skill_delta[shot_type] = current_delta * (1.0 - retention_rate)

func age_learning_plasticity(age: float = -1.0) -> float:
	var resolved_age = current_age if age < 0.0 else age
	if resolved_age <= float(AGE_PLASTICITY_POINTS[0][0]):
		return float(AGE_PLASTICITY_POINTS[0][1])
	for i in range(1, AGE_PLASTICITY_POINTS.size()):
		var younger_age = float(AGE_PLASTICITY_POINTS[i - 1][0])
		var younger_factor = float(AGE_PLASTICITY_POINTS[i - 1][1])
		var older_age = float(AGE_PLASTICITY_POINTS[i][0])
		var older_factor = float(AGE_PLASTICITY_POINTS[i][1])
		if resolved_age <= older_age:
			var weight = inverse_lerp(younger_age, older_age, resolved_age)
			return lerp(younger_factor, older_factor, weight)
	return float(AGE_PLASTICITY_POINTS[AGE_PLASTICITY_POINTS.size() - 1][1])

func age_retention_rate(age: float = -1.0) -> float:
	var resolved_age = current_age if age < 0.0 else age
	if resolved_age <= float(AGE_RETENTION_POINTS[0][0]):
		return float(AGE_RETENTION_POINTS[0][1])
	for i in range(1, AGE_RETENTION_POINTS.size()):
		var younger_age = float(AGE_RETENTION_POINTS[i - 1][0])
		var younger_rate = float(AGE_RETENTION_POINTS[i - 1][1])
		var older_age = float(AGE_RETENTION_POINTS[i][0])
		var older_rate = float(AGE_RETENTION_POINTS[i][1])
		if resolved_age <= older_age:
			var weight = inverse_lerp(younger_age, older_age, resolved_age)
			return lerp(younger_rate, older_rate, weight)
	return float(AGE_RETENTION_POINTS[AGE_RETENTION_POINTS.size() - 1][1])

func record_execution(shot_type: int, execution_score: float, lateral_error: float, distance_error: float, persistent_execution_score: float = -1.0) -> Dictionary:
	if not evidence.has(shot_type):
		return {}
	var score = clamp(execution_score, 0.0, 100.0)
	# When the caller can identify a transient performance component (for example,
	# explicit hot/cold form), persistent skill evidence may be supplied separately.
	# Existing callers omit it and preserve the original score-as-evidence behavior.
	var persistent_score = score if persistent_execution_score < 0.0 else clamp(persistent_execution_score, 0.0, 100.0)
	var row: Dictionary = evidence[shot_type]
	row["count"] = int(row["count"]) + 1
	row["quality_sum"] = float(row["quality_sum"]) + score
	row["persistent_quality_sum"] = float(row.get("persistent_quality_sum", 0.0)) + persistent_score
	row["lateral_sum"] = float(row["lateral_sum"]) + lateral_error
	row["distance_sum"] = float(row["distance_sum"]) + distance_error
	evidence[shot_type] = row
	var event := {"shot_type": shot_type, "score": score, "persistent_score": persistent_score, "lateral": lateral_error, "distance": distance_error}
	history.append(event)
	while history.size() > MAX_TRACKED_EVENTS:
		history.pop_front()

	# Development windows must be retained independently for each shot family.
	# A shared global history causes lower-frequency shots (especially drives and
	# short-game shots) to be displaced by higher-frequency putting/approach events
	# before they can accumulate the minimum evidence required for true skill change.
	var shot_events: Array = shot_history[shot_type]
	shot_events.append(event)
	while shot_events.size() > MAX_TRACKED_EVENTS_PER_SHOT:
		shot_events.pop_front()
	shot_history[shot_type] = shot_events

	_update_technique(shot_type)
	_update_skill_delta(shot_type)
	return development_state(shot_type)

func effective_skill(golfer: Node, shot_type: int) -> float:
	var current = float(golfer.get_shot_ability(shot_type))
	var delta = float(skill_delta.get(shot_type, 0.0))
	return clamp(current + delta, 0.0, 100.0)

func development_state(shot_type: int) -> Dictionary:
	var base = float(baseline_skill.get(shot_type, 50.0))
	var delta = float(skill_delta.get(shot_type, 0.0))
	var current_skill = clamp(base + delta, 0.0, 100.0)
	var row: Dictionary = evidence.get(shot_type, {"count": 0, "quality_sum": 0.0, "persistent_quality_sum": 0.0})
	var count = int(row.get("count", 0))
	var avg_quality = float(row.get("quality_sum", 0.0)) / max(count, 1)
	var avg_persistent_quality = float(row.get("persistent_quality_sum", row.get("quality_sum", 0.0))) / max(count, 1)
	var total_experience = _total_experience(shot_type)
	var stability = _experience_stability(total_experience)
	return {
		"baseline_skill": base,
		"skill_delta": delta,
		"effective_skill": current_skill,
		"evidence_count": count,
		"prior_experience": int(prior_experience.get(shot_type, 0)),
		"supplemental_experience": int(supplemental_experience.get(shot_type, 0)),
		"total_experience": total_experience,
		"experience_stability": stability,
		"learning_aptitude": float(learning_aptitude.get(shot_type, 1.0)),
		"skill_potential": development_potential.potential_for(shot_type),
		"distance_to_potential": development_potential.potential_for(shot_type) - current_skill,
		"potential_resistance": development_potential.resistance_for(shot_type, current_skill),
		"current_age": current_age,
		"age_learning_plasticity": age_learning_plasticity(),
		"development_resistance": _development_resistance(delta),
		"average_execution_quality": avg_quality,
		"average_persistent_execution_quality": avg_persistent_quality,
		"technique_bias": technique_bias.get(shot_type, {}).duplicate(true),
		"coaching_candidate": delta <= COACHING_TRIGGER_DELTA,
		"coaching_trigger_delta": COACHING_TRIGGER_DELTA
	}

func _update_technique(shot_type: int) -> void:
	var recent = _recent_events(shot_type, 24)
	if recent.size() < MIN_TECHNIQUE_EVIDENCE:
		return
	var avg_score = 0.0
	var avg_lateral = 0.0
	var avg_distance = 0.0
	for event in recent:
		avg_score += float(event["score"])
		avg_lateral += float(event["lateral"])
		avg_distance += float(event["distance"])
	avg_score /= recent.size()
	avg_lateral /= recent.size()
	avg_distance /= recent.size()
	var bias: Dictionary = technique_bias[shot_type]
	var stability = _experience_stability(_total_experience(shot_type))
	var technique_rate = TECHNIQUE_STEP_SCALE * lerp(1.0, 0.55, stability)
	bias["lateral"] = lerp(float(bias["lateral"]), avg_lateral, technique_rate)
	bias["distance"] = lerp(float(bias["distance"]), avg_distance, technique_rate)
	var quality_penalty = clamp((55.0 - avg_score) / 55.0, 0.0, 1.0)
	bias["dispersion"] = lerp(float(bias["dispersion"]), quality_penalty, technique_rate)
	technique_bias[shot_type] = bias

func _update_skill_delta(shot_type: int) -> void:
	var row: Dictionary = evidence[shot_type]
	var count = int(row["count"])
	if count < MIN_SKILL_EVIDENCE:
		return
	var long_window = _recent_events(shot_type, 80)
	if long_window.size() < MIN_SKILL_EVIDENCE:
		return
	var immediate_window = _recent_events(shot_type, 8)
	# True skill responds to the persistent-learning channel. The observed score
	# remains available to technique/current-performance systems, but known transient
	# form no longer has to masquerade as acquired or lost underlying ability.
	var long_avg = _average_persistent_score(long_window)
	var immediate_avg = _average_persistent_score(immediate_window)
	var long_signal = clamp((long_avg - 62.0) / 38.0, -1.0, 1.0)
	var immediate_signal = clamp((immediate_avg - 62.0) / 38.0, -1.0, 1.0)
	var skill_signal = long_signal * 0.65 + immediate_signal * 0.35
	var current_delta = float(skill_delta[shot_type])
	var base = float(baseline_skill[shot_type])
	var current_skill = clamp(base + current_delta, 0.0, 100.0)
	var total_experience = _total_experience(shot_type)
	var stability = _experience_stability(total_experience)

	# Experience has three distinct roles:
	# 1) it protects established ability from deterioration;
	# 2) it helps restoration toward a previously established baseline, but true
	#    skill recovery remains slower than form, technique, or confidence;
	# 3) it makes acquisition of genuinely new above-baseline skill slower.
	var experience_modifier: float
	if skill_signal < 0.0:
		experience_modifier = lerp(1.0, 0.32, stability)
	elif current_delta < 0.0:
		experience_modifier = lerp(1.0, BASELINE_RECOVERY_EXPERIENCE_MAX, stability)
	else:
		experience_modifier = lerp(1.0, 0.45, stability)

	# Skill-specific aptitude and age-based plasticity apply only to genuinely new
	# skill acquisition. Slump deterioration and restoration toward an established
	# baseline remain governed by evidence and experience, keeping recovery separate.
	var aptitude_modifier = 1.0
	var potential_modifier = 1.0
	if skill_signal > 0.0 and current_delta >= 0.0:
		aptitude_modifier = float(learning_aptitude.get(shot_type, 1.0)) * age_learning_plasticity()
		potential_modifier = development_potential.resistance_for(shot_type, current_skill)

	# Moving farther from an established skill becomes progressively harder instead
	# of stopping at an arbitrary +/-8 point clamp. This produces a general soft
	# plateau. POC-09 adds golfer-specific potential resistance on top of this
	# universal development resistance only for acquisition of genuinely new skill.
	var resistance = _development_resistance(current_delta)

	# The 0-100 skill scale is the only absolute bound. Movement naturally slows
	# near either end because there is less physical/technical headroom remaining.
	var boundary_modifier = 1.0
	if skill_signal > 0.0:
		boundary_modifier = sqrt(clamp((100.0 - current_skill) / 100.0, 0.0, 1.0))
	elif skill_signal < 0.0:
		boundary_modifier = sqrt(clamp(current_skill / 100.0, 0.0, 1.0))

	# Baseline regression is deliberately modest. It preserves the useful idea
	# that established golfers self-correct somewhat faster, without letting a
	# relatively short run of good swings instantly erase genuine skill loss.
	# Faster rebound still belongs to technique, confidence, and comfort layers.
	var regression = 0.0
	var evidence_points_toward_baseline = (
		current_delta < 0.0 and skill_signal > 0.0
	)
	if evidence_points_toward_baseline:
		regression = -current_delta * lerp(BASELINE_REGRESSION_MIN, BASELINE_REGRESSION_MAX, stability)

	var step = skill_signal * SKILL_STEP_SCALE * experience_modifier * aptitude_modifier * potential_modifier * resistance * boundary_modifier + regression
	var next_skill = clamp(current_skill + step, 0.0, 100.0)
	skill_delta[shot_type] = next_skill - base

func _total_experience(shot_type: int) -> int:
	return int(prior_experience.get(shot_type, 0)) + int(evidence.get(shot_type, {}).get("count", 0)) + int(supplemental_experience.get(shot_type, 0))

func _development_resistance(delta: float) -> float:
	var distance = abs(delta) / DEVELOPMENT_RESISTANCE_SCALE
	return 1.0 / pow(1.0 + distance, DEVELOPMENT_RESISTANCE_POWER)

func _experience_stability(total_experience: int) -> float:
	var experience = max(float(total_experience), 0.0)
	return clamp(experience / (experience + EXPERIENCE_STABILITY_HALF_LIFE), 0.0, 0.92)

func _average_score(events: Array) -> float:
	if events.is_empty():
		return 62.0
	var total = 0.0
	for event in events:
		total += float(event["score"])
	return total / events.size()

func _average_persistent_score(events: Array) -> float:
	if events.is_empty():
		return 62.0
	var total = 0.0
	for event in events:
		total += float(event.get("persistent_score", event["score"]))
	return total / events.size()

func _recent_events(shot_type: int, limit: int) -> Array:
	var result: Array = []
	var shot_events: Array = shot_history.get(shot_type, [])
	for i in range(shot_events.size() - 1, -1, -1):
		result.push_front(shot_events[i])
		if result.size() >= limit:
			break
	return result
