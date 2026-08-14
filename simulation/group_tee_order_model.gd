extends RefCounted

# POC-25: Group Tee Order Model
# -----------------------------
# Owns tee-box order independently from away play. The opening tee uses a
# reproducible seeded random permutation. On later holes, lower score on the
# immediately previous hole has honors; ties retain relative order from the
# previous tee. This model never executes or changes a golf shot.


func first_tee_order(member_count: int, seed_value: int) -> Array:
	if member_count <= 0:
		return []
	var order: Array = []
	for index in range(member_count):
		order.append(index)
	if member_count <= 1:
		return order

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Seeded Fisher-Yates keeps tests/replays deterministic while making the
	# opening order genuinely independent of member insertion order.
	for index in range(member_count - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var value = order[index]
		order[index] = order[swap_index]
		order[swap_index] = value
	return order


func honors_order(previous_hole_scores: Array, previous_tee_order: Array) -> Array:
	if previous_hole_scores.is_empty():
		return []
	var member_count: int = previous_hole_scores.size()
	var prior: Array = _normalized_prior_order(previous_tee_order, member_count)
	var prior_rank: Dictionary = {}
	for rank in range(prior.size()):
		prior_rank[int(prior[rank])] = rank

	var order: Array = []
	for index in range(member_count):
		if int(previous_hole_scores[index]) <= 0:
			return []
		order.append(index)
	order.sort_custom(func(a, b) -> bool:
		var a_index: int = int(a)
		var b_index: int = int(b)
		var a_score: int = int(previous_hole_scores[a_index])
		var b_score: int = int(previous_hole_scores[b_index])
		if a_score != b_score:
			return a_score < b_score
		return int(prior_rank.get(a_index, a_index)) < int(prior_rank.get(b_index, b_index))
	)
	return order


func is_valid_order(order: Array, member_count: int) -> bool:
	if member_count <= 0 or order.size() != member_count:
		return false
	var seen: Dictionary = {}
	for value in order:
		var member_index: int = int(value)
		if member_index < 0 or member_index >= member_count or seen.has(member_index):
			return false
		seen[member_index] = true
	return seen.size() == member_count


func _normalized_prior_order(previous_tee_order: Array, member_count: int) -> Array:
	if is_valid_order(previous_tee_order, member_count):
		return previous_tee_order.duplicate()
	var fallback: Array = []
	for index in range(member_count):
		fallback.append(index)
	return fallback
