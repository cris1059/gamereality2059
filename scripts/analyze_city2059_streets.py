import json
import math
import os
import struct
import sys
import zlib

# Exploration helper for the street network: rasterises the City2059 GLB top
# down and writes PNG maps plus per-mesh statistics, so the street detection
# in build_city2059_streets.py can be checked by eye.
# Plain Python 3 (no bpy):
#   python analyze_city2059_streets.py <city.glb> <City2059Data.luau> <out_dir>

CELL = 0.025      # GLB units per cell (1.5 studs at scale 60)
FLOOR_Y = 0.13
BAND = 0.10       # street layer: up-facing surfaces up to FLOOR_Y + BAND
UP = 0.65         # |normal.y| for a walkable (up-facing) triangle


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    json_len = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + json_len])
    return gltf, data, 20 + json_len + 8


def accessor(gltf, data, bin_start, index):
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    offset = bin_start + view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[acc["type"]]
    fmt = {5126: "f", 5125: "I", 5123: "H"}[acc["componentType"]]
    return struct.unpack_from("<%d%s" % (acc["count"] * width, fmt), data, offset)


def write_png(path, width, height, pixels):
    """pixels: bytearray of RGB rows (top row first)."""
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw += pixels[y * width * 3:(y + 1) * width * 3]

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))


def load_colliders(path):
    boxes = []
    inside = False
    with open(path, encoding="utf-8") as f:
        for line in f:
            if "Colliders = table.freeze({" in line and "Surface" not in line:
                inside = True
                continue
            if inside:
                if line.strip().startswith("})"):
                    break
                values = [float(v) for v in line.strip().strip("{},").split(",")]
                boxes.append(values)
    return boxes


def main():
    glb_path, data_path, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(out_dir, exist_ok=True)
    gltf, data, bin_start = read_glb(glb_path)

    meshes = []
    min_x = min_z = 1e9
    max_x = max_z = -1e9
    for mesh_index, mesh in enumerate(gltf["meshes"]):
        primitive = mesh["primitives"][0]
        acc = gltf["accessors"][primitive["attributes"]["POSITION"]]
        min_x = min(min_x, acc["min"][0]); max_x = max(max_x, acc["max"][0])
        min_z = min(min_z, acc["min"][2]); max_z = max(max_z, acc["max"][2])
        material = gltf["materials"][primitive["material"]]
        pbr = material.get("pbrMetallicRoughness", {})
        meshes.append({
            "index": mesh_index,
            "name": mesh["name"],
            "material": material.get("name"),
            "textured": "baseColorTexture" in pbr,
            "base": pbr.get("baseColorFactor"),
            "emissive": material.get("emissiveFactor"),
            "min": acc["min"], "max": acc["max"],
            "positions": accessor(gltf, data, bin_start, primitive["attributes"]["POSITION"]),
            "indices": accessor(gltf, data, bin_start, primitive["indices"]),
        })

    columns = int(math.ceil((max_x - min_x) / CELL)) + 1
    rows = int(math.ceil((max_z - min_z) / CELL)) + 1
    n = rows * columns
    top_h = [-1.0] * n
    top_m = [-1] * n
    street_h = [-1.0] * n
    street_m = [-1] * n
    stats = {m["index"]: {"tris": 0, "street_area": 0.0, "raised_area": 0.0, "level_area": 0.0} for m in meshes}

    for mesh in meshes:
        pos, idx, mi = mesh["positions"], mesh["indices"], mesh["index"]
        for t in range(0, len(idx), 3):
            a = pos[3 * idx[t]:3 * idx[t] + 3]
            b = pos[3 * idx[t + 1]:3 * idx[t + 1] + 3]
            c = pos[3 * idx[t + 2]:3 * idx[t + 2] + 3]
            stats[mi]["tris"] += 1
            ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
            vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
            nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            length = math.sqrt(nx * nx + ny * ny + nz * nz)
            area = (b[0] - a[0]) * (c[2] - a[2]) - (c[0] - a[0]) * (b[2] - a[2])
            if abs(area) < 1e-10 or length < 1e-12:
                continue
            up = abs(ny) / length >= UP
            in_band = up and max(a[1], b[1], c[1]) <= FLOOR_Y + BAND and min(a[1], b[1], c[1]) >= FLOOR_Y - 0.03
            if in_band:
                mean = (a[1] + b[1] + c[1]) / 3
                key = "level_area" if mean - FLOOR_Y < 0.01 else "raised_area"
                stats[mi][key] += abs(area) / 2
                stats[mi]["street_area"] += abs(area) / 2
            c0 = max(0, int((min(a[0], b[0], c[0]) - min_x) / CELL)); c1 = min(columns - 1, int((max(a[0], b[0], c[0]) - min_x) / CELL))
            r0 = max(0, int((min(a[2], b[2], c[2]) - min_z) / CELL)); r1 = min(rows - 1, int((max(a[2], b[2], c[2]) - min_z) / CELL))
            for r in range(r0, r1 + 1):
                pz = min_z + (r + 0.5) * CELL
                for col in range(c0, c1 + 1):
                    px = min_x + (col + 0.5) * CELL
                    w0 = ((b[0] - px) * (c[2] - pz) - (c[0] - px) * (b[2] - pz)) / area
                    w1 = ((c[0] - px) * (a[2] - pz) - (a[0] - px) * (c[2] - pz)) / area
                    w2 = 1 - w0 - w1
                    if w0 < -1e-6 or w1 < -1e-6 or w2 < -1e-6:
                        continue
                    h = w0 * a[1] + w1 * b[1] + w2 * c[1]
                    k = r * columns + col
                    if h > top_h[k]:
                        top_h[k] = h
                        top_m[k] = mi
                    if in_band and h > street_h[k]:
                        street_h[k] = h
                        street_m[k] = mi

    blocked = [False] * n
    for box in load_colliders(data_path):
        cx, cy, cz, sx, sy, sz = box
        if cy + sy / 2 <= FLOOR_Y + 0.04:
            continue
        c0 = max(0, int((cx - sx / 2 - min_x) / CELL)); c1 = min(columns - 1, int((cx + sx / 2 - min_x) / CELL))
        r0 = max(0, int((cz - sz / 2 - min_z) / CELL)); r1 = min(rows - 1, int((cz + sz / 2 - min_z) / CELL))
        for r in range(r0, r1 + 1):
            for col in range(c0, c1 + 1):
                blocked[r * columns + col] = True

    palette = [
        (230, 25, 75), (60, 180, 75), (255, 225, 25), (0, 130, 200), (245, 130, 48), (145, 30, 180),
        (70, 240, 240), (240, 50, 230), (210, 245, 60), (250, 190, 212), (0, 128, 128), (220, 190, 255),
        (170, 110, 40), (255, 250, 200), (128, 0, 0), (170, 255, 195), (128, 128, 0), (255, 215, 180),
        (0, 0, 128), (128, 128, 128), (255, 255, 255), (100, 100, 255), (255, 100, 100), (100, 255, 100),
        (200, 200, 0), (0, 200, 200), (200, 0, 200), (90, 60, 30), (30, 90, 60), (60, 30, 90), (150, 150, 60),
    ]
    max_top = max(top_h)

    # 1) Height view of the visible top surface (hillshade-ish grey ramp).
    pixels = bytearray(n * 3)
    for k in range(n):
        h = top_h[k]
        v = 0 if h < 0 else int(40 + 215 * min(1.0, max(0.0, (h - FLOOR_Y) / (max_top - FLOOR_Y)) ** 0.5))
        pixels[3 * k:3 * k + 3] = bytes((v, v, v))
    write_png(os.path.join(out_dir, "top_height.png"), columns, rows, pixels)

    # 2) Street layer by mesh; raised parts darker; blocked cells dark red.
    pixels = bytearray(n * 3)
    for k in range(n):
        if blocked[k]:
            color = (70, 0, 0)
        elif street_m[k] >= 0:
            base = palette[street_m[k] % len(palette)]
            factor = 1.0 if street_h[k] - FLOOR_Y < 0.01 else 0.45
            color = tuple(int(v * factor) for v in base)
        else:
            color = (0, 0, 0)
        pixels[3 * k:3 * k + 3] = bytes(color)
    write_png(os.path.join(out_dir, "street_layer.png"), columns, rows, pixels)

    # 3) Street height classes: level (white), raised (blue ramp), none (black).
    pixels = bytearray(n * 3)
    for k in range(n):
        if blocked[k]:
            color = (90, 0, 0)
        elif street_m[k] < 0:
            color = (0, 0, 0)
        else:
            rise = street_h[k] - FLOOR_Y
            if rise < 0.01:
                color = (235, 235, 235)
            else:
                t = min(1.0, rise / BAND)
                color = (0, int(80 + 120 * (1 - t)), int(150 + 105 * t))
        pixels[3 * k:3 * k + 3] = bytes(color)
    write_png(os.path.join(out_dir, "street_height.png"), columns, rows, pixels)

    legend = []
    for mesh in meshes:
        s = stats[mesh["index"]]
        legend.append({
            "index": mesh["index"], "name": mesh["name"], "material": mesh["material"],
            "palette": palette[mesh["index"] % len(palette)], "textured": mesh["textured"],
            "base": mesh["base"], "emissive": mesh["emissive"], "tris": s["tris"],
            "level_area": round(s["level_area"], 3), "raised_area": round(s["raised_area"], 3),
            "min_y": round(mesh["min"][1], 4), "max_y": round(mesh["max"][1], 4),
        })
    with open(os.path.join(out_dir, "meshes.json"), "w") as f:
        json.dump({"rows": rows, "columns": columns, "min_x": min_x, "min_z": min_z, "cell": CELL, "meshes": legend}, f, indent=1)
    print("done", rows, columns)


main()
