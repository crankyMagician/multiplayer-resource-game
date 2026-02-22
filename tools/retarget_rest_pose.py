"""Blender script: Fix AR Kit base models to match UAL mannequin skeleton exactly.

Usage:
  blender --background --python tools/retarget_rest_pose.py -- <mannequin.glb> <source.glb> <output.glb>

This script:
1. Imports mannequin to get the canonical 65-bone UAL skeleton
2. Imports source model (AR Kit modular character)
3. Renames misnamed bones (e.g. index_03_leaf_l → index_04_leaf_l)
4. Deletes extra bones not in the mannequin (Blender _end bones, etc.)
5. Poses the armature to match mannequin rest positions (level-by-level)
6. Applies pose as rest pose (Blender adjusts mesh bind poses automatically)
7. Collapses finger bone weights into hand bones (prevents animation stretching)
8. Exports the result as GLB with exactly matching skeleton
"""
import bpy
import sys
from pathlib import Path


# Bones after original conversion that were named wrong.
# The BONE_MAP in convert_arkit_to_ual.py mapped finger joint 4 to *_03_leaf
# but the UAL mannequin actually has *_04_leaf.
BONE_RENAMES = {
    "index_03_leaf_l": "index_04_leaf_l",
    "index_03_leaf_r": "index_04_leaf_r",
    "middle_03_leaf_l": "middle_04_leaf_l",
    "middle_03_leaf_r": "middle_04_leaf_r",
    "ring_03_leaf_l": "ring_04_leaf_l",
    "ring_03_leaf_r": "ring_04_leaf_r",
    "pinky_03_leaf_l": "pinky_04_leaf_l",
    "pinky_03_leaf_r": "pinky_04_leaf_r",
    "thumb_03_leaf_l": "thumb_04_leaf_l",
    "thumb_03_leaf_r": "thumb_04_leaf_r",
}

FINGER_BONE_PREFIXES = ["thumb_", "index_", "middle_", "ring_", "pinky_"]


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    for dt in [bpy.data.meshes, bpy.data.materials, bpy.data.armatures,
               bpy.data.textures, bpy.data.images, bpy.data.actions]:
        for b in list(dt):
            if b.users == 0:
                dt.remove(b)


def find_armature(objects):
    for obj in objects:
        if obj.type == 'ARMATURE':
            return obj
    return None


def import_glb(filepath):
    """Import a GLB and return its new objects."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(filepath))
    after = set(bpy.data.objects)
    return after - before


def get_bone_rest_matrices(armature_obj):
    """Get bone name -> armature-space rest matrix for all bones."""
    result = {}
    for bone in armature_obj.data.bones:
        result[bone.name] = bone.matrix_local.copy()
    return result


def rename_misnamed_bones(arm):
    """Rename bones that were incorrectly mapped by the original conversion script."""
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')

    renamed = 0
    for ebone in arm.data.edit_bones:
        if ebone.name in BONE_RENAMES:
            old_name = ebone.name
            ebone.name = BONE_RENAMES[old_name]
            renamed += 1

    bpy.ops.object.mode_set(mode='OBJECT')

    # Also rename vertex groups on skinned meshes
    if renamed > 0:
        for child in bpy.data.objects:
            if child.type != 'MESH':
                continue
            skinned = (child.parent == arm) or any(
                m.type == 'ARMATURE' and m.object == arm for m in child.modifiers
            )
            if not skinned:
                continue
            for vg in child.vertex_groups:
                if vg.name in BONE_RENAMES:
                    vg.name = BONE_RENAMES[vg.name]

    print(f"  Renamed {renamed} misnamed bones")
    return renamed


def delete_extra_bones(arm, valid_bone_names):
    """Delete any bones not in the valid set. Vertex weights are redistributed to parents."""
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')

    to_delete = []
    for ebone in arm.data.edit_bones:
        if ebone.name not in valid_bone_names:
            to_delete.append(ebone.name)

    # Reparent children of deleted bones to their grandparent before deletion
    for bone_name in to_delete:
        ebone = arm.data.edit_bones.get(bone_name)
        if ebone:
            parent = ebone.parent
            for child in list(ebone.children):
                child.parent = parent

    # Delete the extra bones
    for bone_name in to_delete:
        ebone = arm.data.edit_bones.get(bone_name)
        if ebone:
            arm.data.edit_bones.remove(ebone)

    bpy.ops.object.mode_set(mode='OBJECT')

    # Clean up vertex groups for deleted bones on skinned meshes
    # Merge weights into parent bone's vertex group
    if to_delete:
        for child in bpy.data.objects:
            if child.type != 'MESH':
                continue
            skinned = (child.parent == arm) or any(
                m.type == 'ARMATURE' and m.object == arm for m in child.modifiers
            )
            if not skinned:
                continue
            for bone_name in to_delete:
                vg = child.vertex_groups.get(bone_name)
                if vg:
                    child.vertex_groups.remove(vg)

    print(f"  Deleted {len(to_delete)} extra bones: {to_delete}")
    return len(to_delete)


def collapse_finger_weights(arm):
    """Merge all finger bone weights into hand_l/hand_r.

    AR Kit hand meshes have correct vertex groups but vertices are spatially
    far from their finger bone pivots (in bone-local space). During animation,
    finger rotations amplify movement 10-17x causing stretched/deformed fingers.
    Collapsing everything into the hand bone eliminates per-finger deformation.
    """
    for child in bpy.data.objects:
        if child.type != 'MESH':
            continue
        skinned = (child.parent == arm) or any(
            m.type == 'ARMATURE' and m.object == arm for m in child.modifiers
        )
        if not skinned:
            continue

        for side in ['_l', '_r']:
            hand_vg = child.vertex_groups.get(f"hand{side}")
            if not hand_vg:
                continue

            finger_vgs = []
            for vg in child.vertex_groups:
                if any(vg.name.startswith(p) and vg.name.endswith(side)
                       for p in FINGER_BONE_PREFIXES):
                    finger_vgs.append(vg)

            if not finger_vgs:
                continue

            # Transfer weights from finger groups to hand group
            for vert in child.data.vertices:
                added_weight = 0.0
                for fvg in finger_vgs:
                    try:
                        w = fvg.weight(vert.index)
                        if w > 0:
                            added_weight += w
                    except RuntimeError:
                        pass
                if added_weight > 0:
                    try:
                        existing = hand_vg.weight(vert.index)
                    except RuntimeError:
                        existing = 0.0
                    hand_vg.add([vert.index], existing + added_weight, 'REPLACE')

            # Remove finger vertex groups
            for fvg in finger_vgs:
                child.vertex_groups.remove(fvg)

    print("  Collapsed finger weights into hand bones")


def apply_mannequin_pose(arm, mannequin_rests):
    """Pose armature bones to match mannequin rest positions, level-by-level."""
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='POSE')

    # Group bones by depth level
    bones_by_depth = {}
    unmatched = []
    for pbone in arm.pose.bones:
        if pbone.name in mannequin_rests:
            depth = 0
            p = pbone.parent
            while p:
                depth += 1
                p = p.parent
            bones_by_depth.setdefault(depth, []).append(pbone)
        else:
            unmatched.append(pbone.name)

    # Process level by level, updating depsgraph between levels
    matched = 0
    for depth in sorted(bones_by_depth.keys()):
        for pbone in bones_by_depth[depth]:
            pbone.matrix = mannequin_rests[pbone.name]
            matched += 1
        bpy.context.view_layer.update()

    print(f"  Posed {matched} bones across {len(bones_by_depth)} depth levels")
    if unmatched:
        print(f"  WARNING: Unmatched bones after cleanup: {unmatched}")

    # Apply pose as rest pose
    bpy.ops.pose.select_all(action='SELECT')
    bpy.ops.pose.armature_apply()
    print("  Applied pose as rest pose")

    bpy.ops.object.mode_set(mode='OBJECT')


def export_glb(filepath, armature_obj):
    """Export the model as GLB."""
    bpy.ops.object.select_all(action='DESELECT')
    armature_obj.select_set(True)
    for child in bpy.data.objects:
        if child.parent == armature_obj or (
            child.type == 'MESH' and any(
                m.type == 'ARMATURE' and m.object == armature_obj
                for m in child.modifiers
            )
        ):
            child.select_set(True)

    bpy.ops.export_scene.gltf(
        filepath=str(filepath),
        export_format='GLB',
        use_selection=True,
        export_apply=False,
        export_animations=False,
        export_skins=True,
        export_all_influences=True,
    )
    print(f"  Exported: {filepath}")


def process(mannequin_path, source_path, output_path):
    print(f"\n=== Retargeting AR Kit model to UAL ===")
    print(f"  Mannequin: {mannequin_path}")
    print(f"  Source:    {source_path}")
    print(f"  Output:    {output_path}")

    clear_scene()

    # 1. Import mannequin — get canonical bone list and rest poses
    print("\n1. Importing mannequin reference...")
    mann_objs = import_glb(mannequin_path)
    mann_arm = find_armature(mann_objs)
    if not mann_arm:
        print("ERROR: No armature in mannequin!")
        return False

    mannequin_rests = get_bone_rest_matrices(mann_arm)
    mannequin_bone_names = set(mannequin_rests.keys())
    print(f"  Mannequin bones: {len(mannequin_bone_names)}")

    # Remove mannequin objects
    for obj in mann_objs:
        bpy.data.objects.remove(obj, do_unlink=True)
    for a in list(bpy.data.armatures):
        if a.users == 0:
            bpy.data.armatures.remove(a)
    for m in list(bpy.data.meshes):
        if m.users == 0:
            bpy.data.meshes.remove(m)

    # 2. Import source model
    print("\n2. Importing source model...")
    source_objs = import_glb(source_path)
    source_arm = find_armature(source_objs)
    if not source_arm:
        print("ERROR: No armature in source model!")
        return False

    source_bone_names = {b.name for b in source_arm.data.bones}
    print(f"  Source bones: {len(source_bone_names)}")
    print(f"  Shared with mannequin: {len(source_bone_names & mannequin_bone_names)}")
    print(f"  Only in source: {sorted(source_bone_names - mannequin_bone_names)}")
    print(f"  Only in mannequin: {sorted(mannequin_bone_names - source_bone_names)}")

    # 3. Rename misnamed bones (finger leaf bones)
    print("\n3. Fixing misnamed bones...")
    rename_misnamed_bones(source_arm)

    # 4. Delete extra bones not in mannequin
    print("\n4. Deleting extra bones...")
    delete_extra_bones(source_arm, mannequin_bone_names)

    # Verify bone count matches
    remaining = {b.name for b in source_arm.data.bones}
    missing = mannequin_bone_names - remaining
    extra = remaining - mannequin_bone_names
    print(f"\n  After cleanup: {len(remaining)} bones")
    if missing:
        print(f"  WARNING: Missing mannequin bones: {sorted(missing)}")
    if extra:
        print(f"  WARNING: Still extra bones: {sorted(extra)}")
    if not missing and not extra:
        print(f"  PERFECT: Bone set matches mannequin exactly ({len(remaining)} bones)")

    # 5. Retarget rest pose
    print("\n5. Retargeting rest pose...")
    apply_mannequin_pose(source_arm, mannequin_rests)

    # 5b. Collapse finger weights into hand bones
    print("\n5b. Collapsing finger weights...")
    collapse_finger_weights(source_arm)

    # 6. Verify
    print("\n6. Verifying...")
    max_diff = 0.0
    for bone in source_arm.data.bones:
        if bone.name in mannequin_rests:
            diff = (bone.matrix_local.translation - mannequin_rests[bone.name].translation).length
            max_diff = max(max_diff, diff)
    print(f"  Max position difference: {max_diff:.6f}")

    # 7. Export
    print("\n7. Exporting...")
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    export_glb(output_path, source_arm)

    return True


def main():
    argv = sys.argv
    if '--' not in argv:
        print("Usage: blender --background --python retarget_rest_pose.py -- <mannequin.glb> <source.glb> <output.glb>")
        sys.exit(1)

    args = argv[argv.index('--') + 1:]
    if len(args) < 3:
        print("Need 3 args: mannequin.glb source.glb output.glb")
        sys.exit(1)

    mannequin_path, source_path, output_path = args[0], args[1], args[2]

    if not Path(mannequin_path).exists():
        print(f"ERROR: {mannequin_path} not found")
        sys.exit(1)
    if not Path(source_path).exists():
        print(f"ERROR: {source_path} not found")
        sys.exit(1)

    success = process(mannequin_path, source_path, output_path)
    if not success:
        sys.exit(1)

    print("\nDone!")


if __name__ == "__main__":
    main()
