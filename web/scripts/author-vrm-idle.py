"""Author minimal VRM-native idle + bow animations for the item-shop NPC.

Run with:
    blender --background --python web/scripts/author-vrm-idle.py

Hand-authored against the item_shop VRM rig (J_Bip_C_Hips, J_Bip_C_Spine,
J_Bip_C_Chest, J_Bip_C_UpperChest, J_Bip_C_Head, J_Bip_L_UpperArm,
J_Bip_R_UpperArm). The bones already exist in the rig with VRM-standard
naming, so no retargeting is needed — the exported GLB plays directly on
the model when loaded.

Outputs assets/npcs/item_shop/item_shop_anims.glb containing two
animations:
  - vrm_idle  : small breathing motion (2s loop)
  - vrm_bow   : forward bow + hold + return (3s, one-shot)
"""

import bpy
import math
import os
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
IN_PATH = os.path.join(REPO_ROOT, 'assets/npcs/item_shop/item_shop.glb')
OUT_PATH = os.path.join(REPO_ROOT, 'assets/npcs/item_shop/item_shop_anims.glb')

# ── Reset scene ──────────────────────────────────────────────────────
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()
for img in list(bpy.data.images):
    bpy.data.images.remove(img)
for mat in list(bpy.data.materials):
    bpy.data.materials.remove(mat)
for act in list(bpy.data.actions):
    bpy.data.actions.remove(act)

# ── Import VRM ──────────────────────────────────────────────────────
print(f"[author-vrm] importing {IN_PATH}")
bpy.ops.import_scene.gltf(filepath=IN_PATH)

armature = None
for obj in bpy.data.objects:
    if obj.type == 'ARMATURE':
        armature = obj
        break
if not armature:
    print("[author-vrm] no armature in VRM — aborting")
    sys.exit(1)

print(f"[author-vrm] armature: {armature.name}")
bpy.context.view_layer.objects.active = armature
bpy.ops.object.mode_set(mode='POSE')

# Bone references we'll animate. Blender exposes pose bones via name.
def pb(name):
    if name not in armature.pose.bones:
        raise KeyError(f"bone {name} not in rig — check VRM naming")
    return armature.pose.bones[name]

# Verify the bones we want are present
needed = ['J_Bip_C_Hips', 'J_Bip_C_Spine', 'J_Bip_C_Chest', 'J_Bip_C_UpperChest', 'J_Bip_C_Head']
for n in needed:
    pb(n)
print(f"[author-vrm] all {len(needed)} required bones found")


def reset_pose():
    """Wipe all pose-bone keyframes and reset to rest."""
    for b in armature.pose.bones:
        b.rotation_mode = 'XYZ'
        b.rotation_euler = (0, 0, 0)
        b.location = (0, 0, 0)


def key_euler(bone_name, frame, x_deg=0, y_deg=0, z_deg=0):
    """Set a pose-bone Euler XYZ rotation and keyframe it at frame.

    Bone-local Euler rotation — convenient for authoring against a
    VRM rig where the bone-local Z axis is anatomically "twist around
    bone" for limbs and "forward bend" for the spine chain (typical
    VRM bind-pose convention).
    """
    b = pb(bone_name)
    b.rotation_mode = 'XYZ'
    b.rotation_euler = (math.radians(x_deg), math.radians(y_deg), math.radians(z_deg))
    b.keyframe_insert(data_path='rotation_euler', frame=frame)


def make_action(name, end_frame, set_extrapolation='CONSTANT'):
    """Create+activate a new Action with the given name and timing.

    Returns the Action so we can attach NLA-like info. Each Action
    we create becomes an animation in the exported GLB."""
    a = bpy.data.actions.new(name=name)
    armature.animation_data_create()
    armature.animation_data.action = a
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = end_frame
    # bpy.context.scene.render.fps is 24 by default; that's fine.
    return a


# ── Pose helper: arms-down rest ─────────────────────────────────────
# VRM bind pose is T-pose with arms horizontal. Every keyframe in our
# anims has to explicitly set the arms or they snap back to horizontal
# (since the AnimationPlayer overrides bone-local rotations on each
# frame, including bones with no animation data — those bones get the
# original Blender rest values, which is T-pose).
#
# The rotations below bring J_Bip_L/R_UpperArm and the forearms into a
# natural arms-down stance, matching what feels right visually for the
# item-shop NPC. Found empirically by tweaking values in Blender then
# checking the in-game render.
#
# Local Euler angles per bone (XYZ order). VRoid bones use local Y as
# the bone-length axis, so swinging an arm down from T-pose to a
# natural standing pose is a Z-axis rotation. Mirror across L/R.
# Forearms are kept near rest — X=±90 was a guess that looked like an
# elbow fold; with the upper arm fully vertical (Z=-80°) the forearm
# naturally hangs at the side without any twist.
#   L Upper Arm: Z -80°    (vertical, slight outward away from torso)
#   R Upper Arm: Z +80°    (mirror)
#   L/R Lower Arm: rest    (no rotation needed)
ARMS_DOWN = {
    'J_Bip_L_UpperArm': (0, 0, -80),
    'J_Bip_R_UpperArm': (0, 0, 80),
}


def key_arms_down(frame):
    for bone, (x, y, z) in ARMS_DOWN.items():
        key_euler(bone, frame, x_deg=x, y_deg=y, z_deg=z)


# ── Animation 1: vrm_idle ──────────────────────────────────────────
# 2-second breathing motion (48 frames at 24 fps). Chest rotates
# slightly forward on inhale, back on exhale. Arms held down at the
# sides for the whole loop so the NPC reads as a relaxed shopkeep
# rather than a T-posed mannequin.
print("[author-vrm] authoring vrm_idle")
reset_pose()
make_action('vrm_idle', 48)
# Arms down for every keyframe (frames 1, 12, 24, 36, 48). Without
# repeating these, Blender would interpolate back to T-pose between
# keyframes for un-keyed bones.
for f in (1, 12, 24, 36, 48):
    key_arms_down(f)
# Inhale (frame 1 → 12): chest opens, head slightly up
key_euler('J_Bip_C_Chest', 1, x_deg=0)
key_euler('J_Bip_C_UpperChest', 1, x_deg=0)
key_euler('J_Bip_C_Head', 1, x_deg=0)
key_euler('J_Bip_C_Chest', 12, x_deg=-3)
key_euler('J_Bip_C_UpperChest', 12, x_deg=-2)
key_euler('J_Bip_C_Head', 12, x_deg=-1)
# Hold (12 → 24): same pose
key_euler('J_Bip_C_Chest', 24, x_deg=-3)
key_euler('J_Bip_C_UpperChest', 24, x_deg=-2)
key_euler('J_Bip_C_Head', 24, x_deg=-1)
# Exhale (24 → 36): back to neutral, slightly past
key_euler('J_Bip_C_Chest', 36, x_deg=1)
key_euler('J_Bip_C_UpperChest', 36, x_deg=1)
key_euler('J_Bip_C_Head', 36, x_deg=0)
# Loop back to start (36 → 48)
key_euler('J_Bip_C_Chest', 48, x_deg=0)
key_euler('J_Bip_C_UpperChest', 48, x_deg=0)
key_euler('J_Bip_C_Head', 48, x_deg=0)


# ── Animation 2: vrm_bow ───────────────────────────────────────────
# 3-second bow: bend forward, hold, return. 72 frames at 24 fps.
print("[author-vrm] authoring vrm_bow")
# Build a NEW action so vrm_idle's keyframes don't bleed in.
reset_pose()
make_action('vrm_bow', 72)
# Arms down throughout the bow (same reason as in vrm_idle — un-keyed
# bones snap to T-pose).
for f in (1, 24, 48, 72):
    key_arms_down(f)
# Rest at frame 1
key_euler('J_Bip_C_Hips', 1, x_deg=0)
key_euler('J_Bip_C_Spine', 1, x_deg=0)
key_euler('J_Bip_C_Chest', 1, x_deg=0)
key_euler('J_Bip_C_UpperChest', 1, x_deg=0)
key_euler('J_Bip_C_Head', 1, x_deg=0)
# Bow forward by frame 24 (1 sec). Positive X on VRoid spine bones
# tilts forward; negative tilts backward. Distribute the bend across
# the spine chain so it reads as a bow, not a hip pivot. Head ducks
# along with the chest.
key_euler('J_Bip_C_Hips', 24, x_deg=5)
key_euler('J_Bip_C_Spine', 24, x_deg=15)
key_euler('J_Bip_C_Chest', 24, x_deg=15)
key_euler('J_Bip_C_UpperChest', 24, x_deg=10)
key_euler('J_Bip_C_Head', 24, x_deg=15)
# Hold the bow (24 → 48)
key_euler('J_Bip_C_Hips', 48, x_deg=5)
key_euler('J_Bip_C_Spine', 48, x_deg=15)
key_euler('J_Bip_C_Chest', 48, x_deg=15)
key_euler('J_Bip_C_UpperChest', 48, x_deg=10)
key_euler('J_Bip_C_Head', 48, x_deg=15)
# Return to rest by frame 72 (3s total)
key_euler('J_Bip_C_Hips', 72, x_deg=0)
key_euler('J_Bip_C_Spine', 72, x_deg=0)
key_euler('J_Bip_C_Chest', 72, x_deg=0)
key_euler('J_Bip_C_UpperChest', 72, x_deg=0)
key_euler('J_Bip_C_Head', 72, x_deg=0)


# ── Push both actions into the NLA so the glTF export keeps both ──
# glTF export only writes animations attached to the armature via
# NLA strips or via the active action. We create one NLA track per
# action so both end up in the exported GLB.
bpy.ops.object.mode_set(mode='OBJECT')

# Clear any existing NLA tracks
if armature.animation_data and armature.animation_data.nla_tracks:
    for t in list(armature.animation_data.nla_tracks):
        armature.animation_data.nla_tracks.remove(t)

for action_name in ['vrm_idle', 'vrm_bow']:
    action = bpy.data.actions.get(action_name)
    if not action:
        continue
    track = armature.animation_data.nla_tracks.new()
    track.name = action_name
    track.strips.new(action_name, 1, action)

# Clear active action so it doesn't double-export
armature.animation_data.action = None

# ── Export ─────────────────────────────────────────────────────────
print(f"[author-vrm] exporting to {OUT_PATH}")
bpy.ops.export_scene.gltf(
    filepath=OUT_PATH,
    export_format='GLB',
    use_selection=False,
    export_apply=True,
    export_animations=True,
    export_animation_mode='ACTIONS',
    export_yup=True,
    export_image_format='AUTO',
)
print(f"[author-vrm] wrote {OUT_PATH} ({os.path.getsize(OUT_PATH)} bytes)")
