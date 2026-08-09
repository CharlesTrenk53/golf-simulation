extends SceneTree

const QuietGolfer = preload("res://tests/quiet_golfer.gd")

var failures := 0

func _init() -> void:
	var carl = QuietGolfer.new()
	carl.profile = 2
	carl.apply_profile()
	carl.decision_variability = 0.0

	# Objective facts deliberately favor ATTACK. The first subjective assessment
	# says Carl does not trust it; the decision should follow Carl's belief state.
	var attack = _option("ATTACK", true, 68.0, 70.0, 42.0, 66.0, 38.0, 36.0)
	var layup = _option("LAYUP", false, 90.0, 50.0, 22.0, 72.0, 76.0, 82.0)
	var options = [attack, layup]
	var attack_eval = carl.evaluate_option(attack)
	var layup_eval = carl.evaluate_option(layup)
	_expect(String(attack_eval["decision_basis"]) == "SUBJECTIVE_ASSESSMENT", "pipeline options use subjective decision path")
	_expect(float(attack_eval["utility"]) < float(layup_eval["utility"]), "Carl's subjective distrust can outweigh objectively attractive attack")
	var first_choice = carl.choose_best_option(options)
	_expect(String(first_choice["name"]) == "LAYUP", "final choice follows golfer subjective assessment")

	# Keep the exact same objective assessment but change only Carl's subjective
	# belief/comfort/willingness. The chosen shot should be allowed to reverse.
	var trusted_attack = attack.duplicate(true)
	trusted_attack["assessment"]["subjective"]["assessed_reward"] = 82.0
	trusted_attack["assessment"]["subjective"]["assessed_risk"] = 24.0
	trusted_attack["assessment"]["subjective"]["believed_success_chance"] = 82.0
	trusted_attack["assessment"]["subjective"]["specific_confidence"] = 84.0
	trusted_attack["assessment"]["subjective"]["willingness"]["willingness_score"] = 88.0
	_expect(trusted_attack["assessment"]["objective"] == attack["assessment"]["objective"], "objective shot facts remain unchanged when golfer belief changes")
	var second_choice = carl.choose_best_option([trusted_attack, layup])
	_expect(String(second_choice["name"]) == "ATTACK", "changed subjective assessment can reverse the final decision")

	# Personality is downstream of perception. Rick and Carl can both recognize
	# the same attack as risky and low-confidence, but Rick can still choose it
	# because his risk tolerance, self-belief and stubbornness make him willing to
	# accept known risk. The perceived risk itself must remain identical.
	var rick = QuietGolfer.new()
	rick.profile = 1
	rick.apply_profile()
	rick.decision_variability = 0.0
	var known_risk_attack = _option("ATTACK", true, 42.0, 71.0, 55.0, 42.0, 45.0, 40.0)
	var sensible_layup = _option("LAYUP", false, 86.0, 64.0, 20.0, 80.0, 70.0, 75.0)
	var rick_attack_eval = rick.evaluate_option(known_risk_attack)
	var carl_attack_eval = carl.evaluate_option(known_risk_attack)
	_expect(float(rick_attack_eval["perceived_risk"]) == float(carl_attack_eval["perceived_risk"]), "personality does not rewrite perceived risk")
	_expect(float(rick_attack_eval["believed_success_chance"]) == 42.0, "Rick can accurately recognize a low believed success chance")
	_expect(float(rick_attack_eval["personality_override"]) > float(carl_attack_eval["personality_override"]), "reckless personality creates stronger willingness to accept known risk")
	var rick_choice = rick.choose_best_option([known_risk_attack, sensible_layup])
	var carl_choice = carl.choose_best_option([known_risk_attack, sensible_layup])
	_expect(String(rick_choice["name"]) == "ATTACK", "Rick can knowingly choose a risky shot anyway")
	_expect(String(carl_choice["name"]) == "LAYUP", "Carl can see the same risk and decline it")

	# Objective diagnostics must remain available after subjective choice migration.
	_expect(float(trusted_attack["assessment"]["objective"]["model_success_chance"]) == 68.0, "objective success probability remains available for diagnostics")
	_expect(float(trusted_attack["assessment"]["subjective"]["believed_success_chance"]) == 82.0, "golfer belief can differ from objective probability")

	carl.free()
	rick.free()
	if failures == 0:
		print("POC-08 SUBJECTIVE DECISION CHOICE TESTS PASSED")
		quit(0)
	else:
		push_error("POC-08 SUBJECTIVE DECISION CHOICE TESTS FAILED: %d" % failures)
		quit(1)

func _option(name: String, aggressive: bool, objective_success: float, perceived_reward: float, perceived_risk: float, believed_success: float, confidence_value: float, willingness_value: float) -> Dictionary:
	return {
		"name": name,
		"reward": 50.0,
		"risk": 30.0,
		"shot_type": 0 if aggressive else 1,
		"is_aggressive": aggressive,
		"model_success_chance": objective_success,
		"lie_improvement": 0.0,
		"assessment": {
			"objective": {
				"model_success_chance": objective_success,
				"base_reward": 75.0 if aggressive else 55.0,
				"base_risk": 45.0 if aggressive else 20.0
			},
			"subjective": {
				"assessed_reward": perceived_reward,
				"assessed_risk": perceived_risk,
				"believed_success_chance": believed_success,
				"specific_confidence": confidence_value,
				"willingness": {"willingness_score": willingness_value}
			}
		}
	}

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
