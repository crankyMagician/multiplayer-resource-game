class_name ExcursionGenerator
extends RefCounted

## Procedural excursion arena generator using FastNoiseLite.
## All functions are static — deterministic from seed + season + offset.

const ARENA_SIZE: float = 160.0
const GRID_RESOLUTION: int = 160 # vertices per axis = GRID_RESOLUTION + 1
const HEIGHT_RANGE: float = 6.0
const SPAWN_FLATTEN_RADIUS: float = 12.0
const EXIT_FLATTEN_RADIUS: float = 6.0
const PATH_HALF_WIDTH: float = 4.0

enum Biome { GRASSLAND, DENSE_FOREST, ROCKY_OUTCROP, WATER_EDGE, FLOWER_FIELD, RARE_GROVE }

# --- Synty Model Tables ---

const TREE_MODELS: Dictionary = {
	"spring": [
		"res://assets/synty/nature/models/SM_Tree_Round_01.glb",
		"res://assets/synty/nature/models/SM_Tree_Round_02.glb",
		"res://assets/synty/nature/models/SM_Tree_Birch_01.glb",
		"res://assets/synty/nature/models/SM_Tree_Birch_02.glb",
	],
	"summer": [
		"res://assets/synty/nature/models/SM_Tree_Large_01.glb",
		"res://assets/synty/nature/models/SM_Tree_Round_03.glb",
		"res://assets/synty/farm/models/SM_Generic_Tree_01.glb",
		"res://assets/synty/farm/models/SM_Generic_Tree_02.glb",
	],
	"autumn": [
		"res://assets/synty/nature/models/SM_Tree_Round_04.glb",
		"res://assets/synty/nature/models/SM_Tree_Round_05.glb",
		"res://assets/synty/nature/models/SM_Tree_Birch_03.glb",
		"res://assets/synty/nature/models/SM_Tree_Birch_Dead_01.glb",
	],
	"winter": [
		"res://assets/synty/nature/models/SM_Tree_PolyPine_01.glb",
		"res://assets/synty/nature/models/SM_Tree_PolyPine_02.glb",
		"res://assets/synty/nature/models/SM_Tree_Generic_Dead_01.glb",
		"res://assets/synty/nature/models/SM_Tree_PolyPine_03.glb",
	],
}

const ROCK_MODELS: Array = [
	"res://assets/synty/nature/models/SM_Rock_01.glb",
	"res://assets/synty/nature/models/SM_Rock_02.glb",
	"res://assets/synty/nature/models/SM_Rock_03.glb",
	"res://assets/synty/nature/models/SM_Rock_04.glb",
	"res://assets/synty/nature/models/SM_Rock_Boulder_01.glb",
]

const FLOWER_MODELS: Array = [
	"res://assets/synty/farm/models/SM_Env_Flowers_01.glb",
	"res://assets/synty/farm/models/SM_Env_Flowers_02.glb",
	"res://assets/synty/farm/models/SM_Env_Flowers_03.glb",
	"res://assets/synty/nature/models/SM_Plant_Bush_01.glb",
	"res://assets/synty/nature/models/SM_Plant_Fern_01.glb",
	"res://assets/synty/nature/models/SM_Plant_Fern_02.glb",
	"res://assets/synty/nature/models/SM_Plant_Fern_03.glb",
]

const CLIFF_MODELS: Array = [
	"res://assets/synty/city/models/SM_Gen_Env_Cliff_01.glb",
	"res://assets/synty/city/models/SM_Gen_Env_Cliff_02.glb",
	"res://assets/synty/city/models/SM_Gen_Env_Cliff_03.glb",
	"res://assets/synty/city/models/SM_Gen_Env_Cliff_04.glb",
]

const RUIN_COLUMN_MODELS: Array = [
	"res://assets/synty/tropical/models/SM_Bld_Ruins_Column_01.glb",
	"res://assets/synty/tropical/models/SM_Bld_Ruins_Column_02.glb",
	"res://assets/synty/tropical/models/SM_Bld_Ruins_Column_03.glb",
]

const RUIN_ARCHWAY_MODELS: Array = [
	"res://assets/synty/tropical/models/SM_Bld_Ruins_Archway_01.glb",
	"res://assets/synty/tropical/models/SM_Bld_Ruins_Archway_02.glb",
]

const MONOLITH_MODELS: Array = [
	"res://assets/synty/tropical/models/SM_Env_Monolith_01.glb",
	"res://assets/synty/tropical/models/SM_Env_Monolith_02.glb",
]

const TORCH_MODEL: String = "res://assets/synty/dungeon/models/SM_Prop_Torch_Ornate_01.glb"
const SMALL_ROCK_MODELS: Array = [
	"res://assets/synty/farm/models/SM_Generic_Small_Rocks_01.glb",
	"res://assets/synty/farm/models/SM_Generic_Small_Rocks_02.glb",
	"res://assets/synty/farm/models/SM_Generic_Small_Rocks_03.glb",
]

const BOULDER_MODEL: String = "res://assets/synty/nature/models/SM_Rock_Boulder_01.glb"

# --- Zone-Specific Model Tables ---

# Coastal Wreckage (pirate + tropical packs)
const COASTAL_TREE_MODELS: Dictionary = {
	"spring": [
		"res://assets/synty/tropical/models/SM_Env_Tree_Palm_01.glb",
		"res://assets/synty/tropical/models/SM_Env_Tree_Palm_02.glb",
		"res://assets/synty/tropical/models/SM_Env_Tree_Palm_03.glb",
		"res://assets/synty/nature/models/SM_Tree_Round_01.glb",
	],
	"summer": [
		"res://assets/synty/tropical/models/SM_Env_Tree_Palm_01.glb",
		"res://assets/synty/tropical/models/SM_Env_Tree_Palm_04.glb",
		"res://assets/synty/tropical/models/SM_Env_Tree_Banana_01.glb",
		"res://assets/synty/tropical/models/SM_Env_Tree_Banana_02.glb",
	],
	"autumn": [
		"res://assets/synty/tropical/models/SM_Env_Tree_Palm_02.glb",
		"res://assets/synty/tropical/models/SM_Env_Tree_Palm_03.glb",
		"res://assets/synty/nature/models/SM_Tree_Round_04.glb",
		"res://assets/synty/tropical/models/SM_Env_Tree_Forest_01.glb",
	],
	"winter": [
		"res://assets/synty/tropical/models/SM_Env_Tree_Palm_01.glb",
		"res://assets/synty/tropical/models/SM_Env_Tree_Palm_02.glb",
		"res://assets/synty/nature/models/SM_Tree_Generic_Dead_01.glb",
		"res://assets/synty/tropical/models/SM_Env_Tree_Forest_02.glb",
	],
}
const COASTAL_ROCK_MODELS: Array = [
	"res://assets/synty/tropical/models/SM_Env_Rock_01.glb",
	"res://assets/synty/tropical/models/SM_Env_Rock_02.glb",
	"res://assets/synty/tropical/models/SM_Env_Rock_03.glb",
	"res://assets/synty/tropical/models/SM_Env_Rock_Round_01.glb",
	"res://assets/synty/nature/models/SM_Rock_Boulder_01.glb",
]
const COASTAL_FLORA: Array = [
	"res://assets/synty/tropical/models/SM_Env_Bush_Palm_01.glb",
	"res://assets/synty/tropical/models/SM_Env_Bush_Palm_02.glb",
	"res://assets/synty/tropical/models/SM_Env_Fern_01.glb",
	"res://assets/synty/tropical/models/SM_Env_Fern_02.glb",
	"res://assets/synty/tropical/models/SM_Env_Seaweed_01.glb",
	"res://assets/synty/tropical/models/SM_Env_Flowers_01.glb",
]
const PIRATE_PROPS: Array = [
	"res://assets/synty/pirate/models/SM_Prop_Barrel_01.glb",
	"res://assets/synty/pirate/models/SM_Prop_Barrel_02.glb",
	"res://assets/synty/pirate/models/SM_Prop_Barrel_03.glb",
	"res://assets/synty/pirate/models/SM_Prop_Anchor_01.glb",
	"res://assets/synty/pirate/models/SM_Prop_Cannon_01.glb",
	"res://assets/synty/tropical/models/SM_Prop_ShipWreck_01.glb",
	"res://assets/synty/tropical/models/SM_Prop_ShipWreck_02.glb",
	"res://assets/synty/pirate/models/SM_Prop_Crate_01.glb",
	"res://assets/synty/pirate/models/SM_Prop_Crate_02.glb",
	"res://assets/synty/tropical/models/SM_Env_DriftWood_01.glb",
	"res://assets/synty/tropical/models/SM_Env_DriftWood_02.glb",
	"res://assets/synty/tropical/models/SM_Prop_Coral_01.glb",
	"res://assets/synty/tropical/models/SM_Prop_Coral_02.glb",
]

# Fungal Hollow (dungeon packs)
const FUNGAL_TREE_MODELS: Dictionary = {
	"spring": [
		"res://assets/synty/nature/models/SM_Tree_Dead_01.glb",
		"res://assets/synty/nature/models/SM_Tree_Dead_02.glb",
		"res://assets/synty/nature/models/SM_Tree_Swamp_01.glb",
		"res://assets/synty/nature/models/SM_Tree_Swamp_02.glb",
	],
	"summer": [
		"res://assets/synty/nature/models/SM_Tree_Dead_01.glb",
		"res://assets/synty/nature/models/SM_Tree_Dead_03.glb",
		"res://assets/synty/nature/models/SM_Tree_Swamp_03.glb",
		"res://assets/synty/nature/models/SM_Tree_Swamp_04.glb",
	],
	"autumn": [
		"res://assets/synty/nature/models/SM_Tree_Dead_02.glb",
		"res://assets/synty/nature/models/SM_Tree_Dead_03.glb",
		"res://assets/synty/nature/models/SM_Tree_Swamp_01.glb",
		"res://assets/synty/nature/models/SM_Tree_Swamp_Branch_01.glb",
	],
	"winter": [
		"res://assets/synty/nature/models/SM_Tree_Dead_01.glb",
		"res://assets/synty/nature/models/SM_Tree_Dead_02.glb",
		"res://assets/synty/nature/models/SM_Tree_Dead_03.glb",
		"res://assets/synty/nature/models/SM_Tree_Generic_Dead_01.glb",
	],
}
const FUNGAL_ROCK_MODELS: Array = [
	"res://assets/synty/nature/models/SM_Rock_01.glb",
	"res://assets/synty/nature/models/SM_Rock_02.glb",
	"res://assets/synty/nature/models/SM_Rock_03.glb",
	"res://assets/synty/nature/models/SM_Rock_04.glb",
	"res://assets/synty/nature/models/SM_Rock_Boulder_01.glb",
]
const FUNGAL_FLORA: Array = [
	"res://assets/synty/dungeon/models/SM_Env_Mushroom_Giant_01.glb",
	"res://assets/synty/dungeon/models/SM_Env_Mushroom_Giant_02.glb",
	"res://assets/synty/dungeon/models/SM_Env_Mushroom_Giant_03.glb",
	"res://assets/synty/dungeon/models/SM_Env_Mushroom_Small_01.glb",
	"res://assets/synty/dungeon/models/SM_Env_Mushroom_Small_02.glb",
	"res://assets/synty/dungeon/models/SM_Env_Mushroom_Small_03.glb",
	"res://assets/synty/nature/models/SM_Plant_Fern_01.glb",
]
const DUNGEON_PROPS: Array = [
	"res://assets/synty/dungeon/models/SM_Prop_Torch_Ornate_01.glb",
	"res://assets/synty/dungeon/models/SM_Prop_Torch_Ornate_02.glb",
	"res://assets/synty/dungeon/models/SM_Prop_Brazier_01.glb",
	"res://assets/synty/dungeon/models/SM_Prop_Chain_01.glb",
	"res://assets/synty/dungeon/models/SM_Prop_Candle_Stand_01.glb",
	"res://assets/synty/dungeon/models/SM_Env_Bone_Skull_01.glb",
	"res://assets/synty/dungeon/models/SM_Env_Bone_Skull_02.glb",
	"res://assets/synty/dungeon/models/SM_Env_Bone_Ribcage_01.glb",
	"res://assets/synty/dungeon/models/SM_Env_Cobweb_01.glb",
]
const DUNGEON_RUIN_MODELS: Array = [
	"res://assets/synty/dungeon/models/SM_Env_Ceiling_Stone_Pillar_01.glb",
	"res://assets/synty/dungeon/models/SM_Env_Ceiling_Stone_Pillar_02.glb",
	"res://assets/synty/dungeon/models/SM_Prop_Torch_Ornate_01.glb",
]

# Volcanic Crest (western pack)
const VOLCANIC_TREE_MODELS: Dictionary = {
	"spring": [
		"res://assets/synty/western/models/SM_Env_Cactus_Large_01.glb",
		"res://assets/synty/western/models/SM_Env_Cactus_Large_02.glb",
		"res://assets/synty/western/models/SM_Env_Cactus_01.glb",
		"res://assets/synty/nature/models/SM_Tree_Dead_01.glb",
	],
	"summer": [
		"res://assets/synty/western/models/SM_Env_Cactus_Large_03.glb",
		"res://assets/synty/western/models/SM_Env_Cactus_Large_04.glb",
		"res://assets/synty/western/models/SM_Env_Cactus_02.glb",
		"res://assets/synty/western/models/SM_Env_Cactus_Large_05.glb",
	],
	"autumn": [
		"res://assets/synty/western/models/SM_Env_Cactus_Large_01.glb",
		"res://assets/synty/western/models/SM_Env_Cactus_03.glb",
		"res://assets/synty/nature/models/SM_Tree_Dead_02.glb",
		"res://assets/synty/western/models/SM_Env_Tree_Dead_01.glb",
	],
	"winter": [
		"res://assets/synty/western/models/SM_Env_Cactus_Large_02.glb",
		"res://assets/synty/nature/models/SM_Tree_Dead_03.glb",
		"res://assets/synty/western/models/SM_Env_Tree_Dead_01.glb",
		"res://assets/synty/nature/models/SM_Tree_Generic_Dead_01.glb",
	],
}
const VOLCANIC_ROCK_MODELS: Array = [
	"res://assets/synty/nature/models/SM_Rock_01.glb",
	"res://assets/synty/nature/models/SM_Rock_02.glb",
	"res://assets/synty/nature/models/SM_Rock_03.glb",
	"res://assets/synty/nature/models/SM_Rock_04.glb",
	"res://assets/synty/nature/models/SM_Rock_Boulder_01.glb",
]
const WESTERN_PROPS: Array = [
	"res://assets/synty/western/models/SM_Prop_WagonWheel_01.glb",
	"res://assets/synty/western/models/SM_Prop_Cart_01.glb",
	"res://assets/synty/western/models/SM_Prop_Cart_02.glb",
	"res://assets/synty/western/models/SM_Prop_Barrel_Dirt_01.glb",
	"res://assets/synty/western/models/SM_Prop_Campfire_01.glb",
	"res://assets/synty/western/models/SM_Prop_Campfire_Small_01.glb",
	"res://assets/synty/western/models/SM_Prop_Crate_01.glb",
	"res://assets/synty/western/models/SM_Prop_Crate_02.glb",
	"res://assets/synty/western/models/SM_Prop_SkullPole_01.glb",
	"res://assets/synty/western/models/SM_Prop_Wagon_Destroyed_01.glb",
]

# Frozen Pantry (snow + knights packs)
const FROZEN_TREE_MODELS: Dictionary = {
	"spring": [
		"res://assets/synty/knights/models/SM_Env_Tree_01_Snow.glb",
		"res://assets/synty/knights/models/SM_Env_Tree_02_Snow.glb",
		"res://assets/synty/knights/models/SM_Env_Tree_03_Snow.glb",
		"res://assets/synty/nature/models/SM_Tree_PolyPine_01.glb",
	],
	"summer": [
		"res://assets/synty/knights/models/SM_Env_Tree_01_Snow.glb",
		"res://assets/synty/knights/models/SM_Env_Tree_02_Snow.glb",
		"res://assets/synty/knights/models/SM_Env_Tree_Twisted_01_Snow.glb",
		"res://assets/synty/nature/models/SM_Tree_PolyPine_02.glb",
	],
	"autumn": [
		"res://assets/synty/knights/models/SM_Env_Tree_01_Snow.glb",
		"res://assets/synty/knights/models/SM_Env_Tree_03_Snow.glb",
		"res://assets/synty/knights/models/SM_Env_Tree_Twisted_02_Snow.glb",
		"res://assets/synty/nature/models/SM_Tree_PolyPine_03.glb",
	],
	"winter": [
		"res://assets/synty/knights/models/SM_Env_Tree_01_Snow.glb",
		"res://assets/synty/knights/models/SM_Env_Tree_02_Snow.glb",
		"res://assets/synty/knights/models/SM_Env_Tree_03_Snow.glb",
		"res://assets/synty/knights/models/SM_Env_Tree_Twisted_01_Snow.glb",
	],
}
const FROZEN_ROCK_MODELS: Array = [
	"res://assets/synty/nature/models/SM_Rock_01.glb",
	"res://assets/synty/nature/models/SM_Rock_02.glb",
	"res://assets/synty/nature/models/SM_Rock_03.glb",
	"res://assets/synty/knights/models/SM_Env_Cliff_01.glb",
	"res://assets/synty/knights/models/SM_Env_Cliff_02.glb",
]
const FROZEN_FLORA: Array = [
	"res://assets/synty/nature/models/SM_Plant_Fern_01.glb",
	"res://assets/synty/nature/models/SM_Plant_Bush_01.glb",
]
const KNIGHT_PROPS: Array = [
	"res://assets/synty/knights/models/SM_Prop_Banner_01.glb",
	"res://assets/synty/knights/models/SM_Prop_Banner_02.glb",
	"res://assets/synty/knights/models/SM_Prop_Banner_03.glb",
	"res://assets/synty/knights/models/SM_Prop_Brazier_01_Snow.glb",
	"res://assets/synty/knights/models/SM_Prop_Statue_01.glb",
	"res://assets/synty/knights/models/SM_Bld_Castle_Pillar_01.glb",
	"res://assets/synty/knights/models/SM_Bld_Castle_Flag_01.glb",
	"res://assets/synty/knights/models/SM_Bld_Castle_Tower_Mini_01_Snow.glb",
]

# --- Zone Configurations ---

const ZONE_CONFIGS: Dictionary = {
	"default": {
		"display_name": "The Wilds",
		"terrain_color": Color(0.35, 0.55, 0.25),
		"path_color": Color(0.45, 0.38, 0.28),
		"water_tint": Color(0.2, 0.4, 0.7),
		"ambient_light": Color(0.9, 0.9, 0.85),
		"fog_color": Color(0.7, 0.75, 0.8),
		"common_table": "excursion_common",
		"rare_table": "excursion_rare",
	},
	"coastal_wreckage": {
		"display_name": "Coastal Wreckage",
		"terrain_color": Color(0.65, 0.58, 0.42),
		"path_color": Color(0.5, 0.45, 0.35),
		"water_tint": Color(0.15, 0.45, 0.55),
		"ambient_light": Color(0.95, 0.92, 0.85),
		"fog_color": Color(0.75, 0.8, 0.85),
		"common_table": "battered_bay",
		"rare_table": "excursion_coastal_rare",
	},
	"fungal_hollow": {
		"display_name": "Fungal Hollow",
		"terrain_color": Color(0.25, 0.22, 0.30),
		"path_color": Color(0.30, 0.25, 0.20),
		"water_tint": Color(0.3, 0.5, 0.25),
		"ambient_light": Color(0.6, 0.55, 0.7),
		"fog_color": Color(0.35, 0.3, 0.4),
		"common_table": "fermented_hollow",
		"rare_table": "excursion_fungal_rare",
	},
	"volcanic_crest": {
		"display_name": "Volcanic Crest",
		"terrain_color": Color(0.40, 0.28, 0.18),
		"path_color": Color(0.35, 0.25, 0.15),
		"water_tint": Color(0.8, 0.3, 0.1),
		"ambient_light": Color(1.0, 0.85, 0.7),
		"fog_color": Color(0.6, 0.4, 0.3),
		"common_table": "blackened_crest",
		"rare_table": "excursion_volcanic_rare",
	},
	"frozen_pantry": {
		"display_name": "Frozen Pantry",
		"terrain_color": Color(0.75, 0.8, 0.85),
		"path_color": Color(0.6, 0.55, 0.5),
		"water_tint": Color(0.5, 0.7, 0.9),
		"ambient_light": Color(0.8, 0.85, 0.95),
		"fog_color": Color(0.8, 0.85, 0.9),
		"common_table": "salted_shipwreck",
		"rare_table": "excursion_frozen_rare",
	},
}

# Per-zone poacher species pools
const ZONE_POACHER_SPECIES: Dictionary = {
	"default": [
		"steak_beast", "drumstick_warrior", "crab_knight", "lobster_lord",
		"iron_pot", "obsidian_chef", "dragon_wok", "coffee_golem",
		"potato_brute", "ferment_lord", "salt_crystal", "wasabi_viper",
	],
	"coastal_wreckage": [
		"shrimp_scout", "crab_knight", "lobster_lord", "squid_mystic",
		"jellyfish_drift", "oyster_sage", "coconut_crab", "vanilla_fairy",
	],
	"fungal_hollow": [
		"mushroom_monarch", "ferment_lord", "coffee_golem", "wasabi_viper",
		"hemlock_shade", "truffle_burrower", "cocoa_imp", "ginger_snap",
	],
	"volcanic_crest": [
		"dragon_wok", "obsidian_chef", "steak_beast", "drumstick_warrior",
		"salt_crystal", "turmeric_titan", "cinnamon_swirl", "saffron_spirit",
	],
	"frozen_pantry": [
		"crab_knight", "lobster_lord", "iron_pot", "cocoa_imp",
		"saffron_spirit", "kraken_broth", "coconut_crab", "oyster_sage",
	],
}

# Poacher data
const POACHER_NAMES: Array = [
	"Trap Setter Grim", "Net Caster Vex", "Cage Builder Rook",
	"Snare Master Dusk", "Lure Maker Shade", "Poacher Boss Fang",
]

const POACHER_DIALOGUES_BEFORE: Array = [
	"You're trespassing in MY hunting grounds! Prepare for a fight!",
	"Another fool trying to protect these creatures? I'll crush you!",
	"These Munchies are worth a fortune. Get out of my way!",
	"You think you can stop me? My traps are set and ready!",
	"Hah! A wannabe hero. Let me show you real strength!",
	"I've been poaching Munchies for years. You're no threat to me!",
]

const POACHER_DIALOGUES_AFTER: Array = [
	"Tch... You got lucky this time. I'll be back!",
	"Fine, take your precious creatures. There's always more hunting grounds.",
	"This isn't over... I know people who won't be so kind.",
	"Bah! My traps failed me. I need better equipment...",
	"You win today, but the wilds are vast. You can't protect them all.",
	"Impossible... beaten by some kid with tame Munchies...",
]

const POACHER_SPECIES_POOL: Array = [
	"steak_beast", "drumstick_warrior", "crab_knight", "lobster_lord",
	"iron_pot", "obsidian_chef", "dragon_wok", "coffee_golem",
	"potato_brute", "ferment_lord", "salt_crystal", "wasabi_viper",
]

const POACHER_REWARD_POOL: Array = [
	"mystic_herb", "starfruit", "truffle_shaving",
	"wild_honey", "golden_seed", "ancient_grain_seed",
]

# --- Toon Shader (lazy-loaded) ---

static var _toon_shader: Shader = null
static var _model_cache: Dictionary = {} # path -> PackedScene

static func _load_toon_shader() -> Shader:
	if _toon_shader == null:
		_toon_shader = load("res://shaders/world_toon.gdshader")
	return _toon_shader

static func _apply_toon_shader_static(node: Node) -> void:
	var shader := _load_toon_shader()
	if shader == null:
		return
	for child in node.get_children():
		if child is MeshInstance3D:
			for i in range(child.mesh.get_surface_count() if child.mesh else 0):
				var orig_mat = child.get_active_material(i)
				if orig_mat is StandardMaterial3D:
					var smat := ShaderMaterial.new()
					smat.shader = shader
					if orig_mat.albedo_texture:
						smat.set_shader_parameter("albedo_texture", orig_mat.albedo_texture)
						smat.set_shader_parameter("use_texture", true)
					else:
						smat.set_shader_parameter("use_texture", false)
					smat.set_shader_parameter("albedo_color", orig_mat.albedo_color)
					child.set_surface_override_material(i, smat)
		_apply_toon_shader_static(child)


static func _place_synty_static(parent: Node3D, asset_path: String, pos: Vector3, rot_y: float, scale_val: float) -> void:
	if not _model_cache.has(asset_path):
		var res = load(asset_path)
		if res == null:
			return
		_model_cache[asset_path] = res
	var scene: PackedScene = _model_cache[asset_path]
	var instance: Node3D = scene.instantiate()
	instance.position = pos
	instance.rotation.y = rot_y
	instance.scale = Vector3(scale_val, scale_val, scale_val)
	_apply_toon_shader_static(instance)
	parent.add_child(instance)


# --- Path Helpers ---

static func _is_on_path(x: float, z: float) -> float:
	## Returns 0.0 on path center, 1.0 fully off path.
	## Main north-south corridor from spawn (80,150) to center (80,80).
	## Plus east-west cross-path at z=80.
	var best: float = 1.0
	# N-S corridor
	if z >= 75.0 and z <= 155.0:
		var dx: float = absf(x - 80.0) / PATH_HALF_WIDTH
		best = minf(best, clampf(dx, 0.0, 1.0))
	# E-W cross-path at z=80 (from x=30 to x=130)
	if x >= 25.0 and x <= 135.0:
		var dz: float = absf(z - 80.0) / PATH_HALF_WIDTH
		best = minf(best, clampf(dz, 0.0, 1.0))
	return best


# --- Public API ---

static func generate_server(seed_val: int, season: String, offset: Vector3, zone_type: String = "default") -> Node3D:
	var root := Node3D.new()
	root.name = "ExcursionInstance"
	root.position = offset

	var height_noise := _make_height_noise(seed_val)
	var detail_noise := _make_detail_noise(seed_val)
	var heightmap := _build_heightmap(height_noise, detail_noise)

	# Terrain collision (players walk on this)
	var terrain_body := _build_terrain_collision(heightmap)
	root.add_child(terrain_body)

	# Boundary walls
	_add_boundary_walls(root)

	# Encounter zones (TallGrass-like Area3Ds) — use zone-specific tables
	var config: Dictionary = ZONE_CONFIGS.get(zone_type, ZONE_CONFIGS["default"])
	var biome_noise := _make_biome_noise(seed_val)
	var rare_noise := _make_rare_noise(seed_val)
	var zones := get_encounter_zones(seed_val, season, Vector3.ZERO, zone_type)
	for z_data in zones:
		var area := _create_encounter_area(z_data, height_noise, detail_noise)
		root.add_child(area)

	# Exit portal at spawn point
	var exit_portal := _create_exit_portal()
	root.add_child(exit_portal)

	return root


static func generate_client(seed_val: int, season: String, offset: Vector3, zone_type: String = "default") -> Node3D:
	var root := Node3D.new()
	root.name = "ExcursionVisuals"
	root.position = offset

	var config: Dictionary = ZONE_CONFIGS.get(zone_type, ZONE_CONFIGS["default"])

	var height_noise := _make_height_noise(seed_val)
	var detail_noise := _make_detail_noise(seed_val)
	var heightmap := _build_heightmap(height_noise, detail_noise)

	# Visual terrain mesh — zone-tinted
	var terrain_mesh := _build_terrain_mesh(heightmap, season, zone_type)
	root.add_child(terrain_mesh)

	# Terrain collision (client also needs physics for local prediction)
	var terrain_body := _build_terrain_collision(heightmap)
	root.add_child(terrain_body)

	# Boundary walls with cliff visuals
	_add_boundary_walls(root, true)

	# Biome props (Synty trees, rocks, flowers) — zone-specific models
	var biome_noise := _make_biome_noise(seed_val)
	var resource_noise := _make_resource_noise(seed_val)
	_generate_props(root, biome_noise, height_noise, detail_noise, resource_noise, season, seed_val, zone_type)

	# Path markers (torches + small rocks along spawn-to-center corridor)
	_generate_path_markers(root, height_noise, detail_noise)

	# Zone-specific decorations (extra props like barrels, ruins, etc.)
	_generate_zone_decorations(root, seed_val, zone_type, height_noise, detail_noise)

	# Zone overlays
	var zones := get_encounter_zones(seed_val, season, Vector3.ZERO, zone_type)
	_add_zone_overlays(root, zones, height_noise, detail_noise)

	# Rare zone glow with ruins — use zone-specific ruin models
	for z_data in zones:
		if z_data.get("is_rare", false):
			_add_rare_zone_glow(root, z_data, height_noise, detail_noise, zone_type)

	# Exit portal visual
	var exit_portal := _create_exit_portal_visual()
	root.add_child(exit_portal)

	# Ambient label — show zone display name
	var display_name: String = config.get("display_name", "Excursion Zone")
	var label := Label3D.new()
	UITheme.style_label3d(label, display_name, "zone_sign")
	label.font_size = 48
	label.position = Vector3(80, 12, 80)
	root.add_child(label)

	# Zone ambient lighting
	var ambient := DirectionalLight3D.new()
	ambient.light_color = config.get("ambient_light", Color(0.9, 0.9, 0.85))
	ambient.light_energy = 0.6
	ambient.rotation = Vector3(deg_to_rad(-45), deg_to_rad(30), 0)
	ambient.shadow_enabled = false
	root.add_child(ambient)

	# Zone fog
	var fog_env := WorldEnvironment.new()
	var env := Environment.new()
	env.fog_enabled = true
	env.fog_light_color = config.get("fog_color", Color(0.7, 0.75, 0.8))
	env.fog_density = 0.003
	fog_env.environment = env
	root.add_child(fog_env)

	return root


static func get_item_spawn_points(seed_val: int, season: String, _offset: Vector3) -> Array:
	var points: Array = []
	var resource_noise := _make_resource_noise(seed_val)
	var height_noise := _make_height_noise(seed_val)
	var detail_noise := _make_detail_noise(seed_val)

	# Scan grid for resource clusters
	var item_table := _get_excursion_item_table(season)
	var total_weight := 0
	for entry in item_table:
		total_weight += entry["weight"]

	# Use noise to place 30-50 items deterministically
	var item_seed := seed_val + 100
	var rng := RandomNumberGenerator.new()
	rng.seed = item_seed
	var num_items: int = rng.randi_range(30, 50)

	for i in range(num_items):
		# Spread items across the arena using golden angle
		var angle: float = i * 2.399
		var radius: float = rng.randf_range(10.0, 70.0)
		var cx: float = 80.0 + cos(angle) * radius
		var cz: float = 80.0 + sin(angle) * radius
		cx = clampf(cx, 4.0, 156.0)
		cz = clampf(cz, 4.0, 146.0) # Keep away from spawn edge

		var y: float = _height_at(height_noise, detail_noise, cx, cz) + 0.5

		# Pick item from weighted table
		var roll: int = rng.randi() % total_weight
		var cumulative := 0
		var chosen_id: String = item_table[0]["item_id"]
		for entry in item_table:
			cumulative += entry["weight"]
			if roll < cumulative:
				chosen_id = entry["item_id"]
				break

		points.append({
			"position": Vector3(cx, y, cz),
			"item_id": chosen_id,
			"amount": 1,
		})

	return points


static func get_encounter_zones(seed_val: int, season: String, _offset: Vector3, zone_type: String = "default") -> Array:
	var config: Dictionary = ZONE_CONFIGS.get(zone_type, ZONE_CONFIGS["default"])
	var common_table: String = config.get("common_table", "excursion_common")
	var rare_table: String = config.get("rare_table", "excursion_rare")

	var zones: Array = []
	var rare_noise := _make_rare_noise(seed_val)
	var height_noise := _make_height_noise(seed_val)
	var detail_noise := _make_detail_noise(seed_val)

	# Place 5-8 common encounter zones spread across 160x160
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 200
	var num_zones: int = rng.randi_range(5, 8)

	# Predefined zone placement anchors (spread across arena)
	var anchors: Array[Vector2] = [
		Vector2(30, 30), Vector2(80, 25), Vector2(130, 30),
		Vector2(25, 60), Vector2(135, 60), Vector2(40, 95),
		Vector2(120, 95), Vector2(80, 70),
	]

	for i in range(num_zones):
		var anchor: Vector2 = anchors[i]
		var jx: float = rng.randf_range(-5.0, 5.0)
		var jz: float = rng.randf_range(-5.0, 5.0)
		var zx: float = clampf(anchor.x + jx, 6.0, 154.0)
		var zz: float = clampf(anchor.y + jz, 6.0, 146.0)
		var zy: float = _height_at(height_noise, detail_noise, zx, zz)
		zones.append({
			"position": Vector3(zx, zy, zz),
			"radius": rng.randf_range(5.0, 8.0),
			"table_id": common_table,
			"is_rare": false,
		})

	# Place 1 rare grove zone at highest rare_noise peak
	var best_val: float = -999.0
	var best_pos := Vector2(80, 60)
	for gx in range(2, 38):
		for gz in range(2, 34):
			var wx: float = gx * 4.0 + 2.0
			var wz: float = gz * 4.0 + 2.0
			var n: float = rare_noise.get_noise_2d(wx, wz)
			if n > best_val:
				best_val = n
				best_pos = Vector2(wx, wz)
	var rare_y: float = _height_at(height_noise, detail_noise, best_pos.x, best_pos.y)
	zones.append({
		"position": Vector3(best_pos.x, rare_y, best_pos.y),
		"radius": 6.0,
		"table_id": rare_table,
		"is_rare": true,
	})

	return zones


static func get_harvestable_spawn_points(seed_val: int, season: String, _offset: Vector3) -> Array:
	## Returns array of {position: Vector3, type: String, drops: Array} for excursion harvestables.
	var points: Array = []
	var biome_noise := _make_biome_noise(seed_val)
	var resource_noise := _make_resource_noise(seed_val)
	var height_noise := _make_height_noise(seed_val)
	var detail_noise := _make_detail_noise(seed_val)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 300

	# Get encounter zone positions for 2-unit buffer
	var encounter_zones: Array = get_encounter_zones(seed_val, season, _offset)

	var cell_size: float = 4.0
	var grid_count: int = int(ARENA_SIZE / cell_size)

	for gz in range(grid_count):
		for gx in range(grid_count):
			var cx: float = gx * cell_size + cell_size / 2.0
			var cz: float = gz * cell_size + cell_size / 2.0

			# Skip spawn area
			if Vector2(cx, cz).distance_to(Vector2(80, 150)) < SPAWN_FLATTEN_RADIUS + 4.0:
				continue
			# Skip exit portal area
			if Vector2(cx, cz).distance_to(Vector2(80, 154)) < 5.0:
				continue
			# Skip path corridor
			if _is_on_path(cx, cz) < 0.5:
				continue
			# Skip 2-unit buffer around encounter zones
			var too_close_to_encounter := false
			for zone in encounter_zones:
				var zpos: Vector3 = zone["position"]
				var zradius: float = zone["radius"]
				if Vector2(cx, cz).distance_to(Vector2(zpos.x, zpos.z)) < zradius + 2.0:
					too_close_to_encounter = true
					break
			if too_close_to_encounter:
				continue

			var biome_val: float = biome_noise.get_noise_2d(cx, cz)
			var height_val: float = _height_at(height_noise, detail_noise, cx, cz)
			var density_val: float = resource_noise.get_noise_2d(cx, cz)
			var biome: Biome = _classify_biome(biome_val, height_val, season)

			# Only place harvestables in specific biomes at specific density thresholds
			var harvestable_type: String = ""
			var threshold: float = 0.0

			match biome:
				Biome.DENSE_FOREST:
					harvestable_type = "tree"
					threshold = 0.35
				Biome.ROCKY_OUTCROP:
					harvestable_type = "rock"
					threshold = 0.25
				Biome.GRASSLAND:
					harvestable_type = "bush"
					threshold = 0.5
				Biome.FLOWER_FIELD:
					harvestable_type = "bush"
					threshold = 0.55
				_:
					continue

			if density_val < threshold:
				continue

			# Bias towards path — items within 8 units of path get higher spawn chance
			var path_proximity: float = _is_on_path(cx, cz)
			var spawn_chance: float = 0.25
			if path_proximity < 0.8: # Near path edge
				spawn_chance = 0.45

			# Additional RNG thinning to hit target of ~16-24 per instance
			if rng.randf() > spawn_chance:
				continue

			var y: float = _height_at(height_noise, detail_noise, cx, cz)
			var drop_list: Array = _get_harvestable_drops(harvestable_type, season)

			points.append({
				"position": Vector3(cx, y, cz),
				"type": harvestable_type,
				"drops": drop_list,
			})

	return points


static func get_dig_spot_points(seed_val: int, _season: String, _offset: Vector3) -> Array:
	## Returns array of {position: Vector3, spot_id: String, loot_table: Array} for excursion dig spots.
	var points: Array = []
	var height_noise := _make_height_noise(seed_val)
	var detail_noise := _make_detail_noise(seed_val)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 400
	var num_spots: int = rng.randi_range(5, 8)

	# Find low-height candidate positions across the arena
	var candidates: Array = [] # {position, height}
	var cell_size: float = 8.0
	var grid_count: int = int(ARENA_SIZE / cell_size)

	for gz in range(grid_count):
		for gx in range(grid_count):
			var cx: float = gx * cell_size + cell_size / 2.0
			var cz: float = gz * cell_size + cell_size / 2.0
			# Skip spawn/exit area
			if Vector2(cx, cz).distance_to(Vector2(80, 150)) < SPAWN_FLATTEN_RADIUS + 4.0:
				continue
			var h: float = _height_at(height_noise, detail_noise, cx, cz)
			if h < 3.0: # Valley/low areas (scaled for new height range)
				candidates.append({"x": cx, "z": cz, "h": h})

	# Sort by height ascending, pick lowest spots with spacing
	candidates.sort_custom(func(a, b): return a["h"] < b["h"])

	var min_spacing: float = 10.0
	for c in candidates:
		if points.size() >= num_spots:
			break
		var too_close := false
		for existing in points:
			if Vector2(c["x"], c["z"]).distance_to(Vector2(existing["position"].x, existing["position"].z)) < min_spacing:
				too_close = true
				break
		if too_close:
			continue

		var spot_index: int = points.size()
		points.append({
			"position": Vector3(c["x"], c["h"], c["z"]),
			"spot_id": "excursion_%d_%d" % [seed_val, spot_index],
			"loot_table": _get_dig_spot_loot_table(),
		})

	return points


static func get_poacher_spawn_points(seed_val: int, season: String, _offset: Vector3, zone_type: String = "default") -> Array:
	## Returns array of poacher data dicts for excursion instances.
	## Deterministic from seed — both server and client get identical results.
	var points: Array = []
	var height_noise := _make_height_noise(seed_val)
	var detail_noise := _make_detail_noise(seed_val)
	var species_pool: Array = ZONE_POACHER_SPECIES.get(zone_type, ZONE_POACHER_SPECIES["default"])

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 500
	var num_poachers: int = rng.randi_range(3, 5)

	var spawn_center := Vector2(80, 150)
	var arena_center := Vector2(80, 80)

	for i in range(num_poachers):
		# Golden angle spiral from arena center
		var angle: float = i * 2.399 + rng.randf_range(0.0, 0.5)
		var radius: float = rng.randf_range(25.0, 65.0)
		var px: float = arena_center.x + cos(angle) * radius
		var pz: float = arena_center.y + sin(angle) * radius
		px = clampf(px, 10.0, 150.0)
		pz = clampf(pz, 10.0, 140.0)

		# No poachers within 20 units of spawn
		if Vector2(px, pz).distance_to(spawn_center) < 20.0:
			continue

		# Min 15-unit spacing between poachers
		var too_close := false
		for existing in points:
			if Vector2(px, pz).distance_to(Vector2(existing["position"].x, existing["position"].z)) < 15.0:
				too_close = true
				break
		if too_close:
			continue

		var py: float = _height_at(height_noise, detail_noise, px, pz)

		# Difficulty tier by distance from spawn
		var dist_to_spawn: float = Vector2(px, pz).distance_to(spawn_center)
		var difficulty: String = "easy"
		var party_size: int = 1
		var level_min: int = 8
		var level_max: int = 14
		var reward_money: int = 200

		if dist_to_spawn > 70.0:
			difficulty = "hard"
			party_size = 3
			level_min = 20
			level_max = 30
			reward_money = 700
		elif dist_to_spawn > 40.0:
			difficulty = "medium"
			party_size = 2
			level_min = 14
			level_max = 22
			reward_money = 400

		# Build party from species pool
		var party: Array[Dictionary] = []
		for p in range(party_size):
			var sp_idx: int = rng.randi() % species_pool.size()
			var level: int = rng.randi_range(level_min, level_max)
			party.append({"species_id": species_pool[sp_idx], "level": level})

		# Pick name and dialogues
		var name_idx: int = i % POACHER_NAMES.size()
		var dialogue_idx: int = rng.randi() % POACHER_DIALOGUES_BEFORE.size()

		# Reward ingredients (1-2 random from pool)
		var reward_ingredients: Dictionary = {}
		var num_rewards: int = rng.randi_range(1, 2)
		for _r in range(num_rewards):
			var r_idx: int = rng.randi() % POACHER_REWARD_POOL.size()
			var r_id: String = POACHER_REWARD_POOL[r_idx]
			reward_ingredients[r_id] = reward_ingredients.get(r_id, 0) + 1

		var trainer_id: String = "poacher_%d_%d" % [seed_val, i]

		points.append({
			"position": Vector3(px, py, pz),
			"trainer_id": trainer_id,
			"display_name": POACHER_NAMES[name_idx],
			"dialogue_before": POACHER_DIALOGUES_BEFORE[dialogue_idx],
			"dialogue_after": POACHER_DIALOGUES_AFTER[dialogue_idx],
			"party": party,
			"ai_difficulty": difficulty,
			"reward_money": reward_money,
			"reward_ingredients": reward_ingredients,
		})

	return points


static func _get_harvestable_drops(harvestable_type: String, _season: String) -> Array:
	## Returns drop table for excursion harvestables (richer than overworld).
	match harvestable_type:
		"tree":
			return [
				{"item_id": "wood", "min": 1, "max": 3, "weight": 1.0},
				{"item_id": "herb_basil", "min": 1, "max": 1, "weight": 0.3},
				{"item_id": "mystic_herb", "min": 1, "max": 1, "weight": 0.1},
			]
		"rock":
			return [
				{"item_id": "stone", "min": 1, "max": 2, "weight": 1.0},
				{"item_id": "chili_powder", "min": 1, "max": 1, "weight": 0.15},
				{"item_id": "sugar", "min": 1, "max": 1, "weight": 0.1},
			]
		"bush":
			return [
				{"item_id": "berry", "min": 1, "max": 2, "weight": 1.0},
				{"item_id": "wild_honey", "min": 1, "max": 1, "weight": 0.2},
			]
	return []


static func _get_dig_spot_loot_table() -> Array:
	## Returns loot table for excursion dig spots (rare excursion ingredients).
	return [
		{"item_id": "golden_seed", "min": 1, "max": 1, "weight": 0.2},
		{"item_id": "ancient_grain_seed", "min": 1, "max": 1, "weight": 0.15},
		{"item_id": "starfruit", "min": 1, "max": 1, "weight": 0.15},
		{"item_id": "truffle_shaving", "min": 1, "max": 2, "weight": 0.25},
		{"item_id": "mystic_herb", "min": 1, "max": 1, "weight": 0.2},
		{"item_id": "stone", "min": 1, "max": 3, "weight": 0.5},
		{"item_id": "wild_honey", "min": 1, "max": 1, "weight": 0.3},
	]


static func get_spawn_point(_offset: Vector3) -> Vector3:
	# South edge, flattened area
	return Vector3(80, 1, 150)


# --- Noise Generators (deterministic from seed) ---

static func _make_height_noise(seed_val: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_val + 1
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	return noise


static func _make_detail_noise(seed_val: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_val + 2
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.08
	noise.fractal_octaves = 2
	return noise


static func _make_biome_noise(seed_val: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.04
	noise.fractal_octaves = 2
	return noise


static func _make_resource_noise(seed_val: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_val + 3
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.05
	return noise


static func _make_rare_noise(seed_val: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_val + 4
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.03
	return noise


# --- Heightmap ---

static func _build_heightmap(height_noise: FastNoiseLite, detail_noise: FastNoiseLite) -> PackedFloat32Array:
	var verts_per_axis: int = GRID_RESOLUTION + 1 # 161
	var heightmap := PackedFloat32Array()
	heightmap.resize(verts_per_axis * verts_per_axis)

	var spawn_center := Vector2(80, 150) # spawn area south edge

	for z_idx in range(verts_per_axis):
		for x_idx in range(verts_per_axis):
			var wx: float = x_idx * (ARENA_SIZE / GRID_RESOLUTION)
			var wz: float = z_idx * (ARENA_SIZE / GRID_RESOLUTION)

			var h: float = height_noise.get_noise_2d(wx, wz) # [-1, 1]
			h = (h + 1.0) * 0.5 * HEIGHT_RANGE # [0, HEIGHT_RANGE]

			# Add micro-detail
			var detail: float = detail_noise.get_noise_2d(wx, wz) * 0.5
			h += detail

			# Flatten spawn area
			var dist_to_spawn: float = Vector2(wx, wz).distance_to(spawn_center)
			if dist_to_spawn < SPAWN_FLATTEN_RADIUS:
				var blend: float = dist_to_spawn / SPAWN_FLATTEN_RADIUS
				blend = blend * blend # ease in
				h = lerpf(0.0, h, blend)

			# Flatten path corridor to gentle slope
			var path_val: float = _is_on_path(wx, wz)
			if path_val < 1.0:
				var path_h: float = clampf(h, 1.0, 2.0)
				h = lerpf(path_h, h, path_val)

			h = clampf(h, 0.0, HEIGHT_RANGE)
			heightmap[z_idx * verts_per_axis + x_idx] = h

	return heightmap


static func _height_at(height_noise: FastNoiseLite, detail_noise: FastNoiseLite, x: float, z: float) -> float:
	var h: float = height_noise.get_noise_2d(x, z)
	h = (h + 1.0) * 0.5 * HEIGHT_RANGE
	h += detail_noise.get_noise_2d(x, z) * 0.5

	# Flatten spawn area
	var dist_to_spawn: float = Vector2(x, z).distance_to(Vector2(80, 150))
	if dist_to_spawn < SPAWN_FLATTEN_RADIUS:
		var blend: float = dist_to_spawn / SPAWN_FLATTEN_RADIUS
		blend = blend * blend
		h = lerpf(0.0, h, blend)

	# Flatten path corridor
	var path_val: float = _is_on_path(x, z)
	if path_val < 1.0:
		var path_h: float = clampf(h, 1.0, 2.0)
		h = lerpf(path_h, h, path_val)

	return clampf(h, 0.0, HEIGHT_RANGE)


# --- Terrain Construction ---

static func _build_terrain_collision(heightmap: PackedFloat32Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"

	var verts_per_axis: int = GRID_RESOLUTION + 1
	var cell_size: float = ARENA_SIZE / GRID_RESOLUTION

	# Build triangle mesh for ConcavePolygonShape3D
	var faces := PackedVector3Array()

	for z_idx in range(GRID_RESOLUTION):
		for x_idx in range(GRID_RESOLUTION):
			var i00: int = z_idx * verts_per_axis + x_idx
			var i10: int = z_idx * verts_per_axis + (x_idx + 1)
			var i01: int = (z_idx + 1) * verts_per_axis + x_idx
			var i11: int = (z_idx + 1) * verts_per_axis + (x_idx + 1)

			var v00 := Vector3(x_idx * cell_size, heightmap[i00], z_idx * cell_size)
			var v10 := Vector3((x_idx + 1) * cell_size, heightmap[i10], z_idx * cell_size)
			var v01 := Vector3(x_idx * cell_size, heightmap[i01], (z_idx + 1) * cell_size)
			var v11 := Vector3((x_idx + 1) * cell_size, heightmap[i11], (z_idx + 1) * cell_size)

			# Triangle 1
			faces.append(v00)
			faces.append(v10)
			faces.append(v01)
			# Triangle 2
			faces.append(v10)
			faces.append(v11)
			faces.append(v01)

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var coll := CollisionShape3D.new()
	coll.shape = shape
	body.add_child(coll)

	return body


static func _build_terrain_mesh(heightmap: PackedFloat32Array, season: String, zone_type: String = "default") -> MeshInstance3D:
	var verts_per_axis: int = GRID_RESOLUTION + 1
	var cell_size: float = ARENA_SIZE / GRID_RESOLUTION
	var config: Dictionary = ZONE_CONFIGS.get(zone_type, ZONE_CONFIGS["default"])

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Zone-tinted ground color (zone overrides season for non-default zones)
	var base_color: Color
	if zone_type != "default":
		base_color = config.get("terrain_color", Color(0.35, 0.55, 0.25))
	else:
		match season:
			"spring":
				base_color = Color(0.3, 0.55, 0.2)
			"summer":
				base_color = Color(0.35, 0.5, 0.15)
			"autumn":
				base_color = Color(0.5, 0.4, 0.2)
			"winter":
				base_color = Color(0.6, 0.65, 0.7)
			_:
				base_color = Color(0.3, 0.5, 0.2)

	var zone_path_color: Color = config.get("path_color", Color(0.55, 0.5, 0.4))
	var zone_water_tint: Color = config.get("water_tint", Color(0.25, 0.35, 0.5))

	for z_idx in range(GRID_RESOLUTION):
		for x_idx in range(GRID_RESOLUTION):
			var i00: int = z_idx * verts_per_axis + x_idx
			var i10: int = z_idx * verts_per_axis + (x_idx + 1)
			var i01: int = (z_idx + 1) * verts_per_axis + x_idx
			var i11: int = (z_idx + 1) * verts_per_axis + (x_idx + 1)

			var v00 := Vector3(x_idx * cell_size, heightmap[i00], z_idx * cell_size)
			var v10 := Vector3((x_idx + 1) * cell_size, heightmap[i10], z_idx * cell_size)
			var v01 := Vector3(x_idx * cell_size, heightmap[i01], (z_idx + 1) * cell_size)
			var v11 := Vector3((x_idx + 1) * cell_size, heightmap[i11], (z_idx + 1) * cell_size)

			# Color varies by height
			var h_avg: float = (heightmap[i00] + heightmap[i10] + heightmap[i01] + heightmap[i11]) * 0.25
			var height_blend: float = h_avg / HEIGHT_RANGE
			var low_color: Color = base_color
			var high_color: Color = base_color.lerp(Color(0.5, 0.45, 0.35), 0.6)
			if h_avg < 1.0:
				# Water edge — zone-tinted
				low_color = zone_water_tint
			# Path tint — slightly lighter for walkable path
			var wx: float = (x_idx + 0.5) * cell_size
			var wz: float = (z_idx + 0.5) * cell_size
			var pv: float = _is_on_path(wx, wz)
			if pv < 0.8:
				low_color = low_color.lerp(zone_path_color, (1.0 - pv) * 0.4)
				high_color = low_color
			var vert_color: Color = low_color.lerp(high_color, height_blend)

			# Triangle 1
			var n1: Vector3 = (v10 - v00).cross(v01 - v00).normalized()
			st.set_color(vert_color)
			st.set_normal(n1)
			st.add_vertex(v00)
			st.set_color(vert_color)
			st.set_normal(n1)
			st.add_vertex(v10)
			st.set_color(vert_color)
			st.set_normal(n1)
			st.add_vertex(v01)

			# Triangle 2
			var n2: Vector3 = (v11 - v10).cross(v01 - v10).normalized()
			st.set_color(vert_color)
			st.set_normal(n2)
			st.add_vertex(v10)
			st.set_color(vert_color)
			st.set_normal(n2)
			st.add_vertex(v11)
			st.set_color(vert_color)
			st.set_normal(n2)
			st.add_vertex(v01)

	var mesh := st.commit()
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "TerrainMesh"
	mesh_inst.mesh = mesh

	# Material with vertex colors
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mesh_inst.set_surface_override_material(0, mat)

	return mesh_inst


# --- Boundary Walls ---

static func _add_boundary_walls(parent: Node3D, with_visuals: bool = false) -> void:
	var wall_height: float = 10.0
	var wall_thickness: float = 1.0

	var walls := [
		# North wall
		{"pos": Vector3(ARENA_SIZE / 2.0, wall_height / 2.0, -wall_thickness / 2.0),
			"size": Vector3(ARENA_SIZE + wall_thickness * 2, wall_height, wall_thickness)},
		# South wall
		{"pos": Vector3(ARENA_SIZE / 2.0, wall_height / 2.0, ARENA_SIZE + wall_thickness / 2.0),
			"size": Vector3(ARENA_SIZE + wall_thickness * 2, wall_height, wall_thickness)},
		# West wall
		{"pos": Vector3(-wall_thickness / 2.0, wall_height / 2.0, ARENA_SIZE / 2.0),
			"size": Vector3(wall_thickness, wall_height, ARENA_SIZE)},
		# East wall
		{"pos": Vector3(ARENA_SIZE + wall_thickness / 2.0, wall_height / 2.0, ARENA_SIZE / 2.0),
			"size": Vector3(wall_thickness, wall_height, ARENA_SIZE)},
	]

	for w in walls:
		var body := StaticBody3D.new()
		body.position = w["pos"]
		var shape := BoxShape3D.new()
		shape.size = w["size"]
		var coll := CollisionShape3D.new()
		coll.shape = shape
		body.add_child(coll)
		parent.add_child(body)

	if with_visuals:
		_add_cliff_boundary_visuals(parent)


static func _add_cliff_boundary_visuals(parent: Node3D) -> void:
	var cliff_spacing: float = 8.0
	var cliff_count: int = int(ARENA_SIZE / cliff_spacing)

	# North wall cliffs
	for i in range(cliff_count):
		var cx: float = i * cliff_spacing + cliff_spacing / 2.0
		var model_path: String = CLIFF_MODELS[i % CLIFF_MODELS.size()]
		_place_synty_static(parent, model_path, Vector3(cx, 0, -1.0), PI, 2.5)

	# West wall cliffs
	for i in range(cliff_count):
		var cz: float = i * cliff_spacing + cliff_spacing / 2.0
		var model_path: String = CLIFF_MODELS[i % CLIFF_MODELS.size()]
		_place_synty_static(parent, model_path, Vector3(-1.0, 0, cz), PI * 0.5, 2.5)

	# East wall cliffs
	for i in range(cliff_count):
		var cz: float = i * cliff_spacing + cliff_spacing / 2.0
		var model_path: String = CLIFF_MODELS[(i + 2) % CLIFF_MODELS.size()]
		_place_synty_static(parent, model_path, Vector3(ARENA_SIZE + 1.0, 0, cz), -PI * 0.5, 2.5)

	# South wall cliffs — leave gap at center (x=70-90) for spawn area
	for i in range(cliff_count):
		var cx: float = i * cliff_spacing + cliff_spacing / 2.0
		if cx > 68.0 and cx < 92.0:
			continue # gap for spawn/exit
		var model_path: String = CLIFF_MODELS[(i + 1) % CLIFF_MODELS.size()]
		_place_synty_static(parent, model_path, Vector3(cx, 0, ARENA_SIZE + 1.0), 0.0, 2.5)

	# Corner boulders
	_place_synty_static(parent, BOULDER_MODEL, Vector3(2, 0, 2), 0.0, 3.0)
	_place_synty_static(parent, BOULDER_MODEL, Vector3(ARENA_SIZE - 2, 0, 2), PI * 0.5, 3.0)
	_place_synty_static(parent, BOULDER_MODEL, Vector3(2, 0, ARENA_SIZE - 2), -PI * 0.5, 3.0)
	_place_synty_static(parent, BOULDER_MODEL, Vector3(ARENA_SIZE - 2, 0, ARENA_SIZE - 2), PI, 3.0)


# --- Encounter Areas ---

static func _create_encounter_area(zone_data: Dictionary, _height_noise: FastNoiseLite, _detail_noise: FastNoiseLite) -> Area3D:
	var area := Area3D.new()
	var pos: Vector3 = zone_data["position"]
	var radius: float = zone_data.get("radius", 6.0)
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = 3 # Detect players on layer 2

	# Use cylinder shape for encounter zone
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 4.0
	var coll := CollisionShape3D.new()
	coll.shape = shape
	coll.position = Vector3(0, 2, 0) # Raise so bottom is at terrain level
	area.add_child(coll)

	# Attach script data via metadata
	area.set_meta("encounter_table_id", zone_data.get("table_id", "excursion_common"))
	area.set_meta("is_excursion_encounter", true)
	area.set_meta("is_rare", zone_data.get("is_rare", false))

	if zone_data.get("is_rare", false):
		area.name = "ExcursionRareZone"
	else:
		area.name = "ExcursionZone_" + str(randi() % 10000)

	return area


# --- Props (Client Only) ---

static func _generate_props(parent: Node3D, biome_noise: FastNoiseLite, height_noise: FastNoiseLite, detail_noise: FastNoiseLite, resource_noise: FastNoiseLite, season: String, seed_val: int, zone_type: String = "default") -> void:
	var props_node := Node3D.new()
	props_node.name = "Props"
	parent.add_child(props_node)

	# Seeded RNG for deterministic rotation/scale
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 600

	# Zone-specific model selection
	var zone_tree_dict: Dictionary
	var zone_rock_list: Array
	var zone_flower_list: Array
	match zone_type:
		"coastal_wreckage":
			zone_tree_dict = COASTAL_TREE_MODELS
			zone_rock_list = COASTAL_ROCK_MODELS
			zone_flower_list = COASTAL_FLORA
		"fungal_hollow":
			zone_tree_dict = FUNGAL_TREE_MODELS
			zone_rock_list = FUNGAL_ROCK_MODELS
			zone_flower_list = FUNGAL_FLORA
		"volcanic_crest":
			zone_tree_dict = VOLCANIC_TREE_MODELS
			zone_rock_list = VOLCANIC_ROCK_MODELS
			zone_flower_list = []
		"frozen_pantry":
			zone_tree_dict = FROZEN_TREE_MODELS
			zone_rock_list = FROZEN_ROCK_MODELS
			zone_flower_list = FROZEN_FLORA
		_:
			zone_tree_dict = TREE_MODELS
			zone_rock_list = ROCK_MODELS
			zone_flower_list = FLOWER_MODELS

	var tree_models: Array = zone_tree_dict.get(season, zone_tree_dict.get("spring", []))
	var skip_flowers: bool = (season == "winter") or zone_flower_list.is_empty()

	# Step through grid cells (4x4 unit cells)
	var cell_size: float = 4.0
	var grid_count: int = int(ARENA_SIZE / cell_size)

	for gz in range(grid_count):
		for gx in range(grid_count):
			var cx: float = gx * cell_size + cell_size / 2.0
			var cz: float = gz * cell_size + cell_size / 2.0

			# Skip spawn area
			if Vector2(cx, cz).distance_to(Vector2(80, 150)) < SPAWN_FLATTEN_RADIUS + 2.0:
				continue

			# Skip path corridor
			if _is_on_path(cx, cz) < 0.5:
				continue

			var biome_val: float = biome_noise.get_noise_2d(cx, cz) # [-1, 1]
			var height_val: float = _height_at(height_noise, detail_noise, cx, cz)
			var density_val: float = resource_noise.get_noise_2d(cx, cz)

			var biome: Biome = _classify_biome(biome_val, height_val, season)

			# Skip low-density cells
			if density_val < -0.3:
				continue

			match biome:
				Biome.DENSE_FOREST:
					if density_val > -0.1:
						_add_tree(props_node, cx, cz, height_val, tree_models, gx, gz, rng)
					if density_val > 0.2:
						_add_tree(props_node, cx + 1.5, cz + 1.0, _height_at(height_noise, detail_noise, cx + 1.5, cz + 1.0), tree_models, gx + 100, gz, rng)
				Biome.ROCKY_OUTCROP:
					_add_rock(props_node, cx, cz, height_val, gx, gz, rng, zone_rock_list)
				Biome.FLOWER_FIELD:
					if not skip_flowers:
						_add_flowers(props_node, cx, cz, height_val, gx, gz, rng, zone_flower_list)
				Biome.WATER_EDGE:
					_add_water_patch(props_node, cx, cz, height_val)
				Biome.GRASSLAND:
					if density_val > 0.3:
						_add_tree(props_node, cx, cz, height_val, tree_models, gx, gz, rng)


static func _classify_biome(biome_val: float, height_val: float, season: String) -> Biome:
	if height_val < 1.0:
		return Biome.WATER_EDGE
	if height_val > 5.5:
		return Biome.ROCKY_OUTCROP

	# Season-adjusted thresholds
	var forest_thresh: float = -0.1
	var flower_thresh: float = 0.3
	match season:
		"spring":
			flower_thresh = 0.15 # more flowers
		"winter":
			forest_thresh = -0.3 # fewer forests
			flower_thresh = 0.5  # fewer flowers

	if biome_val < forest_thresh:
		return Biome.DENSE_FOREST
	elif biome_val > flower_thresh:
		return Biome.FLOWER_FIELD
	else:
		return Biome.GRASSLAND


static func _add_tree(parent: Node3D, x: float, z: float, h: float, models: Array, gx: int, gz: int, rng: RandomNumberGenerator) -> void:
	var model_idx: int = (gx + gz) % models.size()
	var rot_y: float = rng.randf_range(0.0, TAU)
	var scale_val: float = rng.randf_range(0.8, 1.4)
	_place_synty_static(parent, models[model_idx], Vector3(x, h, z), rot_y, scale_val)


static func _add_rock(parent: Node3D, x: float, z: float, h: float, gx: int, gz: int, rng: RandomNumberGenerator, rock_list: Array = ROCK_MODELS) -> void:
	if rock_list.is_empty():
		return
	var model_idx: int = (gx + gz) % rock_list.size()
	var rot_y: float = rng.randf_range(0.0, TAU)
	var scale_val: float = rng.randf_range(0.6, 1.2)
	_place_synty_static(parent, rock_list[model_idx], Vector3(x, h, z), rot_y, scale_val)


static func _add_flowers(parent: Node3D, x: float, z: float, h: float, gx: int, gz: int, rng: RandomNumberGenerator, flower_list: Array = FLOWER_MODELS) -> void:
	if flower_list.is_empty():
		return
	var model_idx: int = (gx + gz) % flower_list.size()
	var rot_y: float = rng.randf_range(0.0, TAU)
	var scale_val: float = rng.randf_range(0.5, 1.0)
	_place_synty_static(parent, flower_list[model_idx], Vector3(x, h, z), rot_y, scale_val)


static func _add_water_patch(parent: Node3D, x: float, z: float, h: float) -> void:
	var water := MeshInstance3D.new()
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2(3.0, 3.0)
	water.mesh = water_mesh
	var shader_res = load("res://shaders/water.gdshader")
	if shader_res:
		var smat := ShaderMaterial.new()
		smat.shader = shader_res
		water.set_surface_override_material(0, smat)
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.35, 0.6, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.metallic = 0.3
		mat.roughness = 0.2
		water.set_surface_override_material(0, mat)
	water.position = Vector3(x, h + 0.02, z)
	parent.add_child(water)


# --- Path Markers (Client) ---

static func _generate_path_markers(parent: Node3D, height_noise: FastNoiseLite, detail_noise: FastNoiseLite) -> void:
	# Place torches on left side and small rocks on right side every 8 units along path
	var marker_spacing: float = 8.0
	var z_start: float = 145.0
	var z_end: float = 80.0
	var path_x: float = 80.0

	var z_pos: float = z_start
	var marker_idx: int = 0
	while z_pos > z_end:
		var h: float = _height_at(height_noise, detail_noise, path_x, z_pos)

		# Torch on left side
		_place_synty_static(parent, TORCH_MODEL,
			Vector3(path_x - PATH_HALF_WIDTH - 1.0, h, z_pos),
			0.0, 1.2)

		# Small rocks on right side
		var rock_model: String = SMALL_ROCK_MODELS[marker_idx % SMALL_ROCK_MODELS.size()]
		_place_synty_static(parent, rock_model,
			Vector3(path_x + PATH_HALF_WIDTH + 1.0, h, z_pos),
			float(marker_idx) * 1.3, 0.8)

		z_pos -= marker_spacing
		marker_idx += 1


# --- Zone Overlays (Client) ---

static func _add_zone_overlays(parent: Node3D, zones: Array, _height_noise: FastNoiseLite, _detail_noise: FastNoiseLite) -> void:
	for z_data in zones:
		var pos: Vector3 = z_data["position"]
		var radius: float = z_data.get("radius", 6.0)

		var overlay := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(radius * 2, 0.02, radius * 2)
		overlay.mesh = box
		var mat := StandardMaterial3D.new()
		if z_data.get("is_rare", false):
			mat.albedo_color = Color(0.6, 0.4, 0.8, 0.25)
		else:
			mat.albedo_color = Color(0.2, 0.5, 0.2, 0.2)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		overlay.set_surface_override_material(0, mat)
		overlay.position = Vector3(pos.x, pos.y + 0.01, pos.z)
		parent.add_child(overlay)


static func _add_rare_zone_glow(parent: Node3D, zone_data: Dictionary, _height_noise: FastNoiseLite, _detail_noise: FastNoiseLite, zone_type: String = "default") -> void:
	var pos: Vector3 = zone_data["position"]
	var radius: float = zone_data.get("radius", 6.0)

	# Zone-specific ruin models for rare grove columns
	var ruin_models: Array
	match zone_type:
		"fungal_hollow":
			ruin_models = DUNGEON_RUIN_MODELS
		_:
			ruin_models = RUIN_COLUMN_MODELS

	# Ring of 4 ruin columns around perimeter
	for i in range(4):
		var angle: float = i * (TAU / 4.0) + PI / 4.0
		var col_x: float = pos.x + cos(angle) * (radius - 1.0)
		var col_z: float = pos.z + sin(angle) * (radius - 1.0)
		var col_model: String = ruin_models[i % ruin_models.size()]
		_place_synty_static(parent, col_model, Vector3(col_x, pos.y, col_z), angle + PI, 1.5)

	# Central monolith
	_place_synty_static(parent, MONOLITH_MODELS[0], Vector3(pos.x, pos.y, pos.z), 0.0, 1.8)

	# Archway entrance (south side of grove)
	_place_synty_static(parent, RUIN_ARCHWAY_MODELS[0],
		Vector3(pos.x, pos.y, pos.z + radius - 0.5), 0.0, 1.5)

	# OmniLight3D glow
	var light := OmniLight3D.new()
	light.light_color = Color(0.7, 0.5, 0.9)
	light.light_energy = 2.0
	light.omni_range = 8.0
	light.position = Vector3(pos.x, pos.y + 3.0, pos.z)
	parent.add_child(light)

	# Label
	var label := Label3D.new()
	UITheme.style_label3d(label, "Rare Grove", "landmark")
	label.font_size = 32
	label.outline_size = 6
	label.position = Vector3(pos.x, pos.y + 5.0, pos.z)
	parent.add_child(label)


# --- Zone Decorations (Client) ---

static func _generate_zone_decorations(parent: Node3D, seed_val: int, zone_type: String, height_noise: FastNoiseLite, detail_noise: FastNoiseLite) -> void:
	## Scatter zone-specific extra props (barrels, ruins, dungeon pieces, etc.)
	var extra_props: Array
	match zone_type:
		"coastal_wreckage":
			extra_props = PIRATE_PROPS
		"fungal_hollow":
			extra_props = DUNGEON_PROPS
		"volcanic_crest":
			extra_props = WESTERN_PROPS
		"frozen_pantry":
			extra_props = KNIGHT_PROPS
		_:
			return # Default zone has no extra decorations

	if extra_props.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 700
	var num_decorations: int = rng.randi_range(12, 20)
	var spawn_center := Vector2(80, 150)

	for i in range(num_decorations):
		var angle: float = i * 2.399 + rng.randf_range(0.0, 1.0)
		var radius: float = rng.randf_range(15.0, 70.0)
		var dx: float = 80.0 + cos(angle) * radius
		var dz: float = 80.0 + sin(angle) * radius
		dx = clampf(dx, 6.0, 154.0)
		dz = clampf(dz, 6.0, 146.0)

		# Skip spawn area
		if Vector2(dx, dz).distance_to(spawn_center) < SPAWN_FLATTEN_RADIUS + 4.0:
			continue
		# Skip path corridor
		if _is_on_path(dx, dz) < 0.5:
			continue

		var dy: float = _height_at(height_noise, detail_noise, dx, dz)
		var prop_idx: int = rng.randi() % extra_props.size()
		var rot_y: float = rng.randf_range(0.0, TAU)
		var scale_val: float = rng.randf_range(0.8, 1.4)
		_place_synty_static(parent, extra_props[prop_idx], Vector3(dx, dy, dz), rot_y, scale_val)


# --- Exit Portal ---

static func _create_exit_portal() -> Area3D:
	var area := Area3D.new()
	area.name = "ExcursionExitPortal"
	area.position = Vector3(80, 0, 154) # Just past spawn point at south edge
	area.collision_layer = 0
	area.collision_mask = 3

	var shape := CylinderShape3D.new()
	shape.radius = 3.0
	shape.height = 4.0
	var coll := CollisionShape3D.new()
	coll.shape = shape
	coll.position = Vector3(0, 2, 0)
	area.add_child(coll)

	area.set_meta("is_excursion_exit", true)
	return area


static func _create_exit_portal_visual() -> Node3D:
	var portal := Node3D.new()
	portal.name = "ExitPortalVisual"
	portal.position = Vector3(80, 0, 154)

	var portal_color := Color(0.3, 0.6, 1.0)

	# Archway pillars
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = portal_color.darkened(0.3)
	pillar_mat.emission_enabled = true
	pillar_mat.emission = portal_color
	pillar_mat.emission_energy_multiplier = 0.5

	var pillar_mesh := BoxMesh.new()
	pillar_mesh.size = Vector3(0.6, 5, 0.6)

	var left := MeshInstance3D.new()
	left.mesh = pillar_mesh
	left.set_surface_override_material(0, pillar_mat)
	left.position = Vector3(-2.5, 2.5, 0)
	portal.add_child(left)

	var right := MeshInstance3D.new()
	right.mesh = pillar_mesh
	right.set_surface_override_material(0, pillar_mat)
	right.position = Vector3(2.5, 2.5, 0)
	portal.add_child(right)

	var lintel_mesh := BoxMesh.new()
	lintel_mesh.size = Vector3(6, 0.8, 0.6)
	var lintel := MeshInstance3D.new()
	lintel.mesh = lintel_mesh
	lintel.set_surface_override_material(0, pillar_mat)
	lintel.position = Vector3(0, 5.4, 0)
	portal.add_child(lintel)

	# Glowing ground disc
	var ring := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 3.0
	disc.bottom_radius = 3.0
	disc.height = 0.1
	ring.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.7, 1.0, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = portal_color
	mat.emission_energy_multiplier = 2.0
	ring.set_surface_override_material(0, mat)
	ring.position = Vector3(0, 0.05, 0)
	portal.add_child(ring)

	# OmniLight3D
	var light := OmniLight3D.new()
	light.light_color = portal_color
	light.light_energy = 1.5
	light.omni_range = 8.0
	light.position = Vector3(0, 3, 0)
	portal.add_child(light)

	# Label (larger)
	var label := Label3D.new()
	UITheme.style_label3d(label, "Exit Portal", "zone_sign")
	label.font_size = 48
	label.outline_size = 8
	label.position = Vector3(0, 6.5, 0)
	portal.add_child(label)

	return portal


# --- Item Spawn Table ---

static func _get_excursion_item_table(season: String) -> Array:
	var table: Array = [
		{"item_id": "golden_seed", "weight": 5},
		{"item_id": "mystic_herb", "weight": 8},
		{"item_id": "starfruit", "weight": 6},
		{"item_id": "truffle_shaving", "weight": 10},
		{"item_id": "rainbow_creature", "weight": 4},
		{"item_id": "excursion_berry", "weight": 12},
		{"item_id": "ancient_grain_seed", "weight": 5},
		{"item_id": "wild_honey", "weight": 15},
		{"item_id": "herb_basil", "weight": 15},
		{"item_id": "sugar", "weight": 10},
		{"item_id": "vinegar", "weight": 10},
	]

	# Season modifiers
	match season:
		"spring":
			# Boost seeds
			for entry in table:
				if entry["item_id"] in ["golden_seed", "ancient_grain_seed"]:
					entry["weight"] += 5
		"summer":
			# Boost fruits/essences
			for entry in table:
				if entry["item_id"] in ["starfruit", "excursion_berry"]:
					entry["weight"] += 5
		"autumn":
			# Boost mushroom-like ingredients
			for entry in table:
				if entry["item_id"] in ["truffle_shaving", "mystic_herb"]:
					entry["weight"] += 5
		"winter":
			# Boost honey, herbs
			for entry in table:
				if entry["item_id"] in ["wild_honey", "herb_basil"]:
					entry["weight"] += 5

	return table
