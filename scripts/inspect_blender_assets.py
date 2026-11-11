import bpy

print("REALITY2059_ASSET_INVENTORY_BEGIN")
for obj in sorted(bpy.data.objects, key=lambda item: item.name.lower()):
    if obj.type != "MESH":
        continue
    polygons = len(obj.data.polygons)
    vertices = len(obj.data.vertices)
    materials = [slot.material.name for slot in obj.material_slots if slot.material]
    print(f"ASSET|{obj.name}|vertices={vertices}|polygons={polygons}|materials={','.join(materials)}")
print("REALITY2059_ASSET_INVENTORY_END")
