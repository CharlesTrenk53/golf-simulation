extends "res://scenes/participate_demo.gd"

# POC-28 Manual Acceptance Demo — Persistent Player Engagement Loop
# -----------------------------------------------------------------
# The player owns one persistent golfer inside one persistent living golf world.
# A played round is an ordinary group activity. When it finishes, authoritative
# results and consequences are archived, only that finished group retires, and the
# player returns to a lightweight world hub while the rest of the course remains
# alive. Starting another round inserts the same golfer into a new ordinary group
# without rebuilding the controller, world clock, memory, or development state.

const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const PlayerWorldSession = preload("res://simulation/player_world_session.gd")
const POC27World = preload("res://scenes/spectator_course_world.gd")
const POC27PopulationView = preload("res://scenes/spectator_population_view.gd")
const POC28Session = preload("res://scenes/poc28_participate_session.gd")
const POC27FocusController = preload("res://scenes/participate_focus_controller.gd")
const POC27Golfer = preload("res://scenes/golfer.gd")
const SpectatorGroupVisual = preload("res://scenes/spectator_group_visual.gd")
const ParticipatePacingController = preload("res://scenes/participate_pacing_controller.gd")

const AUTO_GROUP_IDS := ["group_2", "group_3", "group_4"]
const STATE_PLAYING := "PLAYING"
const STATE_RESULTS := "RESULTS"
const STATE_WORLD := "WORLD"

@export var compress_idle_waits: bool = true
@export var starting_world_day: int = 0
@export var starting_world_time_seconds: float = 28800.0

var world_session = null
var persistent_player = null
var participate_pacing = ParticipatePacingController.new()
var engagement_state: String = STATE_PLAYING
var active_player_group_id: String = ""
var round_number: int = 0
var last_completed_round: Dictionary = {}

var round_context_label: Label = null
var engagement_panel: PanelContainer = null
var engagement_title: Label = null
var engagement_body: Label = null
var engagement_action: Button = null


func _ready() -> void:
	initialize_demo()


func _process(delta: float) -> void:
	if not initialized:
		return
	if session != null:
		session.advance_visuals(delta)
	_sync_world_session_from_controller()

	if engagement_state == STATE_RESULTS:
		return

	if auto_advance and session != null:
		var real_step: float = clampf(delta, 0.0, max_real_step_seconds)
		if real_step > 0.0 and not session.presentation_busy():
			var advanced: bool = false
			if compress_idle_waits and engagement_state == STATE_PLAYING and not active_player_group_id.is_empty():
				var pacing: Dictionary = participate_pacing.idle_advance(controller, active_player_group_id)
				if str(pacing.get("mode", "")) == ParticipatePacingController.MODE_FAST_FORWARD:
					session.advance_time(float(pacing.get("delta_seconds", 0.0)), true)
					advanced = true
				elif str(pacing.get("mode", "")) == ParticipatePacingController.MODE_REALTIME:
					session.advance_time(real_step * maxf(simulation_speed, 0.01), true)
					advanced = true
			if not advanced:
				session.advance_time(real_step * maxf(simulation_speed, 0.01), true)

	_sync_world_session_from_controller()
	_refresh_presentation(delta)
	if engagement_state == STATE_PLAYING:
		_maybe_finalize_player_round()
	elif engagement_state == STATE_WORLD:
		_refresh_world_hub_text()


func initialize_demo() -> bool:
	if initialized:
		return true
	var course = POC27Course.build()
	if course == null or course.hole_count() != 18:
		return false

	persistent_player = _make_golfer(POC27Golfer.GolferProfile.CAREFUL_CARL)
	world_session = PlayerWorldSession.new()
	world_session.name = "PlayerWorldSession"
	add_child(world_session)
	if not world_session.configure(persistent_player, course, starting_world_day, starting_world_time_seconds):
		return false
	controller = world_session.controller

	# The player's activity is inserted first so the first launch starts on the
	# normal first tee. Other groups are ordinary autonomous course population.
	if not _enter_new_player_round():
		return false
	if not _add_initial_world_population():
		return false

	course_world = POC27World.new()
	course_world.name = "CourseWorld"
	add_child(course_world)
	if not course_world.configure(course):
		return false

	population_view = POC27PopulationView.new()
	population_view.name = "PopulationView"
	add_child(population_view)
	if not population_view.configure(course_world, controller):
		return false

	session = POC28Session.new()
	session.name = "PersistentParticipateSession"
	add_child(session)
	if not session.configure(controller, course_world, population_view):
		return false
	var started: Dictionary = session.start_session()
	if started.is_empty() or str(started.get("group_id", "")) != active_player_group_id:
		return false

	focus_controller = POC27FocusController.new()
	focus_controller.name = "ParticipateFocusController"
	add_child(focus_controller)
	if not focus_controller.configure(session, population_view):
		return false
	focus_controller.select_group(active_player_group_id)

	_build_environment()
	_build_hud()
	initialized = true
	_sync_world_session_from_controller()
	_refresh_presentation(1.0, true)
	return true


func snapshot() -> Dictionary:
	var base: Dictionary = super.snapshot()
	base["engagement_state"] = engagement_state
	base["round_number"] = round_number
	base["active_player_group_id"] = active_player_group_id
	base["persistent_world"] = world_session.snapshot() if world_session != null else {}
	base["persistent_player_instance_id"] = persistent_player.get_instance_id() if persistent_player != null else 0
	base["last_completed_round"] = last_completed_round.duplicate(true)
	return base


func _enter_new_player_round() -> bool:
	if world_session == null or persistent_player == null:
		return false
	var next_round: int = round_number + 1
	var group_id: String = "player_round_%d" % next_round
	var partner_a = _make_golfer(POC27Golfer.GolferProfile.WILD_BILL)
	var partner_b = _make_golfer(POC27Golfer.GolferProfile.RECKLESS_RICK)
	var partner_c = _make_golfer(POC27Golfer.GolferProfile.CAREFUL_CARL)
	var entered: Dictionary = world_session.enter_round(
		group_id,
		[partner_a, partner_b, partner_c],
		"default",
		0,
		player_seed + next_round * 1000
	)
	if not bool(entered.get("entered", false)):
		return false
	round_number = next_round
	active_player_group_id = group_id
	engagement_state = STATE_PLAYING
	return true


func _add_initial_world_population() -> bool:
	var auto_1a = _make_golfer(POC27Golfer.GolferProfile.WILD_BILL)
	var auto_1b = _make_golfer(POC27Golfer.GolferProfile.RECKLESS_RICK)
	if not world_session.add_world_group("group_2", [auto_1a, auto_1b], "default", other_seed):
		return false
	var auto_2a = _make_golfer(POC27Golfer.GolferProfile.RECKLESS_RICK)
	var auto_2b = _make_golfer(POC27Golfer.GolferProfile.CAREFUL_CARL)
	if not world_session.add_world_group("group_3", [auto_2a, auto_2b], "default", other_seed + 100):
		return false
	var auto_3a = _make_golfer(POC27Golfer.GolferProfile.CAREFUL_CARL)
	var auto_3b = _make_golfer(POC27Golfer.GolferProfile.WILD_BILL)
	return world_session.add_world_group("group_4", [auto_3a, auto_3b], "default", other_seed + 200)


func _unhandled_input(event: InputEvent) -> void:
	if not initialized or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if engagement_state == STATE_RESULTS:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_return_to_world()
			get_viewport().set_input_as_handled()
		return
	if engagement_state == STATE_WORLD:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_begin_next_round()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB or event.keycode == KEY_RIGHT:
			cycle_group(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_LEFT:
			cycle_group(-1)
			get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_TAB or event.keycode == KEY_RIGHT:
		cycle_group(1)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_LEFT:
		cycle_group(-1)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_1:
		select_group(active_player_group_id)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_2:
		select_group("group_2")
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_3:
		select_group("group_3")
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_4:
		select_group("group_4")
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		if decision_panel != null and decision_panel.visible:
			_commit_selected_choice()
			get_viewport().set_input_as_handled()


func _build_hud() -> void:
	super._build_hud()
	var canvas = get_node_or_null("ParticipateHUD")
	if canvas == null:
		return
	var info_panel = canvas.get_node_or_null("InfoPanel")
	if info_panel != null and info_panel.get_child_count() > 0:
		var margin = info_panel.get_child(0)
		if margin != null and margin.get_child_count() > 0:
			var box = margin.get_child(0)
			round_context_label = Label.new()
			round_context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			round_context_label.add_theme_font_size_override("font_size", 13)
			box.add_child(round_context_label)

	for child in canvas.get_children():
		if child is Label and str(child.text).begins_with("TAB /"):
			child.text = "TAB / ← → switch groups   •   1 = your group   •   2 / 3 / 4 = other groups   •   Enter commits / continues"

	engagement_panel = PanelContainer.new()
	engagement_panel.name = "EngagementPanel"
	engagement_panel.offset_left = 545.0
	engagement_panel.offset_top = 30.0
	engagement_panel.offset_right = 1010.0
	engagement_panel.offset_bottom = 535.0
	engagement_panel.visible = false
	canvas.add_child(engagement_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	engagement_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	engagement_title = Label.new()
	engagement_title.add_theme_font_size_override("font_size", 24)
	box.add_child(engagement_title)
	engagement_body = Label.new()
	engagement_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	engagement_body.custom_minimum_size = Vector2(420.0, 350.0)
	box.add_child(engagement_body)
	engagement_action = Button.new()
	engagement_action.pressed.connect(_on_engagement_action)
	box.add_child(engagement_action)


func _update_hud(presentation: Dictionary) -> void:
	super._update_hud(presentation)
	if round_context_label == null:
		return
	_sync_world_session_from_controller()
	var context: Dictionary = world_session.player_round_context() if world_session != null else {}
	if engagement_state != STATE_PLAYING or context.is_empty():
		round_context_label.text = ""
		return
	var front: Dictionary = context.get("front_nine", {})
	var back: Dictionary = context.get("back_nine", {})
	round_context_label.text = "YOUR ROUND • %s • %d holes complete • Front %s • Back %s" % [
		_score_label(int(context.get("score_to_par", 0))),
		int(context.get("holes_completed", 0)),
		_nine_label(front),
		_nine_label(back)
	]


func _update_decision_ui(presentation: Dictionary) -> void:
	var decision_id: String = str(presentation.get("decision_id", ""))
	var is_player_group: bool = str(presentation.get("group_id", "")) == active_player_group_id
	var playable: bool = engagement_state == STATE_PLAYING and is_player_group and str(presentation.get("mode", "")) == "PARTICIPATE" and not decision_id.is_empty()
	decision_panel.visible = playable
	if not playable:
		current_decision_id = ""
		choice_browser.clear()
		return
	if decision_id == current_decision_id:
		return

	current_decision_id = decision_id
	var choices: Array = presentation.get("choices", [])
	if not choice_browser.load_choices(choices):
		decision_panel.visible = false
		return
	var situation: Dictionary = presentation.get("situation", {})
	decision_title.text = "YOUR SHOT — %s" % str(presentation.get("shot", {}).get("golfer_name", "Golfer"))
	situation_label.text = "Hole %d • Shot %d • %s • %.1f yd" % [
		int(situation.get("hole_number", presentation.get("hole_number", 0))),
		int(situation.get("shot_number", 0)),
		str(situation.get("surface", "")),
		float(situation.get("remaining_distance_yards", 0.0))
	]
	choice_count_label.text = "%d authoritative choices — browsed without pruning" % choice_browser.candidate_count()
	_populate_clubs(choice_browser.default_path())


func _update_turn_alert() -> void:
	if turn_alert_label == null or session == null or engagement_state != STATE_PLAYING or active_player_group_id.is_empty():
		if turn_alert_label != null:
			turn_alert_label.text = ""
		return
	var player_decision: Dictionary = session.pending_human_decision(active_player_group_id)
	if player_decision.is_empty():
		turn_alert_label.text = ""
		return
	if focus_controller != null and focus_controller.selected_group_id() == active_player_group_id:
		turn_alert_label.text = "YOUR TURN — choose a shot below. The rest of the course is still live."
	else:
		turn_alert_label.text = "YOUR TURN — press 1 to return to your group."


func _commit_selected_choice() -> void:
	if engagement_state != STATE_PLAYING or session == null or focus_controller == null or decision_panel == null or not decision_panel.visible:
		return
	var candidate_index: int = selected_candidate_index()
	if candidate_index < 0:
		return
	var group_id: String = focus_controller.selected_group_id()
	if group_id != active_player_group_id:
		return
	var result: Dictionary = session.submit_human_choice(group_id, candidate_index, true)
	if bool(result.get("played", false)):
		current_decision_id = ""
		choice_browser.clear()
		decision_panel.visible = false
	_sync_world_session_from_controller()
	_refresh_presentation(0.0)


func _maybe_finalize_player_round() -> void:
	if not _player_round_authority_complete():
		return
	if session != null and session.group_presentation_busy(active_player_group_id):
		return
	_sync_world_session_from_controller()
	var finalized: Dictionary = world_session.finalize_player_round()
	if not bool(finalized.get("finalized", false)):
		return
	last_completed_round = finalized.get("round", {}).duplicate(true)
	engagement_state = STATE_RESULTS
	if decision_panel != null:
		decision_panel.visible = false
	_show_round_results(last_completed_round)


func _player_round_authority_complete() -> bool:
	if world_session == null or world_session.active_round.is_empty() or active_player_group_id.is_empty():
		return false
	var group = controller.living_course.population.group_by_id(active_player_group_id)
	var round_state = world_session.player_round_state()
	if group == null or round_state == null or not bool(round_state.complete):
		return false
	if str(group.status) != "FINISHED":
		return false
	if int(controller.traffic.group_hole(active_player_group_id)) != 0:
		return false
	return not controller.live_sessions.has(active_player_group_id) and not controller.blocked_transitions.has(active_player_group_id)


func _show_round_results(archive: Dictionary) -> void:
	if engagement_panel == null:
		return
	var stats: Dictionary = archive.get("statistics", {})
	var front: Dictionary = archive.get("front_nine", {})
	var back: Dictionary = archive.get("back_nine", {})
	var before: Dictionary = archive.get("development_before", {})
	var after: Dictionary = archive.get("development_after", {})
	engagement_title.text = "ROUND %d COMPLETE" % int(archive.get("sequence", round_number))
	engagement_body.text = "Score: %d  (%s)\nFront nine: %d  (%s)\nBack nine: %d  (%s)\n\nAuthoritative shots: %d\nPutts: %d\nPenalty strokes: %d\n\nCareer rounds: %d\nCourse clock: %s\n\nDurable development\n%s" % [
		int(archive.get("total_strokes", 0)),
		_score_label(int(archive.get("score_to_par", 0))),
		int(front.get("strokes", 0)),
		_score_label(int(front.get("score_to_par", 0))),
		int(back.get("strokes", 0)),
		_score_label(int(back.get("score_to_par", 0))),
		int(stats.get("total_shots", 0)),
		int(stats.get("putts", 0)),
		int(stats.get("penalty_strokes", 0)),
		int(world_session.golf_activity.career_rounds_played),
		_clock_label(world_session.world_time_seconds),
		_development_delta_text(before, after)
	]
	engagement_action.text = "RETURN TO WORLD  (Enter)"
	engagement_panel.visible = true


func _return_to_world() -> void:
	if engagement_state != STATE_RESULTS:
		return
	var finished_group_id: String = active_player_group_id
	_remove_group_visual(finished_group_id)
	active_player_group_id = ""
	engagement_state = STATE_WORLD
	_select_first_available_world_group()
	_refresh_world_hub_text()
	engagement_action.text = "PLAY ANOTHER ROUND  (Enter)"
	engagement_panel.visible = true


func _begin_next_round() -> void:
	if engagement_state != STATE_WORLD:
		return
	if not _enter_new_player_round():
		engagement_body.text = "Could not enter a new round. The persistent world remains intact."
		return
	if not _attach_group_visual(active_player_group_id):
		engagement_body.text = "Round entered authority but presentation could not attach the group."
		return
	if focus_controller != null:
		focus_controller.select_group(active_player_group_id)
	if session != null:
		session.attempt_release_next(true)
	engagement_panel.visible = false
	current_decision_id = ""
	choice_browser.clear()
	_sync_world_session_from_controller()
	_refresh_presentation(0.0, true)


func _on_engagement_action() -> void:
	if engagement_state == STATE_RESULTS:
		_return_to_world()
	elif engagement_state == STATE_WORLD:
		_begin_next_round()


func _refresh_world_hub_text() -> void:
	if engagement_state != STATE_WORLD or engagement_panel == null or world_session == null:
		return
	var activity: Dictionary = world_session.golf_activity.state()
	var development: Dictionary = world_session.development_snapshot()
	engagement_title.text = "LIVING GOLF WORLD"
	engagement_body.text = "%s\n\nRounds played: %d\nAuthoritative on-course shots: %d\nWorld day: %d\nCourse clock: %s\nGroups still in world: %d\n\nCurrent durable ability\nDrive %.2f  •  Approach %.2f\nShort game %.2f  •  Putting %.2f\n\nYour golfer and this golf world have not been rebuilt. Start another ordinary round when ready." % [
		str(persistent_player.golfer_name),
		int(activity.get("career_rounds_played", 0)),
		int(activity.get("total_on_course_exposure", 0)),
		int(world_session.world_day),
		_clock_label(world_session.world_time_seconds),
		controller.living_course.population.groups.size(),
		float(development.get(0, {}).get("effective_skill", persistent_player.driving)),
		float(development.get(1, {}).get("effective_skill", persistent_player.approach)),
		float(development.get(2, {}).get("effective_skill", persistent_player.short_game)),
		float(development.get(3, {}).get("effective_skill", persistent_player.putting))
	]


func _attach_group_visual(group_id: String) -> bool:
	if population_view == null or course_world == null or controller == null:
		return false
	if population_view.group_visual(group_id) != null:
		return true
	var group = controller.living_course.population.group_by_id(group_id)
	if group == null:
		return false
	var visual = SpectatorGroupVisual.new()
	visual.waiting_backoff_yards = maxf(population_view.first_tee_waiting_backoff_yards, 0.0)
	population_view.add_child(visual)
	if not visual.configure(group, course_world, controller.traffic):
		population_view.remove_child(visual)
		visual.queue_free()
		return false
	population_view.group_visuals[group_id] = visual
	if focus_controller != null and not focus_controller.group_ids.has(group_id):
		focus_controller.group_ids.append(group_id)
	return true


func _remove_group_visual(group_id: String) -> void:
	if population_view != null and population_view.group_visuals.has(group_id):
		var visual = population_view.group_visuals[group_id]
		population_view.group_visuals.erase(group_id)
		if visual != null and is_instance_valid(visual):
			if visual.get_parent() == population_view:
				population_view.remove_child(visual)
			visual.queue_free()
	if focus_controller != null:
		var index: int = focus_controller.group_ids.find(group_id)
		if index >= 0:
			focus_controller.group_ids.remove_at(index)
		if focus_controller.group_ids.is_empty():
			focus_controller.selected_index = -1
		else:
			focus_controller.selected_index = clampi(focus_controller.selected_index, 0, focus_controller.group_ids.size() - 1)


func _select_first_available_world_group() -> void:
	if focus_controller == null:
		return
	for group_id in AUTO_GROUP_IDS:
		if controller.living_course.population.group_by_id(group_id) != null and focus_controller.select_group(group_id):
			_refresh_presentation(0.0, true)
			return


func _sync_world_session_from_controller() -> void:
	if world_session == null or controller == null:
		return
	world_session.world_time_seconds = maxf(world_session.world_time_seconds, float(controller.current_time_seconds))
	if not world_session.active_round.is_empty():
		var group_id: String = str(world_session.active_round.get("group_id", ""))
		var group = controller.living_course.population.group_by_id(group_id)
		if group != null:
			world_session.active_round["status"] = str(group.status)


func _display_group_name(group_id: String) -> String:
	if not active_player_group_id.is_empty() and group_id == active_player_group_id:
		return "YOUR GROUP — YOU, BILL, RICK & CARL"
	match group_id:
		"group_2": return "GROUP 2 — BILL & RICK"
		"group_3": return "GROUP 3 — RICK & CARL"
		"group_4": return "GROUP 4 — CARL & BILL"
	return group_id.to_upper()


func _nine_label(summary: Dictionary) -> String:
	if int(summary.get("holes_completed", 0)) <= 0:
		return "—"
	return "%d (%s)" % [int(summary.get("strokes", 0)), _score_label(int(summary.get("score_to_par", 0)))]


func _score_label(to_par: int) -> String:
	if to_par == 0:
		return "E"
	return "+%d" % to_par if to_par > 0 else str(to_par)


func _clock_label(seconds: float) -> String:
	var total_minutes: int = maxi(0, int(seconds / 60.0))
	return "%02d:%02d" % [(total_minutes / 60) % 24, total_minutes % 60]


func _development_delta_text(before: Dictionary, after: Dictionary) -> String:
	var labels := ["Drive", "Approach", "Short game", "Putting"]
	var lines: Array[String] = []
	for shot_type in [0, 1, 2, 3]:
		var prior: float = float(before.get(shot_type, {}).get("effective_skill", 0.0))
		var current: float = float(after.get(shot_type, {}).get("effective_skill", prior))
		lines.append("%s: %.2f → %.2f  (%+.3f)" % [labels[shot_type], prior, current, current - prior])
	return "\n".join(lines)
