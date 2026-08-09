extends RefCounted

# Golfer Memory & Comfort
# -----------------------
# Ability answers "can I hit this shot?". Comfort answers "how much do I trust
# this club/shot right now?". Comfort is learned from experience and is kept
# separate from underlying skill.
#
# Three timescales are blended:
#   1. baseline familiarity (stable identity / underlying ability)
#   2. learned history (older experiences still matter)
#   3. recent + current-round experience (largest per-shot influence)
#
# The API already accepts shot-form strings (NORMAL, HIGH, LOW, DRAW, FADE,
# PARTIAL, etc.) so future shot-shape work can plug in without changing this
# memory model.

const MAX_HISTORY := 80
const RECENT_WINDOW := 12
const ROUND_WINDOW := 8
const RECENCY_DECAY := 0.82
const LONG_TERM_DECAY := 0.965

var baseline_club: Dictionary = {}
var baseline_shot_type: Dictionary = {}
var baseline_shot_form: Dictionary = {}
var baseline_combo: Dictionary = {}
var history: Array = []
var current_round_start_index: int = 0
var sequence: int = 0

func initialize_from_golfer(golfer: Node, clubs: Array = []) -> void:
	baseline_club.clear()
	baseline_shot_type.clear()
	baseline_shot_form.clear()
	baseline_combo.clear()
	history.clear()
	sequence = 0
	current_round_start_index = 0

	for shot_type in [0, 1, 2, 3]:
		var ability = float(golfer.get_shot_ability(shot_type))
		baseline_shot_type[shot_type] = _baseline_from_identity(ability, float(golfer.confidence))

	for club in clubs:
		var club_id = String(club.get("id", ""))
		if club_id.is_empty():
			continue
		var shot_type = int(club.get("shot_type", 1))
		var ability = float(golfer.get_shot_ability(shot_type))
		baseline_club[club_id] = _baseline_from_identity(ability, float(golfer.confidence))

	# Normal shots start most familiar. Specialized forms start neutral rather
	# than bad: lack of history means uncertainty, not inability.
	baseline_shot_form = {
		"NORMAL": clamp(float(golfer.confidence) * 0.55 + 45.0, 35.0, 90.0),
		"HIGH": 50.0,
		"LOW": 50.0,
		"DRAW": 50.0,
		"FADE": 50.0,
		"PARTIAL": 50.0
	}

func start_new_round() -> void:
	current_round_start_index = history.size()

func record_experience(club: Dictionary, shot_form: String, execution_quality: String, outcome: String = "SUCCESS", perceived_execution_score: float = -1.0) -> void:
	var club_id = String(club.get("id", ""))
	var shot_type = int(club.get("shot_type", 1))
	var normalized_form = _normalize_form(shot_form)
	var quality_score = _experience_score(execution_quality, outcome, perceived_execution_score)
	sequence += 1
	history.append({
		"sequence": sequence,
		"club_id": club_id,
		"shot_type": shot_type,
		"shot_form": normalized_form,
		"combo": _combo_key(club_id, normalized_form),
		"quality_score": quality_score,
		"execution_quality": execution_quality,
		"outcome": outcome
	})
	while history.size() > MAX_HISTORY:
		history.pop_front()
		current_round_start_index = max(current_round_start_index - 1, 0)

func comfort_for(golfer: Node, club: Dictionary, shot_form: String = "NORMAL") -> Dictionary:
	var club_id = String(club.get("id", ""))
	var shot_type = int(club.get("shot_type", 1))
	var normalized_form = _normalize_form(shot_form)
	var combo = _combo_key(club_id, normalized_form)

	var identity_default = _baseline_from_identity(float(golfer.get_shot_ability(shot_type)), float(golfer.confidence))
	var club_base = float(baseline_club.get(club_id, identity_default))
	var type_base = float(baseline_shot_type.get(shot_type, identity_default))
	var form_base = float(baseline_shot_form.get(normalized_form, 50.0))
	var combo_base = float(baseline_combo.get(combo, club_base * 0.55 + form_base * 0.45))
	var baseline = club_base * 0.38 + type_base * 0.22 + form_base * 0.20 + combo_base * 0.20

	var long_term = _weighted_history_value(club_id, shot_type, normalized_form, combo, false, LONG_TERM_DECAY, MAX_HISTORY)
	var recent = _weighted_history_value(club_id, shot_type, normalized_form, combo, false, RECENCY_DECAY, RECENT_WINDOW)
	var round_value = _weighted_history_value(club_id, shot_type, normalized_form, combo, true, 0.76, ROUND_WINDOW)

	var long_term_score = baseline if long_term["weight"] <= 0.0 else float(long_term["score"])
	var recent_score = baseline if recent["weight"] <= 0.0 else float(recent["score"])
	var round_score = baseline if round_value["weight"] <= 0.0 else float(round_value["score"])

	# Recent results are intentionally stronger than old history. Current-round
	# momentum is smaller overall but can move rapidly after a short streak.
	var comfort = baseline * 0.38 + long_term_score * 0.22 + recent_score * 0.28 + round_score * 0.12
	var evidence = float(long_term["weight"] + recent["weight"] + round_value["weight"])
	var certainty = clamp(35.0 + evidence * 7.0, 35.0, 100.0)

	return {
		"comfort": clamp(comfort, 0.0, 100.0),
		"baseline": baseline,
		"long_term": long_term_score,
		"recent": recent_score,
		"current_round": round_score,
		"certainty": certainty,
		"club_id": club_id,
		"shot_type": shot_type,
		"shot_form": normalized_form,
		"combo": combo,
		"matching_experiences": int(long_term.get("matches", 0))
	}

func set_baseline_club_comfort(club_id: String, value: float) -> void:
	baseline_club[club_id] = clamp(value, 0.0, 100.0)

func set_baseline_shot_form_comfort(shot_form: String, value: float) -> void:
	baseline_shot_form[_normalize_form(shot_form)] = clamp(value, 0.0, 100.0)

func set_baseline_combo_comfort(club_id: String, shot_form: String, value: float) -> void:
	baseline_combo[_combo_key(club_id, _normalize_form(shot_form))] = clamp(value, 0.0, 100.0)

func _weighted_history_value(club_id: String, shot_type: int, shot_form: String, combo: String, current_round_only: bool, decay: float, window: int) -> Dictionary:
	var weighted_sum = 0.0
	var weight_sum = 0.0
	var matches = 0
	var considered = 0
	for i in range(history.size() - 1, -1, -1):
		if considered >= window:
			break
		if current_round_only and i < current_round_start_index:
			break
		var event: Dictionary = history[i]
		var relevance = _event_relevance(event, club_id, shot_type, shot_form, combo)
		if relevance <= 0.0:
			continue
		var age = history.size() - 1 - i
		var recency_weight = pow(decay, age)
		var weight = recency_weight * relevance
		weighted_sum += float(event["quality_score"]) * weight
		weight_sum += weight
		matches += 1
		considered += 1
	return {
		"score": weighted_sum / weight_sum if weight_sum > 0.0 else 50.0,
		"weight": weight_sum,
		"matches": matches
	}

func _event_relevance(event: Dictionary, club_id: String, shot_type: int, shot_form: String, combo: String) -> float:
	# Exact club+form experiences teach the most. Related club/type/form history
	# still transfers a little, which avoids every new combination starting blank.
	if String(event.get("combo", "")) == combo and not combo.begins_with("|"):
		return 1.0
	var relevance = 0.0
	if not club_id.is_empty() and String(event.get("club_id", "")) == club_id:
		relevance += 0.55
	if int(event.get("shot_type", -1)) == shot_type:
		relevance += 0.20
	if String(event.get("shot_form", "")) == shot_form:
		relevance += 0.35
	return min(relevance, 0.85)

func _experience_score(execution_quality: String, outcome: String, perceived_execution_score: float) -> float:
	# Confidence learns primarily from how the golfer believes they executed,
	# not merely from where the ball finished. A good swing with a bad bounce can
	# therefore preserve comfort better than a mishit that gets lucky.
	if perceived_execution_score >= 0.0:
		var perceived = clamp(perceived_execution_score, 0.0, 100.0)
		if outcome == "WATER":
			return clamp(perceived * 0.82, 0.0, 100.0)
		return perceived
	match execution_quality:
		"GOOD":
			return 86.0 if outcome != "WATER" else 68.0
		"ACCEPTABLE":
			return 62.0 if outcome != "WATER" else 45.0
		"POOR":
			return 24.0 if outcome != "WATER" else 14.0
	return 50.0

func _baseline_from_identity(ability: float, confidence: float) -> float:
	return clamp(ability * 0.58 + confidence * 0.32 + 5.0, 20.0, 95.0)

func _normalize_form(shot_form: String) -> String:
	var value = shot_form.strip_edges().to_upper()
	return "NORMAL" if value.is_empty() else value

func _combo_key(club_id: String, shot_form: String) -> String:
	return "%s|%s" % [club_id, shot_form]
