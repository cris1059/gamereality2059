import json
import math
import struct
import sys
import traceback

# Finds every tower of City2059 and its large flat walls, for the per-building
# dressing (billboard screens, neon edge strips, rooftop signs) placed by
# CityDressingService. All towers share one mesh per material, so a texture
# alone cannot tell them apart; dressing anchored to each tower's own walls
# can. Output: src/server/World/City2059Dressing.luau (glTF coordinates).
# Plain Python (no bpy):
#   blender -b --python build_city2059_dressing.py -- <city.glb> <out.luau> <report.json>

TOWER_MESHES = (7, 19, 20, 22)   # Cuberpunk2077.009, .021, .022, .024
MIN_TOWER_HEIGHT = 1.2           # glTF units (~72 studs at scale 60)
WALL_MIN_WIDTH = 0.16            # ~10 studs
WALL_MIN_HEIGHT = 0.45           # ~27 studs
WALL_MIN_FILL = 0.75             # covered fraction of the wall rectangle
NORMAL_STEP = math.radians(3)
PLANE_STEP = 0.01


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    json_len = struct.unpack_from("<I", data, 12)[0]
    return json.loads(data[20:20 + json_len]), data, 20 + json_len + 8


def accessor(gltf, data, bin_start, index):
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    offset = bin_start + view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[acc["type"]]
    fmt = {5126: "f", 5125: "I", 5123: "H"}[acc["componentType"]]
    return struct.unpack_from("<%d%s" % (acc["count"] * width, fmt), data, offset)


class UnionFind:
    def __init__(self, n):
        self.parent = list(range(n))

    def find(self, x):
        while self.parent[x] != x:
            self.parent[x] = self.parent[self.parent[x]]
            x = self.parent[x]
        return x

    def union(self, a, b):
        self.parent[self.find(a)] = self.find(b)


def trim_occluded(wall, walls):
    """Keeps the tallest part of a wall that no other wall of the same tower
    covers from the front (an overhanging upper section, for example)."""
    nx, nz = wall["n"]
    tx, tz = -nz, nx
    intervals = [wall["y"]]
    for other in walls:
        if other is wall or other["n"][0] * nx + other["n"][1] * nz < 0.99:
            continue
        # Other wall's offset measured along this wall's normal.
        ox, oz = other["c"][0], other["c"][2]
        if ox * nx + oz * nz <= wall["d"] + 0.005:
            continue
        ot = ox * tx + oz * tz
        o0, o1 = ot - other["w"] / 2, ot + other["w"] / 2
        overlap = min(o1, wall["t"][1]) - max(o0, wall["t"][0])
        if overlap < 0.5 * wall["w"]:
            continue
        y0, y1 = other["y"]
        trimmed = []
        for a, b in intervals:
            if y1 <= a or y0 >= b:
                trimmed.append((a, b))
                continue
            if y0 > a:
                trimmed.append((a, y0))
            if y1 < b:
                trimmed.append((y1, b))
        intervals = trimmed
    if not intervals:
        return None
    a, b = max(intervals, key=lambda iv: iv[1] - iv[0])
    if b - a < WALL_MIN_HEIGHT:
        return None
    result = dict(wall)
    result["y"] = (a, b)
    result["h"] = b - a
    result["c"] = (wall["c"][0], (a + b) / 2, wall["c"][2])
    return result


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    glb_path, out_path, report_path = args
    gltf, data, bin_start = read_glb(glb_path)

    # 1. Tower triangles, grouped into connected pieces.
    triangles = []
    for mesh_index in TOWER_MESHES:
        primitive = gltf["meshes"][mesh_index]["primitives"][0]
        positions = accessor(gltf, data, bin_start, primitive["attributes"]["POSITION"])
        indices = accessor(gltf, data, bin_start, primitive["indices"])
        for t in range(0, len(indices), 3):
            triangles.append([tuple(positions[3 * indices[t + k]:3 * indices[t + k] + 3]) for k in range(3)])
    vertex_ids = {}
    uf = UnionFind(len(triangles) * 3)
    tri_vertex = []
    for t, tri in enumerate(triangles):
        ids = []
        for p in tri:
            key = (round(p[0], 4), round(p[1], 4), round(p[2], 4))
            ids.append(vertex_ids.setdefault(key, len(vertex_ids)))
        tri_vertex.append(ids)
    uf = UnionFind(len(vertex_ids))
    for ids in tri_vertex:
        uf.union(ids[0], ids[1])
        uf.union(ids[1], ids[2])
    pieces = {}
    for t, ids in enumerate(tri_vertex):
        pieces.setdefault(uf.find(ids[0]), []).append(t)

    # 2. Buildings: pieces whose footprints overlap (stacked sections, roofs).
    piece_list = []
    for tris in pieces.values():
        xs = [p[0] for t in tris for p in triangles[t]]
        ys = [p[1] for t in tris for p in triangles[t]]
        zs = [p[2] for t in tris for p in triangles[t]]
        piece_list.append({"tris": tris, "box": (min(xs), max(xs), min(zs), max(zs)), "y": (min(ys), max(ys))})
    buf = UnionFind(len(piece_list))
    for i, a in enumerate(piece_list):
        for j in range(i + 1, len(piece_list)):
            b = piece_list[j]
            ax0, ax1, az0, az1 = a["box"]
            bx0, bx1, bz0, bz1 = b["box"]
            overlap_x = min(ax1, bx1) - max(ax0, bx0)
            overlap_z = min(az1, bz1) - max(az0, bz0)
            small = min((ax1 - ax0) * (az1 - az0), (bx1 - bx0) * (bz1 - bz0))
            if overlap_x > 0 and overlap_z > 0 and overlap_x * overlap_z > 0.3 * small:
                buf.union(i, j)
    groups = {}
    for i, piece in enumerate(piece_list):
        groups.setdefault(buf.find(i), []).append(piece)

    buildings = []
    for members in groups.values():
        y0 = min(p["y"][0] for p in members)
        y1 = max(p["y"][1] for p in members)
        if y1 - max(y0, 0.13) < MIN_TOWER_HEIGHT:
            continue
        x0 = min(p["box"][0] for p in members); x1 = max(p["box"][1] for p in members)
        z0 = min(p["box"][2] for p in members); z1 = max(p["box"][3] for p in members)

        # 3. Large flat walls: coplanar vertical triangles, merged per plane.
        planes = {}
        for piece in members:
            for t in piece["tris"]:
                a, b, c = triangles[t]
                ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
                vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
                nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
                length = math.sqrt(nx * nx + ny * ny + nz * nz)
                if length < 1e-9 or abs(ny / length) > 0.08:
                    continue
                nx, nz = nx / length, nz / length
                horizontal = math.hypot(nx, nz)
                nx, nz = nx / horizontal, nz / horizontal
                angle = round(math.atan2(nz, nx) / NORMAL_STEP)
                offset = round((a[0] * nx + a[2] * nz) / PLANE_STEP)
                entry = planes.setdefault((angle, offset), {"n": [0.0, 0.0], "area": 0.0, "pts": []})
                entry["n"][0] += nx * length
                entry["n"][1] += nz * length
                entry["area"] += length / 2
                entry["pts"].extend((a, b, c))
        walls = []
        for entry in planes.values():
            nx, nz = entry["n"]
            norm = math.hypot(nx, nz)
            if norm < 1e-9:
                continue
            nx, nz = nx / norm, nz / norm
            tx, tz = -nz, nx  # along the wall, horizontal
            ts = [p[0] * tx + p[2] * tz for p in entry["pts"]]
            ys = [p[1] for p in entry["pts"]]
            ds = [p[0] * nx + p[2] * nz for p in entry["pts"]]
            width, height = max(ts) - min(ts), max(ys) - min(ys)
            if width < WALL_MIN_WIDTH or height < WALL_MIN_HEIGHT:
                continue
            fill = entry["area"] / (width * height)
            if fill < WALL_MIN_FILL:
                continue
            tc, yc, d = (max(ts) + min(ts)) / 2, (max(ys) + min(ys)) / 2, sum(ds) / len(ds)
            cx, cz = tx * tc + nx * d, tz * tc + nz * d
            # Face outward: away from the tower's footprint centre.
            if (cx - (x0 + x1) / 2) * nx + (cz - (z0 + z1) / 2) * nz < 0:
                nx, nz = -nx, -nz
            walls.append({"c": (cx, yc, cz), "n": (nx, nz), "w": width, "h": height, "fill": min(fill, 1.0),
                          "t": (min(ts), max(ts)), "y": (min(ys), max(ys)), "d": cx * nx + cz * nz})
        walls = [w for w in (trim_occluded(w, walls) for w in walls) if w]
        walls.sort(key=lambda w: -w["w"] * w["h"])
        if not walls:
            continue
        buildings.append({
            "center": ((x0 + x1) / 2, (z0 + z1) / 2),
            "size": (x1 - x0, z1 - z0),
            "base": max(y0, 0.13), "top": y1,
            "walls": walls[:6],
        })
    buildings.sort(key=lambda b: (round(b["center"][0], 2), round(b["center"][1], 2)))

    lines = [
        "--!strict", "",
        "-- GENERATED by scripts/build_city2059_dressing.py from the City2059 GLB.",
        "-- Towers and their largest flat walls in glTF units (see CityDressingService).",
        "-- wall: { centerX, centerY, centerZ, normalX, normalZ, width, height }", "",
        "return table.freeze({",
    ]
    for b in buildings:
        lines.append("\ttable.freeze({")
        lines.append("\t\tcenter = Vector3.new(%.4f, %.4f, %.4f)," % (b["center"][0], b["base"], b["center"][1]))
        lines.append("\t\tsize = Vector3.new(%.4f, %.4f, %.4f)," % (b["size"][0], b["top"] - b["base"], b["size"][1]))
        lines.append("\t\ttop = %.4f," % b["top"])
        lines.append("\t\twalls = table.freeze({")
        for w in b["walls"]:
            lines.append("\t\t\t{ %.4f, %.4f, %.4f, %.4f, %.4f, %.4f, %.4f }," % (w["c"][0], w["c"][1], w["c"][2], w["n"][0], w["n"][1], w["w"], w["h"]))
        lines.append("\t\t}),")
        lines.append("\t}),")
    lines += ["})", ""]
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    with open(report_path, "w") as f:
        json.dump({"buildings": len(buildings), "walls": sum(len(b["walls"]) for b in buildings),
                   "detail": [{"center": b["center"], "height": b["top"] - b["base"], "walls": [(round(w["w"], 2), round(w["h"], 2), round(w["fill"], 2)) for w in b["walls"]]} for b in buildings]}, f, indent=1)


try:
    main()
except Exception:
    args = sys.argv[sys.argv.index("--") + 1:]
    with open(args[2] + ".error.txt", "w") as f:
        f.write(traceback.format_exc())
    raise
