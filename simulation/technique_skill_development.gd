extends RefCounted

# Technique & Skill Development
# -----------------------------
# Comfort and confidence can move quickly. Technique moves slowly. Underlying
# skill moves slowest of all. Established experience makes true skill more
# resistant to decline, slower to acquire genuinely new ability, and better at
# self-correcting back toward an established pattern.

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

var baseline_skill: Dictionary = {}
var skill_delta: Dictionary = {}
var technique_bias: Dictionary = {}
var evidence: Dictionary = {}
var prior_experience: Dictionary = {}
var learning_aptitude: Dictionary = {}
var history: Array = []
var shot_history: Dictionary = {}

func initialize_from_golfer(golfer: Node) -> void:
	baseline_skill.clear()
	skill_delta.clear()
	technique_bias.clear()
	evidence.clear()
	prior_experience.clear()
	learning_aptitude.clear()
	history.clear()
	shot_history.clear()
	for shot_type in [0, 1, 2, 3]:
		baseline_skill[shot_type] = float(golfer.get_shot_ability(shot_type))
		skill_delta[shot_type] = 0.0
		technique_bias[shot_type] = {"lateral": 0.0, "distance": 0.0, "dispersion": 0.0}
		evidence[shot_type] = {"count": 0, "quality_sum": 0.0, "lateral_sum": 0.0, "distance_sum": 0.0}
		prior_experience[shot_type] = int(golfer.skill_experience_for(shot_type)) if golfer.has_method("skill_experience_for") else 0
		learning_aptitude[shot_type] = clamp(float(golfer.skill_learning_rate_for(shot_type)), 0.25, 2.0) if golfer.has_method("skill_learning_rate_for") else 1.0
		shot_history[shot_type] = []

func record_execution(shot_type: int, execution_score: float, lateral_error: float, distance_error: float) -> Dictionary:
	if not evidence.has(shot_type):
		return {}
	var score = clamp(execution_score, 0.0, 100.0)
	var row: Dictionary = evidence[shot_type]
	row["count"] = int(row["count"]) + 1
	row["quality_sum"] = float(row["quality_sum"]) + score
	row["lateral_sum"] = float(row["lateral_sum"]) + lateral_error
	row["distance_sum"] = float(row["distance_sum"]) + distance_error
	evidence[shot_type] = row
	var event := {"shot_type": shot_type, "score": score, "lateral": lateral_error, "distance": distance_error}
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
	var row: Dictionary = evidence.get(shot_type, {"count": 0, "quality_sum": 0.0})
	var count = int(row.get("count", 0))
	var avg_quality = float(row.get("quality_sum", 0.0)) / max(count, 1)
	var total_experience = int(prior_experience.get(shot_type, 0)) + count
	var stability = _experience_stability(total_experience)
	return {
		"baseline_skill": base,
		"skill_delta": delta,
		"effective_skill": clamp(base + delta, 0.0, 100.0),
		"evidence_count": count,
		"prior_experience": int(prior_experience.get(shot_type, 0)),
		"total_experience": total_experience,
		"experience_stability": stability,
		"learning_aptitude": float(learning_aptitude.get(shot_type, 1.0)),
		"development_resistance": _development_resistance(delta),
		"average_execution_quality": avg_quality,
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
	var stability = _experience_stability(int(prior_experience.get(shot_type, 0)) + int(evidence[shot_type]["count"]))
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
	var long_avg = _average_score(long_window)
	var immediate_avg = _average_score(immediate_window)
	var long_signal = clamp((long_avg - 62.0) / 38.0, -1.0, 1.0)
	var immediate_signal = clamp((immediate_avg - 62.0) / 38.0, -1.0, 1.0)
	var skill_signal = long_signal * 0.65 + immediate_signal * 0.35
	var current_delta = float(skill_delta[shot_type])
	var base = float(baseline_skill[shot_type])
	var current_skill = clamp(base + current_delta, 0.0, 100.0)
	var total_experience = int(prior_experience.get(shot_type, 0)) + count
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

	# Skill-specific aptitude applies only to genuinely new skill acquisition.
	# Slump deterioration and restoration toward an established baseline remain
	# governed by evidence and experience so the recovery model stays independent.
	var aptitude_modifier = 1.0
	if skill_signal > 0.0 and current_delta >= 0.0:
		aptitude_modifier = float(learning_aptitude.get(shot_type, 1.0))

	# Moving farther from an established skill becomes progressively harder instead
	# of stopping at an arbitrary +/-8 point clamp. This produces a soft plateau
	# while still allowing truly prolonged evidence to keep changing the golfer.
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
		(current_delta < 0.0 and skill_signal > 0.0)
		or (current_delta > 0.0 and skill_signal < 0.0)
	)
	if evidence_points_toward_baseline:
		regression = -current_delta * lerp(BASELINE_REGRESSION_MIN, BASELINE_REGRESSION_MAX, stability)

	var step = skill_signal * SKILL_STEP_SCALE * experience_modifier * aptitude_modifier * resistance * boundary_modifier + regression
	var next_skill = clamp(current_skill + step, 0.0, 100.0)
	skill_delta[shot_type] = next_skill - base

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

func _recent_events(shot_type: int, limit: int) -> Array:
	var result: Array = []
	var shot_events: Array = shot_history.get(shot_type, [])
	for i in range(shot_events.size() - 1, -1, -1):
		result.push_front(shot_events[i])
		if result.size() >= limit:
			break
	return result
