extends RefCounted

# POC-26E: Compact Human Choice Browser
# --------------------------------------
# Presentation-only indexing for the authority-issued human candidate list.
# Course-strategy candidates are browsed as Club -> Aim -> Shot Intent while
# putting collapses naturally to Putter -> Line -> Pace. The browser never
# removes, reranks, or edits candidates; it only maps a compact UI path back to
# the exact candidate index owned by ShotDecisionContract.

var choices: Array = []


func load_choices(choice_values: Array) -> bool:
	choices.clear()
	for value in choice_values:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var choice: Dictionary = value
		if not bool(choice.get("human_selectable", false)):
			continue
		if not choice.has("index"):
			continue
		choices.append(choice.duplicate(true))
	return not choices.is_empty()


func clear() -> void:
	choices.clear()


func candidate_count() -> int:
	return choices.size()


func club_options() -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for choice in choices:
		var key: String = _club_key(choice)
		if seen.has(key):
			continue
		seen[key] = true
		result.append({
			"key": key,
			"label": _club_label(choice)
		})
	return result


func aim_options(club_key: String) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for choice in choices:
		if _club_key(choice) != club_key:
			continue
		var key: String = _aim_key(choice)
		if seen.has(key):
			continue
		seen[key] = true
		result.append({
			"key": key,
			"label": _aim_label(choice)
		})
	return result


func shot_options(club_key: String, aim_key: String) -> Array:
	var result: Array = []
	for choice in choices:
		if _club_key(choice) != club_key or _aim_key(choice) != aim_key:
			continue
		var candidate_index: int = int(choice.get("index", -1))
		result.append({
			"key": str(candidate_index),
			"label": _shot_label(choice),
			"candidate_index": candidate_index,
			"choice": choice.duplicate(true)
		})
	return result


func resolve_candidate(club_key: String, aim_key: String, shot_key: String) -> int:
	for option_value in shot_options(club_key, aim_key):
		var option: Dictionary = option_value
		if str(option.get("key", "")) == shot_key:
			return int(option.get("candidate_index", -1))
	return -1


func default_path() -> Dictionary:
	if choices.is_empty():
		return {}
	var first: Dictionary = choices[0]
	return {
		"club_key": _club_key(first),
		"aim_key": _aim_key(first),
		"shot_key": str(int(first.get("index", -1))),
		"candidate_index": int(first.get("index", -1))
	}


func path_for_candidate(candidate_index: int) -> Dictionary:
	for choice in choices:
		if int(choice.get("index", -1)) != candidate_index:
			continue
		return {
			"club_key": _club_key(choice),
			"aim_key": _aim_key(choice),
			"shot_key": str(candidate_index),
			"candidate_index": candidate_index
		}
	return {}


func snapshot() -> Dictionary:
	var clubs: Array = club_options()
	var aim_count: int = 0
	var max_shots_in_leaf: int = 0
	for club_value in clubs:
		var club: Dictionary = club_value
		var aims: Array = aim_options(str(club.get("key", "")))
		aim_count += aims.size()
		for aim_value in aims:
			var aim: Dictionary = aim_value
			max_shots_in_leaf = maxi(
				max_shots_in_leaf,
				shot_options(str(club.get("key", "")), str(aim.get("key", ""))).size()
			)
	return {
		"candidate_count": candidate_count(),
		"club_count": clubs.size(),
		"aim_count": aim_count,
		"max_shots_in_leaf": max_shots_in_leaf,
		"default_path": default_path()
	}


func _club_key(choice: Dictionary) -> String:
	if str(choice.get("mode", "")) == "PUTTING":
		return "PUTTER"
	var club_id: String = str(choice.get("club_id", "")).strip_edges()
	if not club_id.is_empty():
		return club_id
	var club_name: String = str(choice.get("club_name", "")).strip_edges()
	if not club_name.is_empty():
		return club_name.to_upper().replace(" ", "_")
	return "OTHER"


func _club_label(choice: Dictionary) -> String:
	if str(choice.get("mode", "")) == "PUTTING":
		return "Putter"
	var label: String = str(choice.get("club_name", "")).strip_edges()
	if label.is_empty():
		label = str(choice.get("club_id", "Club"))
	return label


func _aim_key(choice: Dictionary) -> String:
	if str(choice.get("mode", "")) == "PUTTING":
		return "PUTT_LINE"
	var variant: String = str(choice.get("target_variant", "")).strip_edges()
	if not variant.is_empty():
		return variant
	return "TARGET"


func _aim_label(choice: Dictionary) -> String:
	if str(choice.get("mode", "")) == "PUTTING":
		return "Putt line"
	var variant: String = str(choice.get("target_variant", "TARGET"))
	return _humanize(variant)


func _shot_label(choice: Dictionary) -> String:
	if str(choice.get("mode", "")) == "PUTTING":
		return _humanize(str(choice.get("putting_strategy", "PUTT")))
	var intent = choice.get("intent", {})
	if typeof(intent) == TYPE_DICTIONARY and not intent.is_empty():
		var trajectory: String = _humanize(str(intent.get("trajectory_name", "NORMAL")))
		var shape: String = _humanize(str(intent.get("shape_name", "STRAIGHT")))
		var swing: String = _humanize(str(intent.get("swing_length_name", "FULL")))
		var technique: String = _humanize(str(intent.get("technique_name", "STOCK")))
		return "%s • %s • %s • %s" % [trajectory, shape, swing, technique]
	var name_value: String = str(choice.get("name", "SHOT")).strip_edges()
	if not name_value.is_empty():
		return _humanize(name_value)
	return "Shot %d" % int(choice.get("index", -1))


func _humanize(value: String) -> String:
	var text: String = value.strip_edges().replace("_", " ").to_lower()
	if text.is_empty():
		return ""
	return text.substr(0, 1).to_upper() + text.substr(1)
