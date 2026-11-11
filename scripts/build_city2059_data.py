import json
import math
import struct
import sys
import traceback

# Builds src/server/World/City2059Data.luau from the City2059 GLB:
#   * the material of every piece (the Roblox importer drops the glTF colours),
#   * invisible collision boxes (the city meshes are split by material, so each
#     one spans the whole city and Roblox's automatic collision would fill the
#     streets),
#   * open street spots for spawning.
# Plain Python (no bpy); run it with Blender's interpreter like the others:
#   blender -b --python build_city2059_data.py -- <city.glb> <out.luau> <report.json>
#
# Collision is a height map over the XZ plane: a piece is solid when it rests
# on the ground or on another solid piece, so floating signs, the monorail and
# bridges never block a street. Equal-height cells are merged into boxes.

CELL = 0.025           # GLB units per cell (1.8 studs at CityScale = 72)
FLOOR_Y = 0.13         # top of the city slab
WALKABLE = 0.04        # anything this close to the floor is walkable
SUPPORT_GAP = 0.12     # how far above a solid cell a piece may start
HEIGHT_STEP = 0.02     # height quantisation for merging
REFERENCE_MESH = 7     # Cuberpunk2077.009, the towers: largest bounds
MAX_FILLED_HOLE_AREA = 0.15
SURFACE_SLOPE_MIN = 0.65
SURFACE_THICKNESS = 0.008
SURFACE_CELL_FACTOR = 1
SURFACE_HEIGHT_STEP = 0.0125
# Street-level slabs are covered by the free-roam ground plane (top just under
# the city slab); only slabs higher than this above the floor are emitted.
SURFACE_MIN_RISE = 0.01


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    json_len = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + json_len])
    bin_start = 20 + json_len + 8
    return gltf, data, bin_start


def accessor(gltf, data, bin_start, index):
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    offset = bin_start + view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[acc["type"]]
    fmt = {5126: "f", 5125: "I", 5123: "H"}[acc["componentType"]]
    count = acc["count"] * width
    return struct.unpack_from("<%d%s" % (count, fmt), data, offset)


def srgb(linear):
    return max(0, min(255, round(255 * (max(linear, 0) ** (1 / 2.2)))))


def material_entry(material):
    pbr = material.get("pbrMetallicRoughness", {})
    base = pbr.get("baseColorFactor")
    emissive = material.get("emissiveFactor")
    specular = material.get("extensions", {}).get("KHR_materials_specular", {}).get("specularFactor", 0)
    entry = {}
    if "baseColorTexture" in pbr:
        entry["kind"] = "textured"
        color = base or [1, 1, 1, 1]
    elif emissive and max(emissive) > 0:
        entry["kind"] = "emissive"
        color = emissive
    else:
        entry["kind"] = "solid"
        color = base or [0.6, 0.6, 0.62, 1]
    entry["color"] = [srgb(c) for c in color[:3]]
    if entry["kind"] == "solid":
        brightness = sum(color[:3]) / 3
        entry["material"] = "Metal" if specular > 0.3 else ("Concrete" if brightness > 0.35 else "SmoothPlastic")
    return entry


def components(positions, indices):
    count = len(positions) // 3
    canonical = {}
    rep = [0] * count
    for i in range(count):
        key = (round(positions[3 * i], 4), round(positions[3 * i + 1], 4), round(positions[3 * i + 2], 4))
        rep[i] = canonical.setdefault(key, i)
    parent = list(range(count))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for t in range(0, len(indices), 3):
        a, b, c = find(rep[indices[t]]), find(rep[indices[t + 1]]), find(rep[indices[t + 2]])
        parent[b] = a
        parent[find(c)] = a
    groups = {}
    for t in range(0, len(indices), 3):
        groups.setdefault(find(rep[indices[t]]), []).append(t)
    return groups.values()


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    glb_path, out_path, report_path = args[0], args[1], args[2]
    gltf, data, bin_start = read_glb(glb_path)

    pieces = []
    bounds = []
    min_x = min_z = 1e9
    max_x = max_z = -1e9
    triangles_by_component = []
    for mesh_index, mesh in enumerate(gltf["meshes"]):
        primitive = mesh["primitives"][0]
        node = next(n for n in gltf["nodes"] if n.get("mesh") == mesh_index)
        material = gltf["materials"][primitive["material"]]
        position_accessor = gltf["accessors"][primitive["attributes"]["POSITION"]]
        bounds.append((position_accessor["min"], position_accessor["max"]))
        pieces.append({"node": node["name"], "mesh": mesh["name"], **material_entry(material)})
        positions = accessor(gltf, data, bin_start, primitive["attributes"]["POSITION"])
        indices = accessor(gltf, data, bin_start, primitive["indices"])
        for tris in components(positions, indices):
            ys = [positions[3 * indices[t + k] + 1] for t in tris for k in range(3)]
            triangles_by_component.append((min(ys), [[positions[3 * indices[t + k]:3 * indices[t + k] + 3] for k in range(3)] for t in tris]))
        min_x = min(min_x, position_accessor["min"][0]); max_x = max(max_x, position_accessor["max"][0])
        min_z = min(min_z, position_accessor["min"][2]); max_z = max(max_z, position_accessor["max"][2])

    columns = int(math.ceil((max_x - min_x) / CELL)) + 1
    rows = int(math.ceil((max_z - min_z) / CELL)) + 1
    height = [[FLOOR_Y] * columns for _ in range(rows)]

    def cells_of(triangle):
        """Cells under a triangle: its interior plus points along its edges
        (vertical walls have no XZ area)."""
        result = set()
        xs = [p[0] for p in triangle]; zs = [p[2] for p in triangle]
        c0 = max(0, int((min(xs) - min_x) / CELL)); c1 = min(columns - 1, int((max(xs) - min_x) / CELL))
        r0 = max(0, int((min(zs) - min_z) / CELL)); r1 = min(rows - 1, int((max(zs) - min_z) / CELL))
        (ax, _, az), (bx, _, bz), (cx, _, cz) = triangle
        area = (bx - ax) * (cz - az) - (cx - ax) * (bz - az)
        if abs(area) > 1e-9:
            for r in range(r0, r1 + 1):
                for c in range(c0, c1 + 1):
                    px = min_x + (c + 0.5) * CELL; pz = min_z + (r + 0.5) * CELL
                    w0 = ((bx - px) * (cz - pz) - (cx - px) * (bz - pz)) / area
                    w1 = ((cx - px) * (az - pz) - (ax - px) * (cz - pz)) / area
                    if w0 >= 0 and w1 >= 0 and w0 + w1 <= 1:
                        result.add((r, c))
        for i in range(3):
            p, q = triangle[i], triangle[(i + 1) % 3]
            steps = max(1, int(math.hypot(q[0] - p[0], q[2] - p[2]) / (CELL * 0.5)))
            for s in range(steps + 1):
                f = s / steps
                c = int((p[0] + (q[0] - p[0]) * f - min_x) / CELL)
                r = int((p[2] + (q[2] - p[2]) * f - min_z) / CELL)
                if 0 <= r < rows and 0 <= c < columns:
                    result.add((r, c))
        return result

    # Supported stacking, per cell: a triangle raises a cell only where it
    # starts at (or just above) that cell's current top. Walls rise from the
    # floor, roofs rest on walls; a monorail tube or a sign over a street
    # never reaches down to it, so the street stays open.
    entries = []
    surface_columns = math.ceil(columns / SURFACE_CELL_FACTOR)
    surface_rows = math.ceil(rows / SURFACE_CELL_FACTOR)
    surface_level = [[None] * surface_columns for _ in range(surface_rows)]
    for _, triangles in triangles_by_component:
        for triangle in triangles:
            ys = [p[1] for p in triangle]
            cells = cells_of(triangle)
            entries.append((min(ys), max(ys), cells))
            a, b, c = triangle
            ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
            vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
            nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            normal_length = math.sqrt(nx * nx + ny * ny + nz * nz)
            # Independent walkable slabs preserve streets, sidewalks, ramps,
            # roofs and bridges even when they do not form a supported column.
            if normal_length > 1e-9 and abs(ny) / normal_length >= SURFACE_SLOPE_MIN:
                surface_y = sum(ys) / 3
                if surface_y >= FLOOR_Y - 0.03:
                    # Always round down: the collision top must never protrude
                    # above the rendered road or ramp.
                    value = math.floor(surface_y / SURFACE_HEIGHT_STEP + 1e-6)
                    for r, c in cells:
                        sr, sc = r // SURFACE_CELL_FACTOR, c // SURFACE_CELL_FACTOR
                        previous = surface_level[sr][sc]
                        if previous is None or value < previous:
                            surface_level[sr][sc] = value
    entries.sort(key=lambda item: item[0])
    solid = [[False] * columns for _ in range(rows)]
    changed = True
    passes = 0
    while changed and passes < 40:
        changed = False
        passes += 1
        for bottom, top, cells in entries:
            for r, c in cells:
                if bottom <= height[r][c] + SUPPORT_GAP and top > height[r][c]:
                    height[r][c] = top
                    changed = True
                    if top > FLOOR_Y + WALKABLE:
                        solid[r][c] = True
    pending = []

    # Fill only small enclosed holes. Filling every enclosed region turned
    # legitimate plazas/courtyards into invisible blocks. Small holes still
    # need filling so a character cannot slip inside decorative structures.
    reached = [[False] * columns for _ in range(rows)]
    stack = [(r, c) for r in range(rows) for c in (0, columns - 1)] + [(r, c) for c in range(columns) for r in (0, rows - 1)]
    while stack:
        r, c = stack.pop()
        if reached[r][c] or solid[r][c]:
            continue
        reached[r][c] = True
        for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if 0 <= r + dr < rows and 0 <= c + dc < columns:
                stack.append((r + dr, c + dc))
    seen = [[False] * columns for _ in range(rows)]
    for r in range(rows):
        for c in range(columns):
            if solid[r][c] or reached[r][c] or seen[r][c]:
                continue
            region, rim, todo = [], 0.0, [(r, c)]
            seen[r][c] = True
            while todo:
                cr, cc = todo.pop()
                region.append((cr, cc))
                for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nr, nc = cr + dr, cc + dc
                    if 0 <= nr < rows and 0 <= nc < columns:
                        if solid[nr][nc]:
                            rim = max(rim, height[nr][nc])
                        elif not seen[nr][nc]:
                            seen[nr][nc] = True
                            todo.append((nr, nc))
            if len(region) * CELL * CELL <= MAX_FILLED_HOLE_AREA:
                for cr, cc in region:
                    height[cr][cc] = rim
                    solid[cr][cc] = True

    # Greedy merge of equal quantised heights into rectangles.
    level = [[round(height[r][c] / HEIGHT_STEP) if solid[r][c] else 0 for c in range(columns)] for r in range(rows)]
    used = [[False] * columns for _ in range(rows)]
    boxes = []
    for r in range(rows):
        for c in range(columns):
            if used[r][c] or level[r][c] == 0:
                continue
            value = level[r][c]
            width = 1
            while c + width < columns and not used[r][c + width] and level[r][c + width] == value:
                width += 1
            depth = 1
            while r + depth < rows and all(not used[r + depth][c + k] and level[r + depth][c + k] == value for k in range(width)):
                depth += 1
            for dr in range(depth):
                for dc in range(width):
                    used[r + dr][c + dc] = True
            top = value * HEIGHT_STEP
            boxes.append((min_x + (c + width / 2) * CELL, (FLOOR_Y - 0.05 + top) / 2, min_z + (r + depth / 2) * CELL,
                          width * CELL, top - (FLOOR_Y - 0.05), depth * CELL))

    # Thin walkable slabs. Skip a slab when the structural height map already
    # ends at the same level; that avoids duplicate physics on building tops.
    surface_boxes = []
    used_surface = [[False] * surface_columns for _ in range(surface_rows)]

    def eligible_surface(r, c, value):
        if r < 0 or r >= surface_rows or c < 0 or c >= surface_columns or used_surface[r][c] or surface_level[r][c] != value:
            return False
        top = value * SURFACE_HEIGHT_STEP
        duplicate = True
        for fr in range(r * SURFACE_CELL_FACTOR, min(rows, (r + 1) * SURFACE_CELL_FACTOR)):
            for fc in range(c * SURFACE_CELL_FACTOR, min(columns, (c + 1) * SURFACE_CELL_FACTOR)):
                if not solid[fr][fc] or abs(height[fr][fc] - top) > SURFACE_HEIGHT_STEP:
                    duplicate = False
        return not duplicate

    for r in range(surface_rows):
        for c in range(surface_columns):
            value = surface_level[r][c]
            if value is None or value * SURFACE_HEIGHT_STEP < FLOOR_Y + SURFACE_MIN_RISE or not eligible_surface(r, c, value):
                continue
            width = 1
            while eligible_surface(r, c + width, value):
                width += 1
            depth = 1
            while all(eligible_surface(r + depth, c + dc, value) for dc in range(width)):
                depth += 1
            for dr in range(depth):
                for dc in range(width):
                    used_surface[r + dr][c + dc] = True
            top = value * SURFACE_HEIGHT_STEP
            surface_boxes.append((
                min_x + (c + width / 2) * CELL * SURFACE_CELL_FACTOR,
                top - SURFACE_THICKNESS / 2,
                min_z + (r + depth / 2) * CELL * SURFACE_CELL_FACTOR,
                width * CELL * SURFACE_CELL_FACTOR,
                SURFACE_THICKNESS,
                depth * CELL * SURFACE_CELL_FACTOR,
            ))

    # Spawn spots: open floor cells (whole 9x9 neighbourhood walkable), spread
    # out with farthest-point sampling around the city centre.
    open_cells = []
    margin = 4
    for r in range(margin, rows - margin):
        for c in range(margin, columns - margin):
            if all(not solid[r + dr][c + dc] for dr in range(-margin, margin + 1) for dc in range(-margin, margin + 1)):
                open_cells.append((min_x + (c + 0.5) * CELL, min_z + (r + 0.5) * CELL))
    center_x, center_z = (min_x + max_x) / 2, (min_z + max_z) / 2
    open_cells.sort(key=lambda p: (p[0] - center_x) ** 2 + (p[1] - center_z) ** 2)
    central = open_cells[: max(1, len(open_cells) // 3)]
    spawns = [central[0]] if central else []
    while central and len(spawns) < 8:
        best = max(central, key=lambda p: min((p[0] - s[0]) ** 2 + (p[1] - s[1]) ** 2 for s in spawns))
        spawns.append(best)

    ref_min, ref_max = bounds[REFERENCE_MESH]
    ref_center = [(a + b) / 2 for a, b in zip(ref_min, ref_max)]
    ref_size = [b - a for a, b in zip(ref_min, ref_max)]

    def v3(values):
        return "Vector3.new(%s)" % ", ".join("%.4f" % v for v in values)

    lines = [
        "--!strict",
        "",
        "-- GENERATED by scripts/build_city2059_data.py from",
        "-- src/assets/environment/city2059/Reality2059_City2059.glb. Do not edit.",
        "-- Coordinates are glTF units (Y up), the same axes Roblox imports with.",
        "",
        "return table.freeze({",
        "\t-- The imported MeshPart whose box locates and scales the whole city.",
        "\tReferenceMesh = %s," % json.dumps(pieces[REFERENCE_MESH]["mesh"]),
        "\tReferenceCenter = %s," % v3(ref_center),
        "\tReferenceSize = %s," % v3(ref_size),
        "\tFloorY = %.4f," % FLOOR_Y,
        "\tCollisionCell = %.4f," % CELL,
        "\tCollisionVersion = 6,",
        "\t-- Bounds centre of every mesh, compared with the imported parts to",
        "\t-- detect how the importer oriented the city (it turns it 180 degrees).",
        "\tMeshCenters = table.freeze({",
    ] + [
        "\t\t[%s] = %s," % (json.dumps(gltf["meshes"][i]["name"]), v3([(lo + hi) / 2 for lo, hi in zip(*bounds[i])]))
        for i in range(len(bounds))
    ] + [
        "\t}),",
        "\tBoundsMin = %s," % v3([min_x, 0, min_z]),
        "\tBoundsMax = %s," % v3([max_x, 7, max_z]),
        "\t-- kind: solid (colour + material), emissive (glow colour), textured (keep TextureID).",
        "\tPieces = table.freeze({",
    ]
    for piece in pieces:
        fields = ["kind = %s" % json.dumps(piece["kind"]), "color = Color3.fromRGB(%d, %d, %d)" % tuple(piece["color"])]
        if "material" in piece:
            fields.append("material = Enum.Material.%s" % piece["material"])
        # Keyed by the MeshPart name and by its parent model's (node) name.
        for key in (piece["mesh"], piece["node"]):
            lines.append("\t\t[%s] = table.freeze({ %s })," % (json.dumps(key), ", ".join(fields)))
    lines += ["\t}),", "\t-- { centerX, centerY, centerZ, sizeX, sizeY, sizeZ }", "\tColliders = table.freeze({"]
    for box in boxes:
        lines.append("\t\t{ %s }," % ", ".join("%.3f" % v for v in box))
    lines += ["\t}),", "\t-- Thin surfaces: roads, sidewalks, ramps, roofs and bridges.", "\tSurfaceColliders = table.freeze({"]
    for box in surface_boxes:
        lines.append("\t\t{ %s }," % ", ".join("%.3f" % v for v in box))
    lines += ["\t}),", "\t-- Open street spots (X, Z) on the floor.", "\tSpawns = table.freeze({"]
    for x, z in spawns:
        lines.append("\t\tVector3.new(%.3f, %.4f, %.3f)," % (x, FLOOR_Y, z))
    lines += ["\t}),", "})", ""]
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    with open(report_path, "w") as f:
        json.dump({
            "cell_glb": CELL,
            "cell_world_at_scale_72": CELL * 72,
            "cells": [rows, columns],
            "boxes": len(boxes),
            "surface_boxes": len(surface_boxes),
            "total_boxes": len(boxes) + len(surface_boxes),
            "passes": passes,
            "open_cells": len(open_cells),
            "spawns": spawns,
        }, f, indent=1)


try:
    main()
except Exception:
    args = sys.argv[sys.argv.index("--") + 1:]
    with open(args[2] + ".error.txt", "w") as f:
        f.write(traceback.format_exc())
    raise
