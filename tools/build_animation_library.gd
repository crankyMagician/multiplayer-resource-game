extends SceneTree

const ANIM_CLIPS := [
	"idle",
	"walk_forward",
	"walk_backward",
	"jog_forward",
	"jog_backward",
	"run",
	"run_to_stop",
	"crouch_idle",
	"crouch_walk",
	"falling",
	"jump_up",
	"landing",
	"turn_left",
	"turn_right",
	"hoe_swing",
	"axe_chop",
	"watering",
	"harvest_pickup",
	"crafting_interact",
	"fishing_cast",
	"fishing_idle",
]

const LOOP_CLIPS := {
	"idle": true,
	"walk_forward": true,
	"walk_backward": true,
	"jog_forward": true,
	"jog_backward": true,
	"run": true,
	"crouch_idle": true,
	"crouch_walk": true,
	"falling": true,
	"turn_left": true,
	"turn_right": true,
	"fishing_idle": true,
}

func _initialize() -> void:
	var library = AnimationLibrary.new()

	for clip in ANIM_CLIPS:
		var path := "res://assets/animations/%s.glb" % clip
		var scene := load(path)
		if scene == null:
			push_error("Missing animation scene: %s" % path)
			continue

		var inst = scene.instantiate()
		var anim_player = inst.find_child("AnimationPlayer", true, false)
		if anim_player == null:
			push_error("AnimationPlayer not found in %s" % path)
			continue

		var anim_list = anim_player.get_animation_list()
		if anim_list.is_empty():
			push_error("No animations found in %s" % path)
			continue

		var anim = anim_player.get_animation(anim_list[0]).duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR if LOOP_CLIPS.has(clip) else Animation.LOOP_NONE
		_remap_tracks_to_skeleton(anim)
		library.add_animation(clip, anim)

	var save_path := "res://assets/animations/player_animation_library.tres"
	var err := ResourceSaver.save(library, save_path)
	if err != OK:
		push_error("Failed to save AnimationLibrary: %s" % err)

	quit()


## Remap Node3D bone paths to Skeleton3D bone paths.
## Animation GLBs (no mesh) import bones as Node3D children:
##   RootNode/mixamorig_Hips/mixamorig_Spine/mixamorig_Spine1
## Player character GLB (with mesh) uses Skeleton3D:
##   RootNode/Skeleton3D:mixamorig_Spine1
## This function converts the former to the latter.
func _remap_tracks_to_skeleton(anim: Animation) -> void:
	for i in anim.get_track_count():
		var path := anim.track_get_path(i)
		var path_str := String(path)

		# Only remap bone tracks (paths starting with RootNode/mixamorig_)
		if not path_str.begins_with("RootNode/mixamorig_"):
			continue

		# The last segment after the final "/" is the bone name
		var bone_name := path_str.get_slice("/", path_str.count("/"))
		var new_path := NodePath("RootNode/Skeleton3D:" + bone_name)
		anim.track_set_path(i, new_path)
