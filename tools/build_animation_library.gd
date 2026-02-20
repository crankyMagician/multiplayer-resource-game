extends SceneTree

## Extracts all animations from the Quaternius Universal Animation Library (UAL1 + UAL2)
## monolithic GLBs and saves them as a single AnimationLibrary resource.
##
## Run: '/Applications/Mechanical Turk.app/Contents/MacOS/Mechanical Turk' --path . --script tools/build_animation_library.gd
##
## Track format: UAL GLBs use "Armature/Skeleton3D:bone_name" which matches the
## mannequin_f.glb skeleton structure — no remapping needed.

const UAL_SOURCES := [
	"res://assets/animations/ual/UAL1.glb",
	"res://assets/animations/ual/UAL2.glb",
]

const SKIP_ANIMATIONS := ["A_TPose"]

## Animations that should loop. UAL doesn't use a _Loop suffix convention,
## so we maintain an explicit list.
const LOOP_ANIMATIONS := {
	# Locomotion
	"Idle": true,
	"Idle_LookAround": true,
	"Idle_Tired": true,
	"Idle_Torch": true,
	"Idle_Talking": true,
	"Idle_FoldArms": true,
	"Idle_Lantern": true,
	"Idle_Rail": true,
	"Idle_Rail_Call": true,
	"Idle_TalkingPhone": true,
	"Idle_Shield": true,
	"Walk": true,
	"Walk_Formal": true,
	"Walk_Fwd": true,
	"Walk_Bwd": true,
	"Walk_L": true,
	"Walk_R": true,
	"Walk_Fwd_L": true,
	"Walk_Fwd_R": true,
	"Walk_Bwd_L": true,
	"Walk_Bwd_R": true,
	"Walk_Carry": true,
	"Jog_Fwd": true,
	"Jog_Bwd": true,
	"Jog_Left": true,
	"Jog_Right": true,
	"Jog_Fwd_L": true,
	"Jog_Fwd_R": true,
	"Jog_Bwd_L": true,
	"Jog_Bwd_R": true,
	"Jog_Fwd_LeanL": true,
	"Jog_Fwd_LeanR": true,
	"Sprint": true,
	"Sprint_Shield": true,
	# Crouch
	"Crouch_Idle": true,
	"Crouch_Fwd": true,
	"Crouch_Bwd": true,
	"Crouch_Left": true,
	"Crouch_Right": true,
	"Crouch_Fwd_L": true,
	"Crouch_Fwd_R": true,
	"Crouch_Bwd_L": true,
	"Crouch_Bwd_R": true,
	# Crawl
	"Crawl_Fwd": true,
	"Crawl_Bwd": true,
	"Crawl_Left": true,
	"Crawl_Right": true,
	"Crawl_Idle": true,
	# Airborne
	"Jump": true,
	# Climbing
	"Climb_Idle": true,
	"Climb_Up": true,
	"Climb_Down": true,
	# Swimming
	"Swim_Fwd": true,
	"Swim_Idle": true,
	# Sitting
	"Sitting_Idle": true,
	"Sitting_Idle02": true,
	"Sitting_Idle03": true,
	"Sitting_Nodding": true,
	"Sitting_Talking": true,
	"GroundSit_Idle": true,
	# Combat idles
	"Sword_Idle": true,
	"Pistol_Idle": true,
	"PunchKick_Enter": true,
	"Spell_Simple_Idle": true,
	"Spell_Double_Idle": true,
	"Sword_Block": true,
	"Sword_Aerial_Idle": true,
	"NinjaJump_Idle": true,
	# Counter/shop
	"Counter_Idle": true,
	# Driving
	"Driving": true,
	# Fishing
	"Fish_Cast_Idle": true,
	"Fish_OH_Idle": true,
	# Fixing
	"Fixing_Kneeling": true,
	# Farming
	"TreeChopping": true,
	"Mining": true,
	# Dance
	"Dance": true,
	"Crying": true,
	# Zombie
	"Zombie_Idle": true,
	"Zombie_Walk_Fwd": true,
	"Zombie_Walk_Bwd": true,
	"Zombie_Walk_L": true,
	"Zombie_Walk_R": true,
	"Zombie_Walk_Fwd_L": true,
	"Zombie_Walk_Fwd_R": true,
	"Zombie_Walk_Bwd_L": true,
	"Zombie_Walk_Bwd_R": true,
	"Zombie_Run_Fwd": true,
	"Zombie_Run_Bwd": true,
	"Zombie_Run_L": true,
	"Zombie_Run_R": true,
	"Zombie_Run_Fwd_L": true,
	"Zombie_Run_Fwd_R": true,
	"Zombie_Run_Bwd_L": true,
	"Zombie_Run_Bwd_R": true,
	# Air combat
	"LiftAir_Idle": true,
	# Wall run
	"WallRun_L": true,
	"WallRun_R": true,
}

func _initialize() -> void:
	var library = AnimationLibrary.new()
	var total_count := 0
	var skipped_dupes := 0

	for source_path in UAL_SOURCES:
		var scene: PackedScene = load(source_path)
		if scene == null:
			push_error("Failed to load: %s" % source_path)
			continue

		var inst = scene.instantiate()
		var anim_player: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
		if anim_player == null:
			push_error("No AnimationPlayer in: %s" % source_path)
			inst.free()
			continue

		var anim_list = anim_player.get_animation_list()
		print("[BuildAnimLib] %s: %d animations" % [source_path, anim_list.size()])

		for anim_name in anim_list:
			if anim_name in SKIP_ANIMATIONS:
				continue
			if library.has_animation(anim_name):
				skipped_dupes += 1
				continue

			var anim = anim_player.get_animation(anim_name).duplicate()
			anim.loop_mode = Animation.LOOP_LINEAR if LOOP_ANIMATIONS.has(anim_name) else Animation.LOOP_NONE
			library.add_animation(anim_name, anim)
			total_count += 1

		inst.free()

	var save_path := "res://assets/animations/player_animation_library.tres"
	var err := ResourceSaver.save(library, save_path)
	if err != OK:
		push_error("Failed to save AnimationLibrary: %s" % err)
	else:
		print("[BuildAnimLib] Saved %d animations to %s (skipped %d dupes)" % [total_count, save_path, skipped_dupes])

	quit()
