extends RefCounted

# Technique & Skill Development
# -----------------------------
# Comfort and confidence can move quickly. Technique moves slowly. Underlying
# skill moves slowest of all. Established experience makes true skill more
# resistant to decline and slightly better at self-correcting after a slump.

const MIN_TECHNIQUE_EVIDENCE := 18
const MIN_SKILL_EVIDENCE := 60
const MAX_TRACKED_EVENTS := 240
const SKILL_STEP_SCALE := 0.0042
const TECHNIQUE_STEP_SCALE := 0.10
const MAX_SKILL_DELTA_FROM_BASELINE := 8.0
const COACHING_TRIGGER_DELTA := -2.5
const EXPERIENCE_STABILITY_HALF_LIFE := 1800.0

var baseline_skill: Dictionary = {}
var skill_delta: Dictionary = {}
var technique_bias: Dictionary = {}
var evidence: Dictionary = {}
var prior_experience: Dictionary = {}
var history: Array = []

func initialize_from_golfer(golfer: Node) -> void:
	baseline_skill.clear()
	skill_delta.clear()
	technique_bias.clear()
	evidence.clear()
	prior_experience.clear()
	history.clear()
	for shot_type in [0, 1, 2, 3]:
		baseline_skill[shot_type] = float(golfer.get_shot_ability(shot_type))
		skill_delta[shot_type] = 0.0
		technique_bias[shot_type] = {"lateral": 0.0, "distance": 0.0, "dispersion": 0.0}
		evidence[shot_type] = {"count": 0, "quality_sum": 0.0, "lateral_sum": 0.0, "distance_sum": 0.0}
		prior_experience[shot_type] = int(golfer.skill_experience_for(shot_type)) if golfer.has_method("skill_experience_for") else 0

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
	history.append({"shot_type": shot_type, "score": score, "lateral": lateral_error, "distance": distance_error})
	while history.size() > MAX_TRACKED_EVENTS:
		history.pop_front()

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
	# Established golfers still develop temporary faults, but the pattern embeds
	# more slowly because an older motor pattern pulls them back toward normal.
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
	var total_experience = int(prior_experience.get(shot_type, 0)) + count
	var stability = _experience_stability(total_experience)

	# Experience creates asymmetry: established skill is harder to erode, while a
	# veteran who starts executing well can self-correct somewhat more efficiently.
	var experience_modifier = lerp(1.0, 0.32, stability) if skill_signal < 0.0 else lerp(1.0, 1.22, stability)
	var regression = -current_delta * lerp(0.0015, 0.0035, stability)
	var step = skill_signal * SKILL_STEP_SCALE * experience_modifier + regression
	skill_delta[shot_type] = clamp(current_delta + step, -MAX_SKILL_DELTA_FROM_BASELINE, MAX_SKILL_DELTA_FROM_BASELINE)

func _experience_stability(total_experience: int) -> float:
	# Saturating curve: early experience matters a lot; thousands of repetitions
	# eventually produce a strong but never perfect anchor.
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
	for i in range(history.size() - 1, -1, -1):
		var event: Dictionary = history[i]
		if int(event["shot_type"]) != shot_type:
			continue
		result.push_front(event)
		if result.size() >= limit:
			break
	return result
