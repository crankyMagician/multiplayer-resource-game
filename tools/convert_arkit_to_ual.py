"""Blender batch: Convert Synty FBX to GLB with UAL bones."""
import bpy, sys
from pathlib import Path

BONE_MAP = {
    "Hips": "pelvis", "Spine": "spine_01", "Spine1": "spine_02",
    "Spine2": "spine_03", "Neck": "neck_01", "Head": "Head",
    "HeadTop_End": "Head_leaf",
    "Shoulder.L": "clavicle_l", "Arm.L": "upperarm_l",
    "ForeArm.L": "lowerarm_l", "Hand.L": "hand_l",
    "Shoulder.R": "clavicle_r", "Arm.R": "upperarm_r",
    "ForeArm.R": "lowerarm_r", "Hand.R": "hand_r",
    "UpLeg.L": "thigh_l", "Leg.L": "calf_l", "Foot.L": "foot_l",
    "ToeBase.L": "ball_l", "Toe_End.L": "ball_leaf_l",
    "UpLeg.R": "thigh_r", "Leg.R": "calf_r", "Foot.R": "foot_r",
    "ToeBase.R": "ball_r", "Toe_End.R": "ball_leaf_r",
}
FINGER_NAMES = {"HandThumb":"thumb","HandIndex":"index","HandMiddle":"middle","HandRing":"ring","HandPinky":"pinky"}
for sp, up in FINGER_NAMES.items():
    for ss, su in [(".L","_l"),(".R","_r")]:
        for i in range(1,5):
            sn = f"{sp}{i}{ss}"
            BONE_MAP[sn] = f"{up}_{i:02d}{su}" if i<=3 else f"{up}_03_leaf{su}"

def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for c in bpy.data.collections: bpy.data.collections.remove(c)
    for bt in [bpy.data.meshes, bpy.data.materials, bpy.data.armatures, bpy.data.textures, bpy.data.images, bpy.data.actions]:
        for b in bt:
            if b.users == 0: bt.remove(b)

def find_armature():
    for obj in bpy.data.objects:
        if obj.type == 'ARMATURE': return obj
    return None

def rename_bones(arm):
    unmapped = []
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    for bone in arm.data.edit_bones:
        if bone.name in BONE_MAP: bone.name = BONE_MAP[bone.name]
        elif bone.name not in BONE_MAP.values(): unmapped.append(bone.name)
    bpy.ops.object.mode_set(mode='OBJECT')
    return unmapped

def rename_vertex_groups(arm):
    for child in bpy.data.objects:
        if child.type != 'MESH': continue
        skinned = (child.parent == arm) or any(m.type=='ARMATURE' and m.object==arm for m in child.modifiers)
        if not skinned: continue
        for vg in child.vertex_groups:
            if vg.name in BONE_MAP: vg.name = BONE_MAP[vg.name]

def insert_root_bone(arm):
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.data.edit_bones
    pelvis = eb.get("pelvis")
    if not pelvis:
        bpy.ops.object.mode_set(mode='OBJECT'); return
    if eb.get("root"):
        bpy.ops.object.mode_set(mode='OBJECT'); return
    root = eb.new("root")
    root.head = (0,0,0); root.tail = (0,0.1,0)
    pelvis.parent = root
    bpy.ops.object.mode_set(mode='OBJECT')
    print("  Inserted root bone")

def process_fbx(fbx_path, output_path):
    print(f"\nProcessing: {fbx_path}")
    clear_scene()
    bpy.ops.import_scene.fbx(filepath=str(fbx_path), use_anim=False, ignore_leaf_bones=False, automatic_bone_orientation=False)
    arm = find_armature()
    if arm:
        unmapped = rename_bones(arm)
        if unmapped: print(f"  WARNING: Unmapped bones: {unmapped}")
        rename_vertex_groups(arm)
        insert_root_bone(arm)
        arm.name = "Armature"; arm.data.name = "Armature"
    else:
        print(f"  Mesh-only part, exporting as-is")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(output_path), export_format='GLB', use_selection=False, export_apply=True, export_animations=False, export_skins=True)
    print(f"  Exported: {output_path}")
    return True

def main():
    argv = sys.argv
    if '--' not in argv: sys.exit(1)
    args = argv[argv.index('--')+1:]
    if len(args) < 2: sys.exit(1)
    source_dir, output_dir = Path(args[0]), Path(args[1])
    if not source_dir.exists(): print(f"ERROR: {source_dir}"); sys.exit(1)
    fbx_files = sorted(source_dir.rglob("*.fbx"))
    if not fbx_files: fbx_files = sorted(source_dir.rglob("*.FBX"))
    if not fbx_files: print(f"ERROR: No FBX in {source_dir}"); sys.exit(1)
    print(f"Found {len(fbx_files)} FBX files")
    success = failed = 0
    for fp in fbx_files:
        rel = fp.relative_to(source_dir)
        out = output_dir / rel.with_suffix('.glb')
        if process_fbx(fp, out): success += 1
        else: failed += 1
    print(f"\nDone! {success} converted, {failed} failed out of {len(fbx_files)} total")

if __name__ == "__main__": main()
