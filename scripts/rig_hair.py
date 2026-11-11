import json
import os
import sys

import bpy
from mathutils import Matrix, Vector

# Adds the Quaternius hairstyles to a face-rigged universal base as meshes
# skinned 100% to the Head bone, so they follow head animation and scaling.
# Usage (headless):
#   blender -b <base_Face.blend> --python rig_hair.py -- <hair_gltf_dir> <out.blend> <out.fbx> <report.json> [texture_dir]
# The source .blend is never overwritten.

# Each style was authored on one base. Eye landmarks (mean eye height, front of
# the eyes) measured on both bases let any style be moved onto the other head.
REFERENCE_EYES = {
    "male": (1.69857, 0.080638),
    "female": (1.65605, 0.075333),
}
STYLES = {
    "Hair_Buzzed": "male",
    "Hair_SimpleParted": "male",
    "Hair_Beard": "male",
    "Hair_BuzzedFemale": "female",
    "Hair_Buns": "female",
    "Hair_Long": "female",
}


def current_eyes():
    eyes = bpy.data.objects["Eyes"]
    points = [eyes.matrix_world @ v.co for v in eyes.data.vertices]
    return sum(p.z for p in points) / len(points), max(p.y for p in points)


def import_style(path, name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    imported = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in imported if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for mesh in meshes:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    hair = bpy.context.view_layer.objects.active
    # Keep the world transform when dropping the importer's empties.
    world = hair.matrix_world.copy()
    hair.parent = None
    hair.matrix_world = world
    for leftover in imported:
        if leftover != hair and leftover.name in bpy.data.objects:
            bpy.data.objects.remove(leftover, do_unlink=True)
    hair.name = name
    hair.data.name = name
    return hair


def fit(hair, offset):
    # The glTF hairs face -Y; the bases in these .blend files face +Y.
    hair.matrix_world = Matrix.Translation(offset) @ Matrix.Rotation(3.14159265, 4, "Z") @ hair.matrix_world
    bpy.ops.object.select_all(action="DESELECT")
    hair.select_set(True)
    bpy.context.view_layer.objects.active = hair
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def skin_to_head(hair, armature):
    hair.parent = armature
    hair.matrix_parent_inverse = armature.matrix_world.inverted()
    group = hair.vertex_groups.new(name="Head")
    group.add([v.index for v in hair.data.vertices], 1.0, "REPLACE")
    modifier = hair.modifiers.new(name="Armature", type="ARMATURE")
    modifier.object = armature


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


def share_materials(hair, canonical):
    # Every glTF import brings its own copy of MI_Hair_1 / MI_Hair_2 (and their
    # 2048px textures); keep one material per texture set.
    for index, material in enumerate(hair.data.materials):
        if material:
            key = material.name.split(".")[0]
            canonical.setdefault(key, material)
            hair.data.materials[index] = canonical[key]


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    hair_dir, out_blend, out_fbx, out_report = args[:4]
    texture_dir = args[4] if len(args) > 4 else None
    armature = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    eye_z, eye_front = current_eyes()
    canonical = {}
    report = {}
    for name, authored_on in STYLES.items():
        reference_z, reference_front = REFERENCE_EYES[authored_on]
        offset = Vector((0, eye_front - reference_front, eye_z - reference_z))
        hair = import_style(os.path.join(hair_dir, name + ".gltf"), name)
        fit(hair, offset)
        skin_to_head(hair, armature)
        share_materials(hair, canonical)
        points = [hair.matrix_world @ v.co for v in hair.data.vertices]
        report[name] = {
            "offset": list(offset),
            "tris": sum(len(p.vertices) - 2 for p in hair.data.polygons),
            "materials": [m.name for m in hair.data.materials if m],
            "z": [min(p.z for p in points), max(p.z for p in points)],
            "y": [min(p.y for p in points), max(p.y for p in points)],
        }
    bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    # Some images in the source .blend point at paths that no longer exist,
    # so they would be exported empty. Relink them from the Quaternius pack.
    for image in bpy.data.images:
        if image.size[0] == 0 and texture_dir:
            candidate = os.path.join(texture_dir, os.path.basename(image.filepath) or image.name)
            if os.path.exists(candidate):
                image.filepath = candidate
                image.reload()
    # Roblox caps textures at 1024px; shrinking first keeps the FBX small.
    for image in bpy.data.images:
        if image.size[0] > 1024:
            image.scale(1024, 1024)
        if image.size[0] > 0:
            image.pack()
    bpy.ops.wm.save_as_mainfile(filepath=out_blend, copy=True)
    export_fbx(out_fbx)
    with open(out_report, "w") as f:
        json.dump(report, f, indent=1)


main()
