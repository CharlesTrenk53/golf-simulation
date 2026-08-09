extends RefCounted

# POC-07A: a compact club model. Distances are simulation units matching the
# existing POC scale, not literal yards. Each club carries a preferred lie set
# so later decision logic can eliminate implausible choices before evaluation.

var clubs: Array[Dictionary] = []


func _init() -> void:
	clubs = [
		_club("DRIVER", "Driver", 70.0, 9.0, 0, ["TEE", "FAIRWAY"]),
		_club("3_WOOD", "3 Wood", 60.0, 7.0, 0, ["TEE", "FAIRWAY"]),
		_club("5_IRON", "5 Iron", 46.0, 5.5, 1, ["TEE", "FAIRWAY", "ROUGH"]),
		_club("7_IRON", "7 Iron", 36.0, 4.5, 1, ["TEE", "FAIRWAY", "ROUGH"]),
		_club("9_IRON", "9 Iron", 27.0, 3.5, 1, ["FAIRWAY", "ROUGH"]),
		_club("PITCHING_WEDGE", "Pitching Wedge", 20.0, 3.0, 2, ["FAIRWAY", "ROUGH", "BUNKER"]),
		_club("SAND_WEDGE", "Sand Wedge", 14.0, 4.0, 2, ["FAIRWAY", "ROUGH", "BUNKER"]),
		_club("PUTTER", "Putter", 8.0, 1.0, 3, ["GREEN"])
	]


func _club(id: String, display_name: String, carry_distance: float, dispersion: float, shot_type: int, allowed_surfaces: Array[String]) -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"carry_distance": carry_distance,
		"dispersion": dispersion,
		"shot_type": shot_type,
		"allowed_surfaces": allowed_surfaces
	}


func all_clubs() -> Array[Dictionary]:
	return clubs.duplicate(true)


func get_club(club_id: String) -> Dictionary:
	for club in clubs:
		if club["id"] == club_id:
			return club.duplicate(true)
	return {}


func clubs_for_surface(surface: String) -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	for club in clubs:
		if surface in club["allowed_surfaces"]:
			available.append(club.duplicate(true))
	return available


func effective_carry(club: Dictionary, golfer: Node, surface: String, lie_quality: float = 1.0) -> float:
	var base_carry: float = club["carry_distance"]
	var shot_type = int(club["shot_type"])
	# Technical skill now has only a modest carry effect: centered, efficient
	# contact matters, but raw distance comes primarily from physical capacity.
	var ability: float = golfer.get_shot_ability(shot_type)
	var strike_factor = lerp(0.94, 1.04, ability / 100.0)
	var physical_factor = golfer.physical_distance_factor(shot_type) if golfer.has_method("physical_distance_factor") else 1.0
	var lie_factor = clamp(lie_quality, 0.45, 1.0)

	if surface == "ROUGH":
		lie_factor *= 0.90
	elif surface == "BUNKER":
		lie_factor *= 0.78

	return base_carry * strike_factor * physical_factor * lie_factor


func effective_dispersion(club: Dictionary, golfer: Node, surface: String, lie_quality: float = 1.0) -> float:
	var base_dispersion: float = club["dispersion"]
	var ability: float = golfer.get_shot_ability(int(club["shot_type"]))
	var ability_factor = lerp(1.45, 0.65, ability / 100.0)
	var lie_penalty = 1.0 + (1.0 - lie_quality)
	if surface == "ROUGH":
		lie_penalty *= 1.15
	elif surface == "BUNKER":
		lie_penalty *= 1.30
	return base_dispersion * ability_factor * lie_penalty


func best_distance_match(golfer: Node, surface: String, lie_quality: float, desired_distance: float) -> Dictionary:
	var available = clubs_for_surface(surface)
	if available.is_empty():
		return {}
	var best: Dictionary = available[0]
	var best_gap = INF
	for club in available:
		var carry = effective_carry(club, golfer, surface, lie_quality)
		var gap = abs(carry - desired_distance)
		if gap < best_gap:
			best_gap = gap
			best = club
	return best.duplicate(true)
