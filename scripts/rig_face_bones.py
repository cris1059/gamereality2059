import json
import os
import sys

import bpy
from mathutils import Vector

# Adds facial bones (nose, nostrils, lips, mouth corners, ears) to a Quaternius
# universal base so MORPHLAB can shape the face at runtime with Bone.Transform.
# Usage (headless):
#   blender -b <source.blend> --python rig_face_bones.py -- <out.blend> <out.fbx> <report.json>
# The source .blend is never overwritten; results are saved as copies.

FACE_BONES = (
    "nose", "nostril_l", "nostril_r", "lip_upper", "lip_lower",
    "lip_corner_l", "lip_corner_r", "ear_l", "ear_r",
)


def body_and_eyes():
    body = max((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: len(o.data.vertices))
    return body, bpy.data.objects["Eyes"]


def head_vertices(body):
    group = body.vertex_groups["Head"]
    result = []
    for v in body.data.vertices:
        for g in v.groups:
            if g.group == group.index and g.weight > 0.3:
                result.append(body.matrix_world @ v.co)
                break
    return result


def landmarks(body, eyes):
    verts = head_vertices(body)
    eye_points = [eyes.matrix_world @ v.co for v in eyes.data.vertices]
    eye_z = sum(p.z for p in eye_points) / len(eye_points)
    eye_front = max(p.y for p in eye_points)
    # Midline profile of the front of the face (the skull back shares heights).
    bins = {}
    for p in verts:
        if abs(p.x) < 0.006 and p.y > eye_front - 0.03:
            key = round(p.z / 0.002)
            if key not in bins or p.y > bins[key].y:
                bins[key] = p
    profile = [bins[k] for k in sorted(bins, reverse=True)]
    below = [p for p in profile if eye_z - 0.12 < p.z < eye_z - 0.01]
    nose_tip = max((p for p in below if p.z > eye_z - 0.075), key=lambda p: p.y)
    after_nose = [p for p in below if p.z < nose_tip.z]

    def extreme(start_z, pick_max, span):
        window = [p for p in after_nose if start_z - span < p.z < start_z]
        return (max if pick_max else min)(window, key=lambda p: p.y)

    subnasal = extreme(nose_tip.z - 0.004, False, 0.022)
    upper_lip = extreme(subnasal.z - 0.002, True, 0.02)
    mouth = extreme(upper_lip.z - 0.002, False, 0.014)
    lower_lip = extreme(mouth.z - 0.002, True, 0.02)
    corner_band = [p for p in verts if abs(p.z - mouth.z) < 0.005 and p.y > upper_lip.y - 0.022]
    wing_band = [p for p in verts if abs(p.z - (subnasal.z + 0.008)) < 0.005 and p.y > subnasal.y - 0.01]
    ears = {}
    for side, sign in (("l", 1), ("r", -1)):
        band = [p for p in verts if sign * p.x > 0 and eye_z - 0.07 < p.z < eye_z + 0.03 and p.y < eye_front - 0.05]
        outer = max(sign * p.x for p in band)
        ear = [p for p in band if sign * p.x > outer - 0.022]
        center = Vector((0, 0, 0))
        for p in ear:
            center += p
        ears[side] = (center / len(ear), outer * sign)
    return {
        "eye_z": eye_z,
        "eye_front": eye_front,
        "nose_tip": nose_tip,
        "subnasal": subnasal,
        "upper_lip": upper_lip,
        "mouth": mouth,
        "lower_lip": lower_lip,
        "mouth_half_width": max(abs(p.x) for p in corner_band),
        "nose_half_width": max(abs(p.x) for p in wing_band if abs(p.x) < 0.035),
        "ears": ears,
    }


def keep_single_material(obj, prefix):
    # The importer turned each extra slot into an extra SurfaceAppearance.
    keep = next(m for m in obj.data.materials if m and m.name.startswith(prefix))
    obj.data.materials.clear()
    obj.data.materials.append(keep)
    for polygon in obj.data.polygons:
        polygon.material_index = 0


def bone_specs(lm):
    """Bone head/tail plus an ellipsoid region (center, radii) for the weights."""
    nose_tip, sub = lm["nose_tip"], lm["subnasal"]
    upper, lower, mouth = lm["upper_lip"], lm["lower_lip"], lm["mouth"]
    mouth_w, nose_w = lm["mouth_half_width"], lm["nose_half_width"]
    nose_root_z = (lm["eye_z"] + nose_tip.z) * 0.5
    specs = {
        "nose": ((0, lm["eye_front"], nose_root_z), (0, nose_tip.y, nose_tip.z),
                 (0, nose_tip.y - 0.012, nose_tip.z + 0.006), (0.016, 0.026, 0.03)),
        "lip_upper": ((0, upper.y - 0.012, upper.z), (0, upper.y, upper.z),
                      (0, upper.y - 0.004, upper.z), (mouth_w * 0.75, 0.012, 0.0075)),
        "lip_lower": ((0, lower.y - 0.012, lower.z), (0, lower.y, lower.z),
                      (0, lower.y - 0.004, lower.z - 0.001), (mouth_w * 0.75, 0.012, 0.0085)),
    }
    for side, sign in (("l", 1), ("r", -1)):
        wing = Vector((sign * nose_w * 0.75, sub.y, sub.z + 0.008))
        specs["nostril_" + side] = (tuple(wing - Vector((0, 0.01, 0))), tuple(wing),
                                    tuple(wing), (0.01, 0.012, 0.01))
        corner = Vector((sign * mouth_w, mouth.y - 0.008, mouth.z))
        specs["lip_corner_" + side] = (tuple(corner - Vector((0, 0.01, 0))), tuple(corner),
                                       tuple(corner), (0.01, 0.012, 0.009))
        ear_center, outer_x = lm["ears"][side]
        root = Vector((ear_center.x - sign * 0.012, ear_center.y, ear_center.z))
        specs["ear_" + side] = (tuple(root), (outer_x, ear_center.y, ear_center.z),
                                tuple(ear_center), (0.02, 0.03, 0.035))
    return specs


def add_bones(armature, specs):
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="EDIT")
    edit_bones = armature.data.edit_bones
    head = edit_bones["Head"]
    to_local = armature.matrix_world.inverted()
    for name, (head_pos, tail_pos, _, _) in specs.items():
        bone = edit_bones.get(name) or edit_bones.new(name)
        bone.head = to_local @ Vector(head_pos)
        bone.tail = to_local @ Vector(tail_pos)
        if (bone.tail - bone.head).length < 0.005:
            bone.tail = bone.head + (to_local.to_3x3() @ Vector((0, 0.008, 0)))
        bone.parent = head
        bone.use_connect = False
        bone.use_deform = True
    bpy.ops.object.mode_set(mode="OBJECT")


def smooth_falloff(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def paint_weights(body, specs):
    head_group = body.vertex_groups["Head"]
    groups = {name: (body.vertex_groups.get(name) or body.vertex_groups.new(name=name)) for name in specs}
    painted = {name: 0 for name in specs}
    for v in body.data.vertices:
        head_weight = 0.0
        for g in v.groups:
            if g.group == head_group.index:
                head_weight = g.weight
        if head_weight <= 0:
            continue
        world = body.matrix_world @ v.co
        # One face region per vertex (the strongest) keeps influences <= 4.
        best_name, best_weight = None, 0.0
        for name, (_, _, center, radii) in specs.items():
            offset = world - Vector(center)
            if name.startswith("ear_") and offset.x * (1 if name.endswith("_l") else -1) < -0.012:
                continue
            distance = (Vector((offset.x / radii[0], offset.y / radii[1], offset.z / radii[2]))).length
            weight = smooth_falloff(1 - distance)
            if weight > best_weight:
                best_name, best_weight = name, weight
        if best_name and best_weight > 0.01:
            transferred = head_weight * best_weight
            groups[best_name].add([v.index], transferred, "REPLACE")
            head_group.add([v.index], head_weight - transferred, "REPLACE")
            painted[best_name] += 1
    return painted


def export_fbx(path):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        if obj.type in {"ARMATURE", "MESH"}:
            obj.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        object_types={"ARMATURE", "MESH"},
        add_leaf_bones=False,
        bake_anim=False,
        path_mode="COPY",
        embed_textures=True,
    )


def main():
    out_blend, out_fbx, out_report = sys.argv[sys.argv.index("--") + 1:][:3]
    body, eyes = body_and_eyes()
    armature = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    keep_single_material(eyes, "MI_Eyes")
    keep_single_material(bpy.data.objects["Eyebrows"], "MI_Hair")
    lm = landmarks(body, eyes)
    specs = bone_specs(lm)
    add_bones(armature, specs)
    painted = paint_weights(body, specs)
    os.makedirs(os.path.dirname(out_blend), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out_blend, copy=True)
    export_fbx(out_fbx)
    report = {
        "body": body.name,
        "bones": len(armature.data.bones),
        "painted": painted,
        "landmarks": {k: (list(v) if isinstance(v, Vector) else v) for k, v in lm.items() if k != "ears"},
    }
    with open(out_report, "w") as f:
        json.dump(report, f, indent=1)
    print("REALITY2059_FACE_RIG_COMPLETE", json.dumps(report["painted"]))


main()
