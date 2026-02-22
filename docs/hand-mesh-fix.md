# Hand Mesh Stretching Fix

## Problem

HANDS meshes in the modular character base GLBs (`modular_female.glb`, `modular_male.glb`) showed stretched/deformed fingers during animation. When UAL animations rotated finger bones, vertices traveled arcs far larger than intended.

## Root Cause

The character models (from the AR Kit "Customizable 3D Characters Complete Bundle") were retargeted from Mixamo to UAL skeleton proportions using `tools/retarget_rest_pose.py`. The retarget correctly moved bone positions and updated inverse bind matrices via Blender's "Apply Pose as Rest," but the **mesh vertices stayed in their original positions** in bone-local space.

This meant finger bone pivots (in UAL proportions) were far from the finger mesh vertices (still at AR Kit proportions). During animation, bone rotations amplified vertex movement:

| Bone | Mannequin avg distance | AR Kit avg distance | Amplification |
|------|----------------------|-------------------|---------------|
| `pinky_03_l` | 0.012 | 0.203 | **17.5x** |
| `index_03_l` | 0.013 | 0.203 | **15.1x** |
| `hand_l` | 0.079 | 0.224 | 2.8x |

## Fix: Finger Weight Collapse

Rather than transforming thousands of vertices to match mannequin proportions (which would distort the hand shape), we collapse all finger bone vertex weights into `hand_l`/`hand_r`. This makes hands move as rigid blocks — appropriate for these stylized low-poly characters where individual finger articulation creates visual artifacts rather than detail.

### Script: `tools/collapse_finger_weights.py`

Standalone Blender script that:
1. Imports a GLB
2. Finds all skinned meshes
3. For each side (`_l`/`_r`), transfers weights from 20 finger groups (thumb/index/middle/ring/pinky x 01/02/03/04_leaf) into the hand group
4. Removes the finger vertex groups
5. Exports as GLB

```bash
blender --background --python tools/collapse_finger_weights.py -- <input.glb> <output.glb>
```

The function is also integrated into `retarget_rest_pose.py` as step 5b for fresh imports from FBX source.

### Important: Don't Re-Run Full Retarget

Running the full `retarget_rest_pose.py` on already-retargeted models causes arm placement drift. The "apply pose as rest" step recalculates inverse bind matrices, and double-application introduces floating-point drift. Use the standalone `collapse_finger_weights.py` for already-processed models.

## Affected Meshes

- **HANDS_01_1, HANDS_02_1/2/3**: Direct hand meshes (~600-850 verts per side)
- **TORSO_* variants**: Long-sleeve torsos with a few vertices weighted to finger bones (~10-60 verts)
- Both male and female base models

## Attribution Correction

During this session, all tooling and documentation was updated to correctly attribute these models to "AR Kit" (Customizable 3D Characters Complete Bundle, Unity Asset Store) instead of "Synty." The character tools were renamed:
- `convert_synty_to_ual.py` → `convert_arkit_to_ual.py`
- `import_synty_characters.sh` → `import_arkit_characters.sh`
- `validate_synty_parts.gd` → `validate_character_parts.gd`
