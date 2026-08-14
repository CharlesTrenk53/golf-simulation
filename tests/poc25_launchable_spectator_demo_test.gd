extends SceneTree

const SpectatorDemoScene = preload("res://scenes/spectator_demo.tscn")


func _init() -> void:
	# SceneTree._init() itself runs before newly-added Node3D children are guaranteed
	# to have completed their normal enter-tree/ready lifecycle. Defer the proof one
	# idle turn, then allow one process frame after adding the demo before asserting.
	call_deferred("_run_proof")


func _run_proof() -> void:
	var demo = SpectatorDemoScene.instantiate()
	demo.auto_advance = false
	get_root().add_child(demo)
	await process_frame

	assert(demo.initialized)
	assert(demo.is_inside_tree())
	assert(demo.spectator_camera != null and demo.spectator_camera.is_inside_tree())
	var initial: Dictionary = demo.snapshot()
	assert(bool(initial.get("initialized", false)))
	assert(not bool(initial.get("physical_round_complete", true)))
	var focus: Dictionary = initial.get("focus", {})
	assert(str(focus.get("group_id", "")) == "group_1")
	assert(str(focus.get("status", "")) == "PLAYING")
	assert(int(focus.get("hole_number", 0)) == 1)
	assert(focus.get("available_group_ids", []).size() == 2)
	assert(str(initial.get("hud_status", "")).contains("PLAYING"))
	assert(not str(initial.get("hud_members", "")).is_empty())
	assert(demo.spectator_camera.current)

	assert(demo.select_group("group_2"))
	var waiting: Dictionary = demo.snapshot()
	var waiting_focus: Dictionary = waiting.get("focus", {})
	assert(str(waiting_focus.get("group_id", "")) == "group_2")
	assert(str(waiting_focus.get("status", "")) == "WAITING")
	assert(int(waiting_focus.get("hole_number", 0)) == 1)
	assert(str(waiting.get("hud_status", "")).contains("WAITING"))

	assert(demo.cycle_group(1) == "group_1")
	var back_to_lead: Dictionary = demo.snapshot()
	assert(str(back_to_lead.get("focus", {}).get("group_id", "")) == "group_1")
	assert(not str(back_to_lead.get("hud_shot", "")).is_empty())

	print("POC25_DEMO_SUMMARY selected=%s lead_status=%s follower_status=%s groups=%d" % [
		str(back_to_lead.get("focus", {}).get("group_id", "")),
		str(back_to_lead.get("focus", {}).get("status", "")),
		str(waiting_focus.get("status", "")),
		int(focus.get("available_group_ids", []).size())
	])
	print("POC-25H LAUNCHABLE LIVING SPECTATOR DEMO PASSED")

	demo.queue_free()
	quit(0)
