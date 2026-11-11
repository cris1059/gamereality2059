import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

# Generates extra hairstyles fitted to each universal base's own scalp, skinned
# 100% to the Head bone like the Quaternius styles.
# Usage (headless):
#   blender -b <base_Hair.blend> --python generate_hair.py -- <out.blend> <out.fbx> <report.json> [preview_dir]
# The source .blend is never overwritten.

STYLES = ("Hair_Mohawk", "Hair_Afro", "Hair_Undercut", "Hair_Ponytail", "Hair_Spiky")


def smoothstep(edge0, edge1, x):
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)


def landmarks(body):
    eyes = bpy.data.objects["Eyes"]
    eye_points = [eyes.matrix_world @ v.co for v in eyes.data.vertices]
    group = body.vertex_groups["Head"]
    head = []
    for v in body.data.vertices:
        if any(g.group == group.index and g.weight > 0.5 for g in v.groups):
            head.append(body.matrix_world @ v.co)
    return {
        "eye_z": sum(p.z for p in eye_points) / len(eye_points),
        "eye_front": max(p.y for p in eye_points),
        "top": max(p.z for p in head),
        "back": min(p.y for p in head),
        "half_width": max(abs(p.x) for p in head),
    }


def is_scalp(p, lm):
    """Hair-covered skin: above the brows at the front, above the ears at the
    sides and down to the nape at the back. Ears are excluded."""
    eye_z, front = lm["eye_z"], lm["eye_front"]
    depth = front - p.y  # 0 at the eyes, grows toward the back of the head
    if abs(p.x) > lm["half_width"] - 0.012 and p.z < eye_z + 0.03:
        return False  # ears
    hairline = eye_z + 0.045 - smoothstep(0.03, 0.15, depth) * 0.12
    return p.z > hairline


def scalp_shell(body, lm, offset):
    """Copy of the scalp faces pushed out along the normals by offset."""
    source = bmesh.new()
    source.from_mesh(body.data)
    source.transform(body.matrix_world)
    source.normal_update()
    keep = {v for v in source.verts if is_scalp(v.co, lm)}
    faces = [f for f in source.faces if all(v in keep for v in f.verts)]
    shell = bmesh.new()
    remap = {}
    for face in faces:
        verts = []
        for v in face.verts:
            if v not in remap:
                remap[v] = shell.verts.new(v.co + v.normal * offset)
            verts.append(remap[v])
        shell.faces.new(verts)
    source.free()
    # The selection follows mesh edges, so the hairline is stair-stepped;
    # relaxing only the boundary straightens it without shrinking the cap.
    boundary = [v for v in shell.verts if v.is_boundary]
    for _ in range(8):
        bmesh.ops.smooth_vert(shell, verts=boundary, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    shell.normal_update()
    return shell


def midline_points(body, lm, spacing):
    """Points along the top of the scalp from the hairline to the nape, with
    their outward normals, roughly `spacing` apart."""
    shell = scalp_shell(body, lm, 0.0)
    # Pivot below the whole scalp: the angle then runs from the forehead
    # (positive) over the top (zero) to the nape (negative) without wrapping.
    center = Vector((0, (lm["eye_front"] + lm["back"]) * 0.5, lm["eye_z"] - 0.12))
    strip = [v for v in shell.verts if abs(v.co.x) < 0.01]
    strip.sort(key=lambda v: -math.atan2(v.co.y - center.y, v.co.z - center.z))
    points = []
    for v in strip:
        # Snap onto the exact midline so the crest is centred.
        position = Vector((0, v.co.y, v.co.z))
        normal = Vector((0, v.normal.y, v.normal.z)).normalized()
        if not points or (position - points[-1][0]).length >= spacing:
            points.append((position, normal))
    shell.free()
    return points


def add_sphere(bm, center, radius):
    result = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    bmesh.ops.translate(bm, verts=result["verts"], vec=center)


def relax(bm, iterations, factor=0.5):
    for _ in range(iterations):
        bmesh.ops.smooth_vert(bm, verts=bm.verts, factor=factor, use_axis_x=True, use_axis_y=True, use_axis_z=True)


def add_cone(bm, base, direction, radius, height, sides=6):
    direction = direction.normalized()
    tangent = direction.orthogonal().normalized()
    bitangent = direction.cross(tangent)
    ring = []
    for i in range(sides):
        angle = 2 * math.pi * i / sides
        ring.append(bm.verts.new(base + (tangent * math.cos(angle) + bitangent * math.sin(angle)) * radius))
    tip = bm.verts.new(base + direction * height)
    for i in range(sides):
        bm.faces.new((ring[i], ring[(i + 1) % sides], tip))
    bm.faces.new(list(reversed(ring)))


def add_tube(bm, points, radii, sides=10):
    rings = []
    for index, point in enumerate(points):
        ahead = points[min(index + 1, len(points) - 1)] - points[max(index - 1, 0)]
        tangent = ahead.normalized()
        normal = tangent.orthogonal().normalized()
        binormal = tangent.cross(normal)
        ring = []
        for i in range(sides):
            angle = 2 * math.pi * i / sides
            ring.append(bm.verts.new(point + (normal * math.cos(angle) + binormal * math.sin(angle)) * radii[index]))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(sides):
            bm.faces.new((a[i], a[(i + 1) % sides], b[(i + 1) % sides], b[i]))
    tip = bm.verts.new(points[-1] + (points[-1] - points[-2]).normalized() * radii[-1])
    for i in range(sides):
        bm.faces.new((rings[-1][i], rings[-1][(i + 1) % sides], tip))
    bm.faces.new(list(reversed(rings[0])))


def solidify(bm, thickness):
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=thickness)


def build_style(name, body, lm):
    eye_z, front, top = lm["eye_z"], lm["eye_front"], lm["top"]
    rng = random.Random(name)
    if name == "Hair_Mohawk":
        # Shaved sides plus a crest of spikes along the midline, tallest at
        # the crown and leaning back.
        bm = scalp_shell(body, lm, 0.0015)
        solidify(bm, 0.0015)
        strip = scalp_shell(body, lm, 0.005)
        bmesh.ops.delete(strip, geom=[v for v in strip.verts if abs(v.co.x) > 0.02], context="VERTS")
        solidify(strip, 0.006)
        # Skip the first points: a spike right on the hairline looks like a bump.
        points = midline_points(body, lm, 0.018)[2:]
        for index, (position, normal) in enumerate(points):
            t = index / max(len(points) - 1, 1)
            height = 0.035 + 0.06 * math.sin(math.pi * min(1.0, t * 1.15))
            direction = (normal + Vector((0, -0.45, 0.15))).normalized()
            add_cone(strip, position - normal * 0.004, direction, 0.019, height, sides=8)
        mesh = bpy.data.meshes.new(name + "_strip")
        strip.to_mesh(mesh)
        strip.free()
        bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
        return bm
    if name == "Hair_Afro":
        # Rounded base pulled toward a sphere around the head, topped with
        # large overlapping smooth puffs so it reads as a cloud of curls.
        bm = scalp_shell(body, lm, 0.004)
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True)
        center = Vector((0, (front + lm["back"]) * 0.5 - 0.01, eye_z + 0.03))
        for v in bm.verts:
            offset = v.co - center
            fullness = smoothstep(eye_z - 0.04, eye_z + 0.06, v.co.z)
            v.co = v.co.lerp(center + offset.normalized() * 0.118, 0.85 * fullness)
        relax(bm, 2, 0.3)
        solidify(bm, 0.006)
        bm.normal_update()
        # Positions are copied first: adding geometry invalidates BMVert refs.
        surface = [v.co.copy() for v in bm.verts if (v.co - center).normalized().z > -0.25 and (v.co - center).length > 0.1]
        rng.shuffle(surface)
        placed = []
        for position in surface:
            if all((position - p).length > 0.045 for p in placed):
                placed.append(position)
            if len(placed) >= 34:
                break
        for position in placed:
            puff = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=rng.uniform(0.034, 0.044))
            bmesh.ops.translate(bm, verts=puff["verts"], vec=position - (position - center).normalized() * 0.012)
        return bm
    if name == "Hair_Undercut":
        # Sides cut almost to the skin, a clear step up to the top volume,
        # which is swept forward over the forehead.
        bm = scalp_shell(body, lm, 0.003)
        raised = []
        for v in bm.verts:
            crown = smoothstep(eye_z + 0.05, eye_z + 0.065, v.co.z) * (1 - smoothstep(0.05, 0.062, abs(v.co.x)))
            sweep = 1 - smoothstep(0.0, 0.12, front - v.co.y)
            v.co += v.normal * 0.034 * crown + Vector((0, 0.01, 0.008)) * crown * sweep
            if crown > 0.01:
                raised.append(v)
        # Smoothing shrinks a surface; only the raised top is smoothed so the
        # close-cut sides stay above the skin.
        for _ in range(4):
            bmesh.ops.smooth_vert(bm, verts=raised, factor=0.4, use_axis_x=True, use_axis_y=True, use_axis_z=True)
        solidify(bm, 0.003)
        return bm
    if name == "Hair_Ponytail":
        # Slicked back hair; the tail starts above the nape, bulges out and
        # hangs clear of the neck.
        bm = scalp_shell(body, lm, 0.004)
        relax(bm, 1, 0.3)
        solidify(bm, 0.004)
        anchor = Vector((0, lm["back"] + 0.01, eye_z + 0.035))
        points, radii = [], []
        for i in range(14):
            t = i / 13
            points.append(anchor + Vector((0, -0.025 - 0.07 * math.sin(t * 1.6), -0.3 * t)))
            radii.append(0.03 * (1 - 0.7 * t) * (1 + 0.25 * math.sin(math.pi * min(1.0, t * 3))) + 0.004)
        add_tube(bm, points, radii, sides=12)
        tie = anchor + Vector((0, -0.022, 0))
        add_tube(bm, [tie + Vector((0, 0.008, 0.004)), tie + Vector((0, -0.008, -0.004))], [0.024, 0.024], sides=12)
        return bm
    if name == "Hair_Spiky":
        # Short cap with spikes pointing up and back.
        bm = scalp_shell(body, lm, 0.005)
        relax(bm, 1, 0.3)
        solidify(bm, 0.005)
        candidates = [v for v in bm.verts if v.co.z > eye_z + 0.055 and v.normal.z > 0.2]
        rng.shuffle(candidates)
        placed = []
        for v in candidates:
            if all((v.co - p).length > 0.03 for p in placed):
                placed.append(v.co.copy())
                direction = (v.normal + Vector((0, -0.6, 0.6))).normalized()
                add_cone(bm, v.co - v.normal * 0.004, direction, 0.016, rng.uniform(0.045, 0.07))
            if len(placed) >= 26:
                break
        return bm
    raise ValueError(name)


def create_object(name, bm, armature, material):
    bm.normal_update()
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for poly in mesh.polygons:
        poly.use_smooth = True
    mesh.materials.append(material)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.parent = armature
    obj.matrix_parent_inverse = armature.matrix_world.inverted()
    group = obj.vertex_groups.new(name="Head")
    group.add([v.index for v in mesh.vertices], 1.0, "REPLACE")
    modifier = obj.modifiers.new(name="Armature", type="ARMATURE")
    modifier.object = armature
    return obj


def render_previews(preview_dir, lm, names):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.render.resolution_x = 360
    scene.render.resolution_y = 360
    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.lens = 85
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    target = Vector((0, lm["eye_front"] - 0.09, lm["eye_z"] + 0.03))
    hairs = [o for o in bpy.data.objects if o.name.startswith("Hair_")]
    for name in names:
        for hair in hairs:
            hair.hide_render = hair.name != name
        for label, angle in (("front", 30), ("back", 200)):
            offset = Matrix.Rotation(math.radians(angle), 3, "Z") @ Vector((0, 0.75, 0.12))
            camera.location = target + offset
            camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = os.path.join(preview_dir, "%s_%s.png" % (name, label))
            bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(camera, do_unlink=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    out_blend, out_fbx, out_report = args[:3]
    preview_dir = args[3] if len(args) > 3 else None
    body = max((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: len(o.data.vertices))
    armature = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    material = next(m for m in bpy.data.materials if m.name.startswith("MI_Hair_1"))
    lm = landmarks(body)
    report = {"landmarks": lm, "styles": {}}
    for name in STYLES:
        existing = bpy.data.objects.get(name)
        if existing:
            bpy.data.objects.remove(existing, do_unlink=True)
        obj = create_object(name, build_style(name, body, lm), armature, material)
        report["styles"][name] = {"verts": len(obj.data.vertices), "tris": sum(len(p.vertices) - 2 for p in obj.data.polygons)}
    if preview_dir:
        os.makedirs(preview_dir, exist_ok=True)
        render_previews(preview_dir, lm, STYLES)
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
    # The Store build of Blender does not forward the console; keep the trace.
    import traceback

    report_path = sys.argv[sys.argv.index("--") + 1:][2]
    with open(report_path + ".error.txt", "w") as f:
        f.write(traceback.format_exc())
    raise
