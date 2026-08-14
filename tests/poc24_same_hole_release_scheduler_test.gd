extends SceneTree
const C=preload("res://simulation/course_definition.gd")
const R=preload("res://simulation/same_hole_release_scheduler.gd")
const G=preload("res://scenes/golfer.gd")
func _init()->void:
 var h=C.load_json("res://data/courses/poc12_proving_course.json").hole_by_number(1);var s=R.new()
 var c=G.new();c.profile=G.GolferProfile.CAREFUL_CARL;c.apply_profile()
 var b=G.new();b.profile=G.GolferProfile.WILD_BILL;b.apply_profile()
 var t:Vector3=h.tee_position();var d:Vector3=(h.pin_position-t).normalized();var a=t+d*220.0;var x=t+d*225.0;var y=t+d*340.0;var z=t+d*350.0
 var r={"member_results":[{"history":[{"landing_position":a,"relief_position":a,"surface_after":"FAIRWAY"},{"landing_position":y,"relief_position":y,"surface_after":"GREEN"}]},{"history":[{"landing_position":x,"relief_position":x,"surface_after":"FAIRWAY"},{"landing_position":z,"relief_position":z,"surface_after":"GREEN"}]}]}
 var ce:Dictionary=s.schedule_release("lead","carl_group",r,h,[c],100.0);var be:Dictionary=s.schedule_release("lead","bill_group",r,h,[b],100.0)
 assert(bool(ce.get("scheduled",false)) and bool(be.get("scheduled",false)))
 assert(str(ce.get("release_rule",""))=="RANGE_SAFE_AND_ALL_LEAD_GOLFERS_ON_GREEN" and str(be.get("release_rule",""))=="RANGE_SAFE_AND_ALL_LEAD_GOLFERS_ON_GREEN")
 var carl_range:float=float(ce.get("range_safe_time_seconds",0.0));var bill_range:float=float(be.get("range_safe_time_seconds",0.0));var green_time:float=float(ce.get("lead_group_green_time_seconds",0.0))
 assert(carl_range<bill_range);assert(carl_range<green_time);assert(bill_range<=green_time)
 var carl_release:float=float(ce.get("release_time_seconds",0.0));var bill_release:float=float(be.get("release_time_seconds",0.0));assert(is_equal_approx(carl_release,bill_release));assert(is_equal_approx(carl_release,100.0+green_time))
 assert(s.due_releases(carl_release-0.01).is_empty());var due:Array=s.due_releases(carl_release+0.01);assert(due.size()==2);assert(str(due[0].get("following_group_id",""))=="bill_group" or str(due[0].get("following_group_id",""))=="carl_group");assert(str(due[1].get("following_group_id",""))!=str(due[0].get("following_group_id","")))
 assert(s.pending_release("carl_group").is_empty() and s.pending_release("bill_group").is_empty())
 print("POC24_RELEASE_SUMMARY carl_range=%.1f bill_range=%.1f green=%.1f release=%.1f"%[carl_range,bill_range,green_time,carl_release]);print("POC-24F GREEN-GATED SPACING-AWARE TEE RELEASE SCHEDULING PASSED");c.free();b.free();quit(0)
