"""Blender script: Collapse finger bone weights into hand bones on existing GLBs.

Usage:
  blender --background --python tools/collapse_finger_weights.py -- <input.glb> <output.glb>

This is a standalone fix for AR Kit hand meshes where finger bone vertices are
spatially far from their bone pivots, causing 10-17x amplified deformation
during animation. It merges all finger bone vertex weights into hand_l/hand_r
so hands move as rigid blocks.

IMPORTANT: This does NOT re-run the retarget pipeline. Use this on models that
are already correctly retargeted to avoid inverse bind matrix drift.
"""
import bpy
import sys
from pathlib import Path

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


def collapse_finger_weights(arm):
    """Merge all finger bone weights into hand_l/hand_r."""
    total_collapsed = 0
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
            verts_affected = 0
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
                    verts_affected += 1

            # Remove finger vertex groups
            for fvg in finger_vgs:
                child.vertex_groups.remove(fvg)

            if verts_affected > 0:
                print(f"  {child.name}: hand{side} ← {len(finger_vgs)} finger groups, {verts_affected} verts")
                total_collapsed += verts_affected

    return total_collapsed


def process(input_path, output_path):
    print(f"\n=== Collapsing Finger Weights ===")
    print(f"  Input:  {input_path}")
    print(f"  Output: {output_path}")

    clear_scene()

    # Import model
    print("\n1. Importing model...")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(input_path))
    after = set(bpy.data.objects)
    new_objs = after - before

    arm = find_armature(new_objs)
    if not arm:
        print("ERROR: No armature found!")
        return False

    print(f"  Armature: {arm.name} ({len(arm.data.bones)} bones)")

    # Collapse finger weights
    print("\n2. Collapsing finger weights...")
    total = collapse_finger_weights(arm)
    print(f"  Total vertices affected: {total}")

    if total == 0:
        print("  WARNING: No finger weights found to collapse. Already processed?")

    # Export
    print("\n3. Exporting...")
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    for child in bpy.data.objects:
        if child.parent == arm or (
            child.type == 'MESH' and any(
                m.type == 'ARMATURE' and m.object == arm
                for m in child.modifiers
            )
        ):
            child.select_set(True)

    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format='GLB',
        use_selection=True,
        export_apply=False,
        export_animations=False,
        export_skins=True,
        export_all_influences=True,
    )
    print(f"  Exported: {output_path}")
    return True


def main():
    argv = sys.argv
    if '--' not in argv:
        print("Usage: blender --background --python collapse_finger_weights.py -- <input.glb> <output.glb>")
        sys.exit(1)

    args = argv[argv.index('--') + 1:]
    if len(args) < 2:
        print("Need 2 args: input.glb output.glb")
        sys.exit(1)

    input_path, output_path = args[0], args[1]

    if not Path(input_path).exists():
        print(f"ERROR: {input_path} not found")
        sys.exit(1)

    success = process(input_path, output_path)
    if not success:
        sys.exit(1)

    print("\nDone!")


if __name__ == "__main__":
    main()
