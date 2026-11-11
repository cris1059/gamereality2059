import os
import re

import bpy


OUTPUT_DIR = r"C:\Users\Crstopher\Documents\cyberpunk online\src\assets\environment\city2059"
OUTPUT_PATH = os.path.join(OUTPUT_DIR, "Reality2059_City2059.glb")


def safe_name(value):
    cleaned = re.sub(r"[^A-Za-z0-9_]+", "_", value or "Unassigned")
    return cleaned.strip("_") or "Unassigned"


source = bpy.context.active_object
if source is None or source.type != "MESH":
    raise RuntimeError("Select the city mesh before running this exporter")

os.makedirs(OUTPUT_DIR, exist_ok=True)

# Work on a disposable duplicate. The source .blend is never saved or modified.
city = source.copy()
city.data = source.data.copy()
city.name = "Reality2059_City_Source"
bpy.context.collection.objects.link(city)

bpy.ops.object.select_all(action="DESELECT")
city.select_set(True)
bpy.context.view_layer.objects.active = city
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

# A single 64k-polygon mesh is unreliable in Roblox. Material separation produces
# manageable pieces while preserving the original transforms and visual grouping.
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.separate(type="MATERIAL")
bpy.ops.object.mode_set(mode="OBJECT")

pieces = [obj for obj in bpy.context.selected_objects if obj.type == "MESH"]
for index, piece in enumerate(sorted(pieces, key=lambda item: item.name.lower()), start=1):
    material = piece.active_material.name if piece.active_material else "Unassigned"
    piece.name = f"City2059_{index:02d}_{safe_name(material)}"

bpy.ops.object.select_all(action="DESELECT")
for piece in pieces:
    piece.select_set(True)
bpy.context.view_layer.objects.active = pieces[0]

bpy.ops.export_scene.gltf(
    filepath=OUTPUT_PATH,
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_yup=True,
    export_materials="EXPORT",
)

print(
    "REALITY2059_CITY_EXPORT_COMPLETE",
    OUTPUT_PATH,
    "pieces",
    len(pieces),
    "polygons",
    sum(len(piece.data.polygons) for piece in pieces),
)
