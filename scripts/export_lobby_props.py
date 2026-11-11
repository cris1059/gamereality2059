import os
import bpy
from mathutils import Matrix

OUTPUT_DIR = r"C:\Users\Crstopher\Documents\cyberpunk online\src\assets\environment\rooftop"
ASSET_NAMES = (
    "CCTV",
    "CCTV_2",
    "Electrical_Box_1",
    "Electrical_Box_2",
    "Electrical_Box_3",
    "Exhaust_Fan_1",
    "Exhaust_Fan_2",
    "Gooseneck_Vent",
    "Large_Exhaust",
    "Straight_Vent",
    "Neon_Strip_Basic_1",
    "Neon_Strip_Basic_2",
    "Neon_Tube_1",
    "Neon_Tube_2",
)

os.makedirs(OUTPUT_DIR, exist_ok=True)

exported = []
missing = []
for asset_name in ASSET_NAMES:
    root = bpy.data.objects.get(asset_name)
    if root is None:
        missing.append(asset_name)
        continue

    bpy.ops.object.select_all(action="DESELECT")
    members = [root, *root.children_recursive]
    for member in members:
        member.select_set(True)

    original_matrix = root.matrix_world.copy()
    root.matrix_world = Matrix.Identity(4)
    output_path = os.path.join(OUTPUT_DIR, f"{asset_name}.glb")
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_materials="EXPORT",
    )
    root.matrix_world = original_matrix
    exported.append(asset_name)

print("REALITY2059_EXPORT_COMPLETE", len(exported), "assets", exported)
print("REALITY2059_EXPORT_MISSING", missing)
