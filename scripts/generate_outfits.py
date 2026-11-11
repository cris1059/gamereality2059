import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree

# Generates the four MORPHLAB outfits as garment shells built on the body's own
# surface. Each garment keeps the body's vertex groups (or copies them from the
# nearest body vertex for new geometry such as a coat skirt), so it bends with
# the skeleton exactly like the skin underneath.
# Usage (headless):
#   blender -b <base_HairV2.blend> --python generate_outfits.py -- <outfit ids,comma> <out.blend> <out.fbx> <report.json> [preview_dir]
# Pieces are named Outfit_<id>_<Top|Overlay|Bottom|Boots|Trim>; colours are
# applied in Roblox, the materials here only tint the previews.

TORSO = {"spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r"}
ARMS_UPPER = {"upperarm_l", "upperarm_r"}
ARMS_LOWER = {"lowerarm_l", "lowerarm_r"}
NECK = {"neck_01"}
HIPS = {"pelvis"}
THIGHS = {"thigh_l", "thigh_r"}
CALVES = {"calf_l", "calf_r"}
FEET = {"foot_l", "foot_r", "ball_l", "ball_r"}
PREVIEW_COLORS = {
    "Top": (0.05, 0.05, 0.07, 1),
    "Overlay": (0.85, 0.85, 0.9, 1),
    "Bottom": (0.08, 0.08, 0.1, 1),
    "Boots": (0.02, 0.02, 0.03, 1),
    "Trim": (1.0, 0.1, 0.2, 1),
}


class Body:
    def __init__(self, obj):
        self.obj = obj
        self.matrix = obj.matrix_world.copy()
        names = {g.index: g.name for g in obj.vertex_groups}
        self.dominant = []
        self.world = []
        for v in obj.data.vertices:
            group = max(v.groups, key=lambda g: g.weight) if v.groups else None
            self.dominant.append(names[group.group] if group else "")
            self.world.append(self.matrix @ v.co)
        self.tree = KDTree(len(obj.data.vertices))
        for index, position in enumerate(self.world):
            self.tree.insert(position, index)
        self.tree.balance()

    def in_groups(self, index, groups):
        return self.dominant[index] in groups


def shell(body, name, keep, offset, thickness, extra=None):
    """Copy of the body faces whose vertices all satisfy keep(index, world),
    pushed out along the normals by offset (+ extra(index, world)) and given
    thickness. Vertex groups are preserved by the bmesh deform layer."""
    bm = bmesh.new()
    bm.from_mesh(body.obj.data)
    bm.verts.ensure_lookup_table()
    # Some source faces are wound inward; make every face point outward so
    # the push direction is consistent (otherwise the skin pokes through).
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    # Keyed by the BMVert itself: deleting geometry renumbers v.index, so
    # index-based lookups afterwards would mix up normals between vertices.
    source_index = {v: v.index for v in bm.verts}
    normals = {v: v.normal.copy() for v in bm.verts}
    keep_verts = {v for v in bm.verts if keep(v.index, body.world[v.index])}
    drop = [f for f in bm.faces if not all(v in keep_verts for v in f.verts)]
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    for v in bm.verts:
        index = source_index[v]
        push = offset + (extra(index, body.world[index]) if extra else 0.0)
        v.co += normals[v] * push
    if thickness > 0:
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thickness)
    return bm


def skirt(body, top_z, bottom_z, flare, margin, front_opening=0.0):
    """Tube from the waist to the knees around both legs (coat tails), open at
    the front by `front_opening` radians. New vertices take the weights of the
    nearest body vertex."""
    bm = bmesh.new()
    deform = bm.verts.layers.deform.verify()
    source = body.obj.data
    rings, sides, steps = [], 24, 10
    for step in range(steps + 1):
        t = step / steps
        z = top_z + (bottom_z - top_z) * t
        slice_points = [p for i, p in enumerate(body.world) if abs(p.z - z) < 0.015 and body.dominant[i] in HIPS | THIGHS | CALVES | TORSO]
        xs = [p.x for p in slice_points] or [-0.15, 0.15]
        ys = [p.y for p in slice_points] or [-0.1, 0.1]
        cx, cy = 0.0, (max(ys) + min(ys)) * 0.5
        rx = max(abs(x) for x in xs) + margin + flare * t * t
        ry = (max(ys) - min(ys)) * 0.5 + margin + flare * 0.6 * t * t
        ring = []
        for side in range(sides):
            angle = 2 * math.pi * side / sides
            world = Vector((cx + math.cos(angle) * rx, cy + math.sin(angle) * ry, z))
            vert = bm.verts.new(body.matrix.inverted() @ world)
            _, nearest, _ = body.tree.find(world)
            for group in source.vertices[nearest].groups:
                vert[deform][group.group] = group.weight
            ring.append(vert)
        rings.append(ring)
    # The body faces +Y, so the front of the tube is around angle pi / 2.
    def in_opening(side):
        angle = 2 * math.pi * (side + 0.5) / sides
        return abs(math.atan2(math.sin(angle - math.pi / 2), math.cos(angle - math.pi / 2))) < front_opening
    for upper, lower in zip(rings, rings[1:]):
        for side in range(sides):
            if not in_opening(side):
                bm.faces.new((upper[side], upper[(side + 1) % sides], lower[(side + 1) % sides], lower[side]))
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.004)
    return bm


def smooth_bump(center, radius, height):
    def extra(_index, world):
        distance = (world - center).length
        return height * max(0.0, 1 - distance / radius) ** 2
    return extra


def outfit_pieces(body, outfit):
    """Returns {piece: bmesh} for one outfit id."""
    hand = bpy.data.objects[ARMATURE_NAME].data.bones["hand_l"]
    wrist_x = abs((bpy.data.objects[ARMATURE_NAME].matrix_world @ hand.head_local).x)

    def groups(*sets, z_min=-9.0, z_max=9.0):
        allowed = set().union(*sets)
        return lambda i, p: body.in_groups(i, allowed) and z_min <= p.z <= z_max

    neck_top = 1.585 if body.world_top > 1.79 else 1.55
    pieces = {}
    if outfit == "vanguard":
        top = groups(TORSO, ARMS_UPPER, ARMS_LOWER, NECK, z_max=neck_top)
        pieces["Top"] = shell(body, "Top", top, 0.012, 0.004)
        pieces["Overlay"] = shell(body, "Overlay", lambda i, p: top(i, p) and p.z > 1.33 and abs(p.x) > 0.05 and abs(p.x) < 0.3, 0.016, 0.003)
        pieces["Trim"] = shell(body, "Trim", lambda i, p: (top(i, p) and abs(p.x) < 0.008 and p.y > 0 and p.z < 1.5) or (body.in_groups(i, ARMS_LOWER) and abs(p.x) > wrist_x - 0.035), 0.019, 0.003)
        # Rises over the jacket hem so no skin shows at the waist.
        pieces["Bottom"] = shell(body, "Bottom", lambda i, p: groups(HIPS, THIGHS, CALVES)(i, p) or (body.in_groups(i, TORSO) and p.z < 1.13), 0.007, 0.004, extra=lambda i, p: smooth_bump(Vector((math.copysign(0.17, p.x), -0.03, 0.74)), 0.09, 0.02)(i, p))
        pieces["Boots"] = shell(body, "Boots", groups(FEET, CALVES, z_max=0.3), 0.014, 0.004)
    elif outfit == "mercenary":
        top = groups(TORSO, ARMS_UPPER, ARMS_LOWER, NECK, HIPS, z_max=neck_top)
        pieces["Top"] = shell(body, "Top", top, 0.016, 0.004)
        pieces["Overlay"] = skirt(body, 1.02, 0.46, 0.1, 0.04, front_opening=0.42)
        pieces["Trim"] = shell(body, "Trim", lambda i, p: top(i, p) and 1.035 <= p.z <= 1.07 and not body.in_groups(i, ARMS_UPPER | ARMS_LOWER), 0.022, 0.004)
        pieces["Bottom"] = shell(body, "Bottom", groups(HIPS, THIGHS, CALVES), 0.007, 0.004)
        pieces["Boots"] = shell(body, "Boots", groups(FEET, CALVES, z_max=0.42), 0.014, 0.004)
    elif outfit == "infiltrator":
        suit = groups(TORSO, ARMS_UPPER, ARMS_LOWER, NECK, HIPS, THIGHS, CALVES, z_max=neck_top - 0.02)
        pieces["Bottom"] = shell(body, "Bottom", suit, 0.004, 0.002)
        pieces["Top"] = shell(body, "Top", groups(TORSO, ARMS_UPPER, NECK, z_min=1.24, z_max=neck_top), 0.014, 0.004)
        pieces["Trim"] = shell(body, "Trim", lambda i, p: suit(i, p) and ((body.in_groups(i, THIGHS | CALVES) and abs(p.x) > 0.155) or (body.in_groups(i, TORSO | HIPS) and abs(p.x) > 0.125 and p.z < 1.24)), 0.008, 0.002)
        pieces["Boots"] = shell(body, "Boots", groups(FEET, CALVES, z_max=0.45), 0.014, 0.004)
    elif outfit == "nomad":
        hoodie = groups(TORSO, ARMS_UPPER, ARMS_LOWER, NECK, z_min=1.16, z_max=neck_top + 0.02)
        neck_bump = lambda i, p: 0.022 if body.in_groups(i, NECK) else 0.0
        pieces["Top"] = shell(body, "Top", hoodie, 0.016, 0.004, extra=neck_bump)
        pieces["Bottom"] = shell(body, "Bottom", groups(HIPS, THIGHS, CALVES, TORSO, z_max=1.2), 0.005, 0.003)
        pieces["Trim"] = shell(body, "Trim", lambda i, p: hoodie(i, p) and ((1.16 <= p.z <= 1.19 and not body.in_groups(i, ARMS_UPPER | ARMS_LOWER)) or (body.in_groups(i, ARMS_LOWER) and abs(p.x) > wrist_x - 0.03)), 0.021, 0.003)
        pieces["Boots"] = shell(body, "Boots", groups(FEET, CALVES, z_max=0.24), 0.016, 0.004)
    else:
        raise ValueError(outfit)
    return pieces


def create_object(body, name, bm, material):
    mesh = bpy.data.meshes.new(name)
    obj = body.obj.copy()
    obj.data = mesh
    obj.name = name
    # Vertex group names live on the mesh (Blender 3+), so a new mesh has the
    # weights but no names: without them the FBX has no skin and the garment
    # stays frozen in the bind pose in Roblox. Names go in first (clearing
    # groups also clears weights), in the body's order so the deform-layer
    # indices keep pointing at the right bones.
    obj.vertex_groups.clear()
    for group in body.obj.vertex_groups:
        obj.vertex_groups.new(name=group.name)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    for modifier in list(obj.modifiers):
        if modifier.type != "ARMATURE":
            obj.modifiers.remove(modifier)
    bpy.context.collection.objects.link(obj)
    mesh.materials.clear()
    mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    return obj


def material_for(piece):
    name = "MI_Outfit_" + piece
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.diffuse_color = PREVIEW_COLORS[piece]
    return material


def render_previews(preview_dir, outfit_ids):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.render.resolution_x = 300
    scene.render.resolution_y = 420
    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.lens = 50
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    target = Vector((0, 0, 0.95))
    for obj in bpy.data.objects:
        if obj.name.startswith("Hair_"):
            obj.hide_render = True
    for outfit in outfit_ids:
        for obj in bpy.data.objects:
            if obj.name.startswith("Outfit_"):
                obj.hide_render = not obj.name.startswith("Outfit_" + outfit + "_")
        for label, angle in (("front", 20), ("back", 200)):
            offset = Matrix.Rotation(math.radians(angle), 3, "Z") @ Vector((0, 3.4, 0.3))
            camera.location = target + offset
            camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = os.path.join(preview_dir, "%s_%s.png" % (outfit, label))
            bpy.ops.render.render(write_still=True)
    # Skinning check: arms lowered like the Roblox idle pose; garments that are
    # not skinned stay in the T-pose and show up immediately.
    armature = bpy.data.objects.get(ARMATURE_NAME)
    if armature:
        for name in ("upperarm_l", "upperarm_r"):
            bone = armature.pose.bones.get(name)
            if bone:
                head = bone.head.copy()
                angle = math.radians(-70 if (armature.matrix_world @ bone.tail).x > 0 else 70)
                bone.matrix = Matrix.Translation(head) @ Matrix.Rotation(angle, 4, "Y") @ Matrix.Translation(-head) @ bone.matrix
        bpy.context.view_layer.update()
        for outfit in outfit_ids:
            for obj in bpy.data.objects:
                if obj.name.startswith("Outfit_"):
                    obj.hide_render = not obj.name.startswith("Outfit_" + outfit + "_")
            offset = Matrix.Rotation(math.radians(20), 3, "Z") @ Vector((0, 3.4, 0.3))
            camera.location = target + offset
            camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = os.path.join(preview_dir, "%s_posed.png" % outfit)
            bpy.ops.render.render(write_still=True)
        for bone in armature.pose.bones:
            bone.matrix_basis = Matrix()
        bpy.context.view_layer.update()
    bpy.data.objects.remove(camera, do_unlink=True)


ARMATURE_NAME = "Armature"


def main():
    global ARMATURE_NAME
    args = sys.argv[sys.argv.index("--") + 1:]
    outfit_ids = args[0].split(",")
    out_blend, out_fbx, out_report = args[1:4]
    preview_dir = args[4] if len(args) > 4 else None
    armature = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    ARMATURE_NAME = armature.name
    body_object = max((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: len(o.data.vertices))
    body = Body(body_object)
    body.world_top = max(p.z for p in body.world)
    report = {}
    for outfit in outfit_ids:
        for piece, bm in outfit_pieces(body, outfit).items():
            name = "Outfit_%s_%s" % (outfit, piece)
            existing = bpy.data.objects.get(name)
            if existing:
                bpy.data.objects.remove(existing, do_unlink=True)
            obj = create_object(body, name, bm, material_for(piece))
            weighted = sum(1 for v in obj.data.vertices if any(g.weight > 0 for g in v.groups))
            report[name] = {"verts": len(obj.data.vertices), "weighted": weighted, "tris": sum(len(p.vertices) - 2 for p in obj.data.polygons)}
            if weighted < len(obj.data.vertices):
                raise RuntimeError("%s has %d unweighted vertices" % (name, len(obj.data.vertices) - weighted))
    if preview_dir:
        os.makedirs(preview_dir, exist_ok=True)
        render_previews(preview_dir, outfit_ids)
    bpy.ops.wm.save_as_mainfile(filepath=out_blend, copy=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        if obj.type in {"ARMATURE", "MESH"}:
            obj.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=out_fbx,
        use_selection=True,
        object_types={"ARMATURE", "MESH"},
        add_leaf_bones=False,
        bake_anim=False,
        path_mode="COPY",
        embed_textures=True,
    )
    with open(out_report, "w") as f:
        json.dump(report, f, indent=1)


try:
    main()
except Exception:
    import traceback

    report_path = sys.argv[sys.argv.index("--") + 1:][3]
    with open(report_path + ".error.txt", "w") as f:
        f.write(traceback.format_exc())
    raise
