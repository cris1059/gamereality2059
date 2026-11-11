import json
import math
import os
import struct
import sys
import zlib

# Builds src/shared/World/City2059Streets.luau: the drivable street network of
# City2059 for the ambient traffic and the sidewalk network for pedestrians,
# detected from the real geometry instead of guessed from open space.
#
#   * Roads: the up-facing triangles of the asphalt mesh (Cuberpunk2077.005)
#     at street level, minus building footprints (the collision boxes).
#   * Centre lines: the road mask thinned to one cell (Zhang-Suen), turned
#     into a graph of junctions and street segments; short spurs pruned.
#   * Lanes: right-hand traffic, offset from the centre line by the measured
#     road width, trimmed at junctions; junction curves (cubic Bezier) are kept
#     only if every sample stays on the asphalt. The central roundabout is
#     detected (round island) and made one-way counter-clockwise.
#   * Sidewalks: the raised block surface (Cuberpunk2077.003) a few studs in
#     from the curb, thinned the same way; crosswalks join sidewalks across a
#     road next to its junctions.
# Debug PNGs are written next to the output so every stage can be checked.
#
# Plain Python 3 (no bpy):
#   python build_city2059_streets.py <city.glb> <City2059Data.luau> <out.luau> <debug_dir>

CELL = 0.025            # GLB units per cell (1.5 studs at scale 60)
SCALE = 60.0            # studs per GLB unit (FreeRoamConfig.CityScale)
FLOOR_Y = 0.13
BAND = 0.10             # street layer: up-facing surfaces up to FLOOR_Y + BAND
UP = 0.65
ROAD_MESH = "Cuberpunk2077.005"
SIDEWALK_MESH = "Cuberpunk2077.003"
HOLE_FILL_CELLS = 40    # non-road specks inside the road (poles, decals)
POST_CELLS = 8          # obstacles up to this size do not push lanes aside
MIN_ROAD_CELLS = 400    # drop isolated asphalt pieces
SPUR_STUDS = 45         # skeleton branches shorter than this from a dead end


def studs(units):
    return units * SCALE


# ---------------------------------------------------------------- GLB / PNG --

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
    boxes, inside = [], False
    with open(path, encoding="utf-8") as f:
        for line in f:
            if "Colliders = table.freeze({" in line and "Surface" not in line:
                inside = True
                continue
            if inside:
                if line.strip().startswith("})"):
                    break
                boxes.append([float(v) for v in line.strip().strip("{},").split(",")])
    return boxes


# --------------------------------------------------------------- raster ----

class Grid:
    def __init__(self, min_x, min_z, columns, rows):
        self.min_x, self.min_z, self.columns, self.rows = min_x, min_z, columns, rows
        self.n = columns * rows

    def center(self, k):
        r, c = divmod(k, self.columns)
        return self.min_x + (c + 0.5) * CELL, self.min_z + (r + 0.5) * CELL

    def cell_of(self, x, z):
        c = int((x - self.min_x) / CELL)
        r = int((z - self.min_z) / CELL)
        if 0 <= r < self.rows and 0 <= c < self.columns:
            return r * self.columns + c
        return -1


def rasterize(glb_path, data_path):
    gltf, data, bin_start = read_glb(glb_path)
    meshes = []
    min_x = min_z = 1e9
    max_x = max_z = -1e9
    for mesh in gltf["meshes"]:
        primitive = mesh["primitives"][0]
        acc = gltf["accessors"][primitive["attributes"]["POSITION"]]
        min_x = min(min_x, acc["min"][0]); max_x = max(max_x, acc["max"][0])
        min_z = min(min_z, acc["min"][2]); max_z = max(max_z, acc["max"][2])
        meshes.append((mesh["name"], accessor(gltf, data, bin_start, primitive["attributes"]["POSITION"]),
                       accessor(gltf, data, bin_start, primitive["indices"])))
    # One empty cell of margin all round keeps the thinning away from edges.
    min_x -= CELL; min_z -= CELL
    grid = Grid(min_x, min_z, int(math.ceil((max_x - min_x) / CELL)) + 2, int(math.ceil((max_z - min_z) / CELL)) + 2)
    columns, rows, n = grid.columns, grid.rows, grid.n
    top_h = [FLOOR_Y] * n
    street_h = [-1.0] * n
    street_m = [""] * n
    for name, pos, idx in meshes:
        for t in range(0, len(idx), 3):
            a = pos[3 * idx[t]:3 * idx[t] + 3]
            b = pos[3 * idx[t + 1]:3 * idx[t + 1] + 3]
            c = pos[3 * idx[t + 2]:3 * idx[t + 2] + 3]
            ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
            vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
            nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            length = math.sqrt(nx * nx + ny * ny + nz * nz)
            area = (b[0] - a[0]) * (c[2] - a[2]) - (c[0] - a[0]) * (b[2] - a[2])
            if abs(area) < 1e-10 or length < 1e-12:
                continue
            in_band = abs(ny) / length >= UP and max(a[1], b[1], c[1]) <= FLOOR_Y + BAND and min(a[1], b[1], c[1]) >= FLOOR_Y - 0.03
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
                    if in_band and h > street_h[k]:
                        street_h[k] = h
                        street_m[k] = name
    blocked = bytearray(n)
    for cx, cy, cz, sx, sy, sz in load_colliders(data_path):
        if cy + sy / 2 <= FLOOR_Y + 0.04:
            continue
        c0 = max(0, int((cx - sx / 2 - min_x) / CELL)); c1 = min(columns - 1, int((cx + sx / 2 - min_x) / CELL))
        r0 = max(0, int((cz - sz / 2 - min_z) / CELL)); r1 = min(rows - 1, int((cz + sz / 2 - min_z) / CELL))
        for r in range(r0, r1 + 1):
            for col in range(c0, c1 + 1):
                blocked[r * columns + col] = 1
    return grid, top_h, street_h, street_m, blocked


# ------------------------------------------------------------- mask tools --

def neighbours4(grid, k):
    columns = grid.columns
    r, c = divmod(k, columns)
    if r > 0:
        yield k - columns
    if r < grid.rows - 1:
        yield k + columns
    if c > 0:
        yield k - 1
    if c < columns - 1:
        yield k + 1


def components(grid, mask, value):
    """4-connected components of cells where mask[k] == value."""
    seen = bytearray(grid.n)
    result = []
    for start in range(grid.n):
        if mask[start] != value or seen[start]:
            continue
        stack, cells = [start], []
        seen[start] = 1
        while stack:
            k = stack.pop()
            cells.append(k)
            for m in neighbours4(grid, k):
                if mask[m] == value and not seen[m]:
                    seen[m] = 1
                    stack.append(m)
        result.append(cells)
    return result


def touches_border(grid, cells):
    for k in cells:
        r, c = divmod(k, grid.columns)
        if r == 0 or c == 0 or r == grid.rows - 1 or c == grid.columns - 1:
            return True
    return False


def chamfer(grid, mask):
    """Distance (cells) from each mask cell to the nearest non-mask cell."""
    columns, rows = grid.columns, grid.rows
    big = 10 ** 9
    d = [0 if not mask[k] else big for k in range(grid.n)]
    for r in range(rows):
        for c in range(columns):
            k = r * columns + c
            if d[k] == 0:
                continue
            best = d[k]
            if c > 0: best = min(best, d[k - 1] + 3)
            if r > 0:
                best = min(best, d[k - columns] + 3)
                if c > 0: best = min(best, d[k - columns - 1] + 4)
                if c < columns - 1: best = min(best, d[k - columns + 1] + 4)
            d[k] = best
    for r in range(rows - 1, -1, -1):
        for c in range(columns - 1, -1, -1):
            k = r * columns + c
            if d[k] == 0:
                continue
            best = d[k]
            if c < columns - 1: best = min(best, d[k + 1] + 3)
            if r < rows - 1:
                best = min(best, d[k + columns] + 3)
                if c < columns - 1: best = min(best, d[k + columns + 1] + 4)
                if c > 0: best = min(best, d[k + columns - 1] + 4)
            d[k] = best
    return [v / 3.0 for v in d]


def thin(grid, mask):
    """Zhang-Suen thinning; mask border cells must be 0."""
    columns = grid.columns
    img = bytearray(mask)
    alive = [k for k in range(grid.n) if img[k]]
    while True:
        changed = False
        for step in (0, 1):
            remove = []
            for k in alive:
                if not img[k]:
                    continue
                p2 = img[k - columns]; p3 = img[k - columns + 1]; p4 = img[k + 1]; p5 = img[k + columns + 1]
                p6 = img[k + columns]; p7 = img[k + columns - 1]; p8 = img[k - 1]; p9 = img[k - columns - 1]
                count = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9
                if count < 2 or count > 6:
                    continue
                seq = (p2, p3, p4, p5, p6, p7, p8, p9, p2)
                transitions = sum(1 for i in range(8) if seq[i] == 0 and seq[i + 1] == 1)
                if transitions != 1:
                    continue
                if step == 0:
                    if p2 * p4 * p6 or p4 * p6 * p8:
                        continue
                else:
                    if p2 * p4 * p8 or p2 * p6 * p8:
                        continue
                remove.append(k)
            for k in remove:
                img[k] = 0
            if remove:
                changed = True
        alive = [k for k in alive if img[k]]
        if not changed:
            return img


def neighbours8(grid, k):
    columns = grid.columns
    return (k - columns - 1, k - columns, k - columns + 1, k - 1, k + 1, k + columns - 1, k + columns, k + columns + 1)


def clean_skeleton(grid, skel):
    """Zhang-Suen leaves staircases on diagonal roads, where every pixel has
    three neighbours and would read as a junction. A pixel whose neighbours
    stay connected to each other without it is redundant: removing all of
    them (one at a time) leaves a minimal 8-connected line."""
    columns = grid.columns

    def connected(cells):
        first = cells[0]
        seen = {first}
        stack = [first]
        while stack:
            cur = stack.pop()
            cr, cc = divmod(cur, columns)
            for other in cells:
                if other not in seen:
                    orr, oc = divmod(other, columns)
                    if abs(orr - cr) <= 1 and abs(oc - cc) <= 1:
                        seen.add(other)
                        stack.append(other)
        return len(seen) == len(cells)

    changed = True
    while changed:
        changed = False
        for k in range(grid.n):
            if not skel[k]:
                continue
            around = [m for m in neighbours8(grid, k) if skel[m]]
            if len(around) >= 2 and connected(around):
                skel[k] = 0
                changed = True
    return skel


# ------------------------------------------------------------ skeleton graph --

def skeleton_graph(grid, skel):
    """Nodes (junction clusters and dead ends) and edges (cell paths)."""
    degree = {}
    for k in range(grid.n):
        if skel[k]:
            degree[k] = sum(1 for m in neighbours8(grid, k) if skel[m])
    special = {k for k, d in degree.items() if d != 2}
    # Junction cells close together form one node.
    node_of = {}
    nodes = []
    for k in special:
        if k in node_of:
            continue
        stack, cluster = [k], []
        node_of[k] = len(nodes)
        while stack:
            cur = stack.pop()
            cluster.append(cur)
            for m in neighbours8(grid, cur):
                if m in special and m not in node_of:
                    node_of[m] = len(nodes)
                    stack.append(m)
        nodes.append(cluster)
    edges = []
    used = set()
    for index, cluster in enumerate(nodes):
        for start_cell in cluster:
            for first in neighbours8(grid, start_cell):
                if not skel[first] or first in node_of or first in used:
                    continue
                path = [start_cell, first]
                used.add(first)
                prev, cur = start_cell, first
                end_node = None
                while True:
                    nxt = None
                    for m in neighbours8(grid, cur):
                        if m == prev or not skel[m]:
                            continue
                        if m in node_of and node_of[m] != index or (m in node_of and len(path) > 2):
                            nxt = m
                            break
                        if m not in used and m not in node_of:
                            nxt = m
                    if nxt is None:
                        break
                    path.append(nxt)
                    if nxt in node_of:
                        end_node = node_of[nxt]
                        break
                    used.add(nxt)
                    prev, cur = cur, nxt
                if end_node is not None:
                    edges.append([index, end_node, path])
    # Pure loops (no junction): give each one a node.
    for k in range(grid.n):
        if skel[k] and k not in node_of and k not in used:
            node_of[k] = len(nodes)
            nodes.append([k])
            index = node_of[k]
            path = [k]
            prev, cur = None, k
            while True:
                nxt = None
                for m in neighbours8(grid, cur):
                    if m != prev and skel[m] and m not in used and m != k:
                        nxt = m
                        break
                if nxt is None:
                    break
                used.add(nxt)
                path.append(nxt)
                prev, cur = cur, nxt
            path.append(k)
            edges.append([index, index, path])
    return nodes, edges


def node_center(grid, cluster):
    xs = [grid.center(k) for k in cluster]
    return sum(p[0] for p in xs) / len(xs), sum(p[1] for p in xs) / len(xs)


def path_length(grid, path):
    total = 0.0
    for i in range(1, len(path)):
        ax, az = grid.center(path[i - 1]); bx, bz = grid.center(path[i])
        total += math.hypot(bx - ax, bz - az)
    return total


def prune_and_merge(grid, nodes, edges, dist):
    """Removes short dead-end spurs and merges nodes left with two edges."""
    alive = [True] * len(nodes)
    changed = True
    while changed:
        changed = False
        deg = [0] * len(nodes)
        for a, b, _ in edges:
            deg[a] += 1
            deg[b] += 1
        keep = []
        for edge in edges:
            a, b, path = edge
            dead_a, dead_b = deg[a] == 1, deg[b] == 1
            if a != b and (dead_a or dead_b) and not (dead_a and dead_b):
                junction = b if dead_a else a
                width = max(dist[k] for k in nodes[junction]) * CELL
                if studs(path_length(grid, path)) < max(SPUR_STUDS, studs(width) * 3.0):
                    changed = True
                    alive[a if dead_a else b] = False
                    continue
            keep.append(edge)
        edges = keep
        # Merge pass-through nodes (exactly two distinct edge ends).
        deg = [0] * len(nodes)
        for a, b, _ in edges:
            deg[a] += 1
            deg[b] += 1
        for index in range(len(nodes)):
            if not alive[index] or deg[index] != 2:
                continue
            ends = [e for e in edges if e[0] == index or e[1] == index]
            if len(ends) != 2 or ends[0] is ends[1]:
                continue
            e1, e2 = ends
            p1 = e1[2] if e1[1] == index else list(reversed(e1[2]))
            p2 = e2[2] if e2[0] == index else list(reversed(e2[2]))
            start = e1[0] if e1[1] == index else e1[1]
            end = e2[1] if e2[0] == index else e2[0]
            edges.remove(e1)
            edges.remove(e2)
            edges.append([start, end, p1 + p2[1:]])
            alive[index] = False
            changed = True
            break
    used = sorted({a for a, _, _ in edges} | {b for _, b, _ in edges})
    remap = {old: new for new, old in enumerate(used)}
    return [nodes[i] for i in used], [[remap[a], remap[b], p] for a, b, p in edges]


# ----------------------------------------------------------------- debug ---

def paint(pixels, grid, k, color):
    pixels[3 * k:3 * k + 3] = bytes(color)


def dot(pixels, grid, x, z, color, radius=2):
    c0 = int((x - grid.min_x) / CELL); r0 = int((z - grid.min_z) / CELL)
    for r in range(r0 - radius, r0 + radius + 1):
        for c in range(c0 - radius, c0 + radius + 1):
            if 0 <= r < grid.rows and 0 <= c < grid.columns:
                paint(pixels, grid, r * grid.columns + c, color)


def line(pixels, grid, ax, az, bx, bz, color):
    steps = max(1, int(math.hypot(bx - ax, bz - az) / (CELL * 0.4)))
    for s in range(steps + 1):
        f = s / steps
        k = grid.cell_of(ax + (bx - ax) * f, az + (bz - az) * f)
        if k >= 0:
            paint(pixels, grid, k, color)


def base_image(grid, road, sidewalk, blocked):
    pixels = bytearray(grid.n * 3)
    for k in range(grid.n):
        if blocked[k]:
            color = (60, 0, 0)
        elif road[k]:
            color = (45, 45, 55)
        elif sidewalk[k]:
            color = (20, 50, 25)
        else:
            color = (0, 0, 0)
        paint(pixels, grid, k, color)
    return pixels


# ----------------------------------------------------------- polylines ----

CAR_HALF_WIDTH = 3.4      # studs, plus margin: lanes keep this off the curb
# A car's centre line keeps this far from any curb, pillar or post (cars are
# 6.2 studs wide): closer and the body visibly sinks into raised sidewalks.
CAR_CLEAR = 3.6
LANE_SPACING = 2          # cells between resampled polyline points
TWO_LANES_FROM = 14.0     # studs of half width for two lanes per direction


def resample(points, spacing):
    """Even spacing along a polyline of (x, z)."""
    if len(points) < 2:
        return list(points)
    out = [points[0]]
    carry = 0.0
    for i in range(1, len(points)):
        ax, az = points[i - 1]; bx, bz = points[i]
        seg = math.hypot(bx - ax, bz - az)
        pos = spacing - carry
        while pos <= seg:
            f = pos / seg
            out.append((ax + (bx - ax) * f, az + (bz - az) * f))
            pos += spacing
        carry = seg - (pos - spacing)
    if math.hypot(out[-1][0] - points[-1][0], out[-1][1] - points[-1][1]) > spacing * 0.3:
        out.append(points[-1])
    else:
        out[-1] = points[-1]
    return out


def smooth(points, passes=3):
    pts = list(points)
    for _ in range(passes):
        pts = [pts[0]] + [((pts[i - 1][0] + 2 * pts[i][0] + pts[i + 1][0]) / 4, (pts[i - 1][1] + 2 * pts[i][1] + pts[i + 1][1]) / 4)
                          for i in range(1, len(pts) - 1)] + [pts[-1]]
    return pts


def simplify(points, tolerance):
    """Douglas-Peucker on (x, z)."""
    if len(points) < 3:
        return list(points)
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        ax, az = points[a]; bx, bz = points[b]
        dx, dz = bx - ax, bz - az
        length = math.hypot(dx, dz)
        best, index = 0.0, -1
        for i in range(a + 1, b):
            px, pz = points[i]
            # Closed loops start and end on the same point: measure from it.
            if length < 1e-9:
                d = math.hypot(px - ax, pz - az)
            else:
                d = abs((px - ax) * dz - (pz - az) * dx) / length
            if d > best:
                best, index = d, i
        if best > tolerance and index > 0:
            keep[index] = True
            stack.append((a, index))
            stack.append((index, b))
    return [p for p, k in zip(points, keep) if k]


def tangents(points):
    result = []
    for i in range(len(points)):
        a = points[max(0, i - 1)]; b = points[min(len(points) - 1, i + 1)]
        dx, dz = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dz) or 1e-9
        result.append((dx / length, dz / length))
    return result


def offset_right(points, distance):
    return offset_right_varying(points, [distance] * len(points))


def offset_right_varying(points, distances):
    """Offset to the right of travel: right = (-tz, tx) for forward (tx, tz)."""
    out = []
    directions = tangents(points)
    for (x, z), (tx, tz), distance in zip(points, directions, distances):
        out.append((x - tz * distance, z + tx * distance))
    # Drop points that fold back on tight inside curves: a step that runs
    # against the centre line's own direction there.
    clean = [out[0]]
    for p, (tx, tz) in zip(out[1:], directions[1:]):
        if (p[0] - clean[-1][0]) * tx + (p[1] - clean[-1][1]) * tz <= 0:
            continue
        clean.append(p)
    return clean


def trim(points, center, radius, at_start):
    """Cuts the part of a polyline within radius of center at one end."""
    pts = points if at_start else list(reversed(points))
    cx, cz = center
    i = 0
    while i < len(pts) - 1 and math.hypot(pts[i + 1][0] - cx, pts[i + 1][1] - cz) < radius:
        i += 1
    if i >= len(pts) - 1:
        return None
    (ax, az), (bx, bz) = pts[i], pts[i + 1]
    da = math.hypot(ax - cx, az - cz)
    if da < radius:
        db = math.hypot(bx - cx, bz - cz)
        f = (radius - da) / max(db - da, 1e-9)
        pts = [(ax + (bx - ax) * f, az + (bz - az) * f)] + pts[i + 1:]
    else:
        pts = pts[i:]
    return pts if at_start else list(reversed(pts))


def polyline_length(points):
    return sum(math.hypot(points[i][0] - points[i - 1][0], points[i][1] - points[i - 1][1]) for i in range(1, len(points)))


def bezier(p0, t0, p3, t3, k):
    chord = math.hypot(p3[0] - p0[0], p3[1] - p0[1])
    d = chord * k
    p1 = (p0[0] + t0[0] * d, p0[1] + t0[1] * d)
    p2 = (p3[0] - t3[0] * d, p3[1] - t3[1] * d)
    steps = max(6, int(chord / (CELL * 1.5)))
    out = []
    for s in range(steps + 1):
        u = s / steps
        a, b, c, e = (1 - u) ** 3, 3 * (1 - u) ** 2 * u, 3 * (1 - u) * u * u, u ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + e * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + e * p3[1]))
    return out


def cross(t, v):
    """> 0 when v points to the right of t (top view, x right, z down)."""
    return t[0] * v[1] - t[1] * v[0]


def main():
    glb_path, data_path, out_path, debug_dir = sys.argv[1:5]
    os.makedirs(debug_dir, exist_ok=True)
    grid, top_h, street_h, street_m, blocked = rasterize(glb_path, data_path)
    n = grid.n

    road = bytearray(1 if street_m[k] == ROAD_MESH and not blocked[k] else 0 for k in range(n))
    # The real drivable area: pillars and posts standing on the asphalt stay
    # holes. Clearances are measured on it.
    true_road = bytearray(road)
    for cells in components(grid, true_road, 0):
        # Thin posts (a couple of cells) are ignored: swerving around every one
        # looks worse than brushing it. Pillars stay obstacles.
        if len(cells) <= POST_CELLS and not touches_border(grid, cells):
            for k in cells:
                true_road[k] = 1
    for cells in components(grid, true_road, 1):
        if len(cells) < MIN_ROAD_CELLS:
            for k in cells:
                true_road[k] = 0
    clear = chamfer(grid, true_road)
    # For the topology only, small holes are filled so the centre lines do not
    # split around every post; isolated asphalt pieces are dropped.
    for cells in components(grid, road, 0):
        if len(cells) <= HOLE_FILL_CELLS and not touches_border(grid, cells):
            for k in cells:
                road[k] = 1
    for cells in components(grid, road, 1):
        if len(cells) < MIN_ROAD_CELLS:
            for k in cells:
                road[k] = 0
    sidewalk = bytearray(1 if street_m[k] == SIDEWALK_MESH and not blocked[k] else 0 for k in range(n))
    dist = chamfer(grid, road)
    skel = clean_skeleton(grid, thin(grid, road))
    nodes, edges = skeleton_graph(grid, skel)
    nodes, edges = prune_and_merge(grid, nodes, edges, dist)
    print("road cells", sum(road), "skeleton cells", sum(skel), "nodes", len(nodes), "edges", len(edges))

    pixels = base_image(grid, road, sidewalk, blocked)
    for k in range(n):
        if skel[k]:
            paint(pixels, grid, k, (90, 90, 110))
    for a, b, path in edges:
        for k in path:
            paint(pixels, grid, k, (255, 210, 0))
    for index, cluster in enumerate(nodes):
        x, z = node_center(grid, cluster)
        dot(pixels, grid, x, z, (255, 40, 60), 3)
    write_png(os.path.join(debug_dir, "1_graph.png"), grid.columns, grid.rows, pixels)

    network = build_network(grid, road, dist, true_road, clear, nodes, edges, street_h, top_h)
    walkways = build_walkways(grid, road, sidewalk, blocked, street_h, network)
    draw_network(grid, road, sidewalk, blocked, network, walkways, debug_dir)
    write_luau(out_path, network, walkways)


def cell_clearance(grid, dist, x, z):
    k = grid.cell_of(x, z)
    return 0.0 if k < 0 else studs(dist[k] * CELL)


def surface_y(grid, street_h, x, z):
    k = grid.cell_of(x, z)
    if k >= 0 and street_h[k] >= 0:
        return street_h[k]
    return FLOOR_Y


def find_roundabouts(grid, road):
    """Islands enclosed by road whose rim is round: (x, z, radius) in units."""
    rings = []
    for cells in components(grid, road, 0):
        if touches_border(grid, cells) or len(cells) < 150:
            continue
        cx = sum(grid.center(k)[0] for k in cells) / len(cells)
        cz = sum(grid.center(k)[1] for k in cells) / len(cells)
        boundary = [k for k in cells if any(road[m] for m in neighbours4(grid, k))]
        radii = [math.hypot(grid.center(k)[0] - cx, grid.center(k)[1] - cz) for k in boundary]
        mean = sum(radii) / len(radii)
        spread = math.sqrt(sum((r - mean) ** 2 for r in radii) / len(radii)) / mean
        if spread < 0.12:
            rings.append((cx, cz, mean))
    return rings


def contract_junctions(grid, dist, nodes, edges, rings):
    """Merges junctions whose areas overlap (one crossing split in two by the
    thinning) and drops small isolated pieces. Junctions on a roundabout are
    never merged: the ring needs every entry as its own node."""
    def on_ring(v):
        x, z = node_center(grid, nodes[v])
        return any(math.hypot(x - cx, z - cz) < r + 45 / SCALE for cx, cz, r in rings)

    def half_width(path):
        middle = path[len(path) // 5: max(len(path) // 5 + 1, 4 * len(path) // 5)]
        values = sorted(dist[k] * CELL for k in middle)
        return values[int(len(values) * 0.3)] if values else 0.0

    while True:
        degree = [0] * len(nodes)
        radius = [0.0] * len(nodes)
        for a, b, path in edges:
            degree[a] += 1
            degree[b] += 1
            half = half_width(path)
            radius[a] = max(radius[a], half * 1.1 + CELL)
            radius[b] = max(radius[b], half * 1.1 + CELL)
        target = None
        for index, (a, b, path) in enumerate(edges):
            if a == b or degree[a] < 3 or degree[b] < 3 or on_ring(a) or on_ring(b):
                continue
            ax, az = node_center(grid, nodes[a]); bx, bz = node_center(grid, nodes[b])
            apart = math.hypot(bx - ax, bz - az)
            if apart < radius[a] + radius[b] + 4 / SCALE and path_length(grid, path) < apart * 1.5 + 2 * CELL:
                target = index
                break
        if target is None:
            break
        a, b, _ = edges.pop(target)
        nodes[a] = nodes[a] + nodes[b]
        edges = [[a if x == b else x, a if y == b else y, p] for x, y, p in edges]
        nodes[b] = []
    # Components made only of dead ends and short streets are leftovers.
    adjacency = {}
    for index, (a, b, path) in enumerate(edges):
        adjacency.setdefault(a, []).append(index)
        adjacency.setdefault(b, []).append(index)
    seen_edges, keep = set(), []
    for start in range(len(edges)):
        if start in seen_edges:
            continue
        stack, group = [start], []
        seen_edges.add(start)
        while stack:
            e = stack.pop()
            group.append(e)
            for v in (edges[e][0], edges[e][1]):
                for f in adjacency[v]:
                    if f not in seen_edges:
                        seen_edges.add(f)
                        stack.append(f)
        total = sum(path_length(grid, edges[e][2]) for e in group)
        if studs(total) >= 150 or len(group) > 3:
            keep.extend(group)
    edges = [edges[e] for e in sorted(keep)]
    used = sorted({a for a, _, _ in edges} | {b for _, b, _ in edges})
    remap = {old: new for new, old in enumerate(used)}
    return [nodes[i] for i in used], [[remap[a], remap[b], p] for a, b, p in edges]


def build_network(grid, road, dist, true_road, clear, nodes, edges, street_h, top_h):
    rings = find_roundabouts(grid, road)
    if os.environ.get("STREETS_DUMP"):
        x0, z0, x1, z1 = (int(v) for v in os.environ["STREETS_DUMP"].split(","))
        for v, cluster in enumerate(nodes):
            x, z = node_center(grid, cluster)
            px, pz = (x - grid.min_x) / CELL, (z - grid.min_z) / CELL
            if x0 <= px <= x1 and z0 <= pz <= z1:
                print("before node", v, "px", int(px), int(pz), "cells", len(cluster))
        for i, (a, b, path) in enumerate(edges):
            ends = [divmod(path[0], grid.columns), divmod(path[-1], grid.columns)]
            if any(x0 <= c <= x1 and z0 <= r <= z1 for r, c in ends):
                print("before edge", i, a, "->", b, "len", len(path), "from px", ends[0][::-1], "to px", ends[1][::-1])
    nodes, edges = contract_junctions(grid, dist, nodes, edges, rings)
    centers = [node_center(grid, cluster) for cluster in nodes]
    degree = [0] * len(nodes)
    for a, b, _ in edges:
        degree[a] += 1
        degree[b] += 1

    # Edge geometry and measured half width (units).
    E = []
    for a, b, path in edges:
        pts = [grid.center(k) for k in path]
        pts[0] = centers[a]
        pts[-1] = centers[b]
        pts = smooth(resample(pts, CELL), 4)
        widths = []
        for x, z in pts[len(pts) // 5: max(len(pts) // 5 + 1, 4 * len(pts) // 5)]:
            k = grid.cell_of(x, z)
            if k >= 0:
                widths.append(dist[k] * CELL)
        widths.sort()
        half = widths[int(len(widths) * 0.3)] if widths else 4 / SCALE
        E.append({"a": a, "b": b, "pts": pts, "half": half, "oneway": False, "ring": False})

    # Ring segments: the middle of the edge follows the roundabout's rim.
    for cx, cz, radius in rings:
        print("roundabout at", round(studs(cx), 1), round(studs(cz), 1), "radius", round(studs(radius), 1), "studs")
        for e in E:
            middle = e["pts"][len(e["pts"]) // 6: max(len(e["pts"]) // 6 + 1, 5 * len(e["pts"]) // 6)]
            near = sum(1 for x, z in middle if abs(math.hypot(x - cx, z - cz) - (radius + e["half"])) < e["half"] * 1.3)
            if near >= 0.8 * len(middle):
                mid = e["pts"][len(e["pts"]) // 2]
                t = tangents(e["pts"])[len(e["pts"]) // 2]
                if cross((mid[0] - cx, mid[1] - cz), t) > 0:
                    e["a"], e["b"], e["pts"] = e["b"], e["a"], list(reversed(e["pts"]))
                e["oneway"] = True
                e["ring"] = True
    # Divided roads: two parallel edges of similar length joining the same two
    # junctions (a median between them) run one way each, keeping right.
    def gap(e, f):
        mid = e["pts"][len(e["pts"]) // 2]
        return min(math.hypot(mid[0] - x, mid[1] - z) for x, z in f["pts"])

    for i, e in enumerate(E):
        for j in range(i + 1, len(E)):
            f = E[j]
            if e["ring"] or f["ring"] or e["a"] == e["b"] or {e["a"], e["b"]} != {f["a"], f["b"]}:
                continue
            le, lf = polyline_length(e["pts"]), polyline_length(f["pts"])
            if max(le, lf) / max(min(le, lf), 1e-9) > 1.35 or gap(e, f) > 4 * max(e["half"], f["half"]):
                continue
            for g in (e, f):
                a, b = centers[g["a"]], centers[g["b"]]
                mid = g["pts"][len(g["pts"]) // 2]
                if cross((b[0] - a[0], b[1] - a[1]), (mid[0] - a[0], mid[1] - a[1])) < 0:
                    g["a"], g["b"], g["pts"] = g["b"], g["a"], list(reversed(g["pts"]))
                g["oneway"] = True

    ring_nodes = {e[k] for e in E if e["ring"] for k in ("a", "b")}
    radius = [0.0] * len(nodes)
    for v in range(len(nodes)):
        incident = [e["half"] for e in E if v in (e["a"], e["b"])]
        if degree[v] >= 3 or v in ring_nodes:
            radius[v] = max(incident) * 1.1 + CELL
        elif degree[v] == 1:
            radius[v] = max(incident) * 0.9

    def clearance_at(x, z):
        """Studs from (x, z) to the nearest curb, pillar or post (0 off-road)."""
        k = grid.cell_of(x, z)
        if k < 0 or not true_road[k]:
            return 0.0
        return studs(clear[k] * CELL)

    def solve_offsets(pts, desired, low, high):
        """Per point, the lateral offset (studs, right of travel) nearest to
        the desired one that keeps CAR_CLEAR to every obstacle; lanes bend
        around pillars and away from curbs instead of running through them."""
        directions = tangents(pts)
        chosen = []
        for (x, z), (tx, tz), want, lo, hi in zip(pts, directions, desired, low, high):
            best, best_clear, fallback = None, -1.0, want
            # Search around the previous point's offset (drifting back toward
            # the wanted one) so a detour is one smooth swerve, not a zigzag.
            center = want if not chosen else chosen[-1] * 0.8 + want * 0.2
            step = 0
            while True:
                tried = False
                for o in ((center + step * 0.25, center - step * 0.25) if step else (center,)):
                    if lo <= o <= hi:
                        tried = True
                        c = clearance_at(x - tz * o / SCALE, z + tx * o / SCALE)
                        if c >= CAR_CLEAR:
                            best = o
                            break
                        if c > best_clear:
                            best_clear, fallback = c, o
                if best is not None or not tried and center + step * 0.25 > hi and center - step * 0.25 < lo:
                    break
                step += 1
            chosen.append(best if best is not None else fallback)
        # Ease the result along the lane, keeping the safe value wherever the
        # eased one would touch an obstacle.
        eased = []
        for i in range(len(chosen)):
            window = chosen[max(0, i - 3): i + 4]
            value = sum(window) / len(window)
            (x, z), (tx, tz) = pts[i], directions[i]
            eased.append(value if clearance_at(x - tz * value / SCALE, z + tx * value / SCALE) >= CAR_CLEAR else chosen[i])
        return eased

    def make_lanes(radius):
        lanes = []
        for ei, e in enumerate(E):
            half_studs = studs(e["half"])
            directions = [(e["a"], e["b"], e["pts"])]
            if not e["oneway"]:
                directions.append((e["b"], e["a"], list(reversed(e["pts"]))))
            for u, v, pts in directions:
                local = []
                for x, z in pts:
                    k = grid.cell_of(x, z)
                    local.append(studs(dist[k] * CELL) if k >= 0 else half_studs)
                # The lane follows the road's own width at each point (eased
                # so bays and junction bulges do not make it wander).
                width = [sum(local[max(0, i - 10): i + 11]) / len(local[max(0, i - 10): i + 11]) for i in range(len(local))]
                if e["oneway"]:
                    count = 2 if half_studs >= 9 else 1
                    low = [-h for h in local]
                else:
                    count = 2 if half_studs >= TWO_LANES_FROM else 1
                    # Never drift across the centre line into oncoming traffic.
                    low = [1.0 for _ in local]
                for index in range(count):
                    if e["oneway"]:
                        desired = [w * ((2 * index + 1) / count - 1) for w in width]
                    else:
                        desired = [max(min(w * (2 * index + 1) / (2 * count), w - CAR_CLEAR), 1.0) for w in width]
                    offsets = solve_offsets(pts, desired, low, local)
                    lane = offset_right_varying(pts, [o / SCALE for o in offsets])
                    if u == v:
                        lane_pts = lane
                    else:
                        lane_pts = trim(lane, centers[u], radius[u], True)
                        lane_pts = lane_pts and trim(lane_pts, centers[v], radius[v], False)
                    if not lane_pts or polyline_length(lane_pts) < 3 * CELL:
                        continue
                    lanes.append({"edge": ei, "from": u, "to": v, "index": index, "count": count, "pts": lane_pts,
                                  "oneway": e["oneway"], "ring": e["ring"], "half": e["half"]})
        return lanes

    def on_road(points, margin):
        # The end points belong to lanes already checked; test the curve between.
        for x, z in points[1:-1]:
            if clearance_at(x, z) < margin:
                return False
        return True

    def make_connectors(lanes, margins, only_missing=None, connectors=None):
        """Junction curves kept only when every sample keeps `margin` studs to
        any curb or obstacle. With only_missing, adds curves just for the lanes
        that still have none (relaxed pass)."""
        connectors = connectors if connectors is not None else []
        # Junctions so close that the street between them kept no lane in one
        # direction act as one: curves continue straight into the next node's lanes.
        bridges = {}
        for ei, e in enumerate(E):
            if e["a"] == e["b"]:
                continue
            directions = [(e["a"], e["b"])] if e["oneway"] else [(e["a"], e["b"]), (e["b"], e["a"])]
            for u, v in directions:
                if not any(l["edge"] == ei and l["from"] == u for l in lanes):
                    bridges.setdefault(u, []).append((v, ei))
        has_way = {c["from"] for c in connectors}
        for v in range(len(nodes)):
            ins = [i for i, lane in enumerate(lanes) if lane["to"] == v]
            outs = [i for i, lane in enumerate(lanes) if lane["from"] == v]
            for w, bridge_edge in bridges.get(v, []):
                outs += [i for i, lane in enumerate(lanes)
                         if lane["from"] == w and lane["edge"] != bridge_edge and v not in (E[lane["edge"]]["a"], E[lane["edge"]]["b"])]
            for i in ins:
                if only_missing and i in has_way:
                    continue
                lin = lanes[i]
                p0 = lin["pts"][-1]
                t0 = tangents(lin["pts"])[-1]
                for o in outs:
                    lout = lanes[o]
                    uturn = lout["edge"] == lin["edge"]
                    if uturn and (degree[v] > 1 or lin["oneway"]):
                        continue
                    p3 = lout["pts"][0]
                    t1 = tangents(lout["pts"])[0]
                    angle = math.degrees(math.atan2(cross(t0, t1), t0[0] * t1[0] + t0[1] * t1[1]))
                    if not only_missing:
                        if uturn:
                            if lin["index"] != 0 or lout["index"] != 0:
                                continue
                        elif angle > 35:
                            if lin["index"] != lin["count"] - 1 or lout["index"] != lout["count"] - 1:
                                continue
                        elif angle < -35:
                            if lin["index"] != 0 or lout["index"] != 0:
                                continue
                        elif lout["index"] != min(lin["index"], lout["count"] - 1):
                            continue
                    done = False
                    for margin in margins:
                        for k in (0.5, 0.35, 0.65, 0.8, 0.25, 0.15):
                            curve = bezier(p0, t0, p3, t1, k)
                            if on_road(curve, margin):
                                connectors.append({"from": i, "to": o, "node": v, "pts": curve,
                                                   "turn": "uturn" if uturn else ("right" if angle > 35 else ("left" if angle < -35 else "straight"))})
                                has_way.add(i)
                                done = True
                                break
                        if done:
                            break
        return connectors

    # Lanes and strict curves; a junction where some lane cannot turn or go
    # straight within CAR_CLEAR grows (lanes end further out, curves widen).
    for attempt in range(5):
        lanes = make_lanes(radius)
        connectors = make_connectors(lanes, [CAR_CLEAR])
        has_way = {c["from"] for c in connectors}
        weak = {lane["to"] for i, lane in enumerate(lanes) if i not in has_way and degree[lane["to"]] > 1}
        if not weak:
            break
        print("attempt", attempt + 1, "junctions widened:", len(weak))
        for v in weak:
            radius[v] *= 1.2
    # Lanes still without a way on: any curve that fits with less margin.
    connectors = make_connectors(lanes, [CAR_CLEAR * 0.85, CAR_CLEAR * 0.7], only_missing=True, connectors=connectors)

    # Traffic control: two light phases split by approach axis; the
    # roundabout yields to traffic already in the ring.
    controls = []
    for v in range(len(nodes)):
        if v in ring_nodes:
            controls.append({"kind": "yield", "phases": {}})
            continue
        approaches = sorted({lane["edge"] for lane in lanes if lane["to"] == v})
        if degree[v] < 3 or len(approaches) < 3:
            controls.append({"kind": "none", "phases": {}})
            continue
        angles = {}
        for ei in approaches:
            e = E[ei]
            pts = e["pts"] if e["a"] == v else list(reversed(e["pts"]))
            ref = pts[min(len(pts) - 1, int(radius[v] / CELL) + 3)]
            angles[ei] = math.degrees(math.atan2(ref[1] - centers[v][1], ref[0] - centers[v][0])) % 180
        first = angles[approaches[0]]
        phases = {}
        for ei in approaches:
            delta = abs(angles[ei] - first) % 180
            phases[ei] = 1 if min(delta, 180 - delta) <= 40 else 2
        if len(set(phases.values())) < 2:
            controls.append({"kind": "none", "phases": {}})
        else:
            controls.append({"kind": "light", "phases": phases})

    # Air lanes over the streets: one per direction, recording the highest
    # obstacle under every point so flying traffic can climb over it.
    def top_near(x, z):
        k = grid.cell_of(x, z)
        if k < 0:
            return FLOOR_Y
        r, c = divmod(k, grid.columns)
        best = FLOOR_Y
        for dr in range(-3, 4):
            for dc in range(-3, 4):
                rr, cc = r + dr, c + dc
                if 0 <= rr < grid.rows and 0 <= cc < grid.columns:
                    best = max(best, top_h[rr * grid.columns + cc])
        return best

    air = []
    for ei, e in enumerate(E):
        if polyline_length(e["pts"]) < 40 / SCALE:
            continue
        directions = [(e["a"], e["b"], e["pts"])]
        if not e["oneway"]:
            directions.append((e["b"], e["a"], list(reversed(e["pts"]))))
        for u, v, pts in directions:
            lane = offset_right(pts, 0 if e["oneway"] else e["half"] * 0.45)
            if u != v:
                lane = trim(lane, centers[u], radius[u] * 0.7, True)
                lane = lane and trim(lane, centers[v], radius[v] * 0.7, False)
            if lane and polyline_length(lane) >= 3 * CELL:
                air.append({"edge": ei, "from": u, "to": v, "pts": lane})
    air_connectors = []
    for v in range(len(nodes)):
        for i, lin in enumerate(air):
            if lin["to"] != v:
                continue
            for o, lout in enumerate(air):
                if lout["from"] != v or (lout["edge"] == lin["edge"] and degree[v] > 1):
                    continue
                curve = bezier(lin["pts"][-1], tangents(lin["pts"])[-1], lout["pts"][0], tangents(lout["pts"])[0], 0.5)
                air_connectors.append({"from": i, "to": o, "pts": curve})
    # An air lane that ended without a way on (its street's other lanes were
    # too short to keep) turns back over its own street instead of vanishing.
    for i, lin in enumerate(air):
        if any(c["from"] == i for c in air_connectors):
            continue
        back = [o for o, lout in enumerate(air) if lout["from"] == lin["to"]] or \
               [o for o, lout in enumerate(air) if lout["edge"] == lin["edge"] and o != i]
        for o in back[:1]:
            lout = air[o]
            curve = bezier(lin["pts"][-1], tangents(lin["pts"])[-1], lout["pts"][0], tangents(lout["pts"])[0], 0.6)
            air_connectors.append({"from": i, "to": o, "pts": curve})

    # Diagnostics: lanes that end without a way out (cars leave the map there).
    for i, lane in enumerate(lanes):
        if not any(c["from"] == i for c in connectors):
            x, z = lane["pts"][-1]
            v = lane["to"]
            outs = [o for o, l in enumerate(lanes) if l["from"] == v]
            print("exit lane %d at px (%d, %d) node %d degree %d outs %d edge %d index %d/%d" % (
                i, (x - grid.min_x) / CELL, (z - grid.min_z) / CELL, v, degree[v], len(outs), lane["edge"], lane["index"], lane["count"]))
            for o in outs:
                lout = lanes[o]
                p0, t0 = lane["pts"][-1], tangents(lane["pts"])[-1]
                p3, t1 = lout["pts"][0], tangents(lout["pts"])[0]
                curve = bezier(p0, t0, p3, t1, 0.5)
                worst = min(cell_clearance(grid, dist, cx, cz) if road[grid.cell_of(cx, cz)] else -1 for cx, cz in curve)
                print("   out %d edge %d start px (%d, %d) heading in (%.2f, %.2f) out (%.2f, %.2f) min clearance %.1f" % (
                    o, lout["edge"], (p3[0] - grid.min_x) / CELL, (p3[1] - grid.min_z) / CELL, t0[0], t0[1], t1[0], t1[1], worst))
    for lane in lanes:
        lane["pts"] = simplify(lane["pts"], CELL * 0.15)
    for lane in air:
        lane["pts"] = simplify(lane["pts"], CELL * 0.3)
    for c in connectors + air_connectors:
        c["pts"] = simplify(c["pts"], CELL * 0.08)
    print("lanes", len(lanes), "connectors", len(connectors), "lights", sum(1 for c in controls if c["kind"] == "light"),
          "air lanes", len(air), "air connectors", len(air_connectors))
    return {"nodes": nodes, "centers": centers, "radius": radius, "controls": controls, "edges": E, "lanes": lanes,
            "connectors": connectors, "air": air, "air_connectors": air_connectors, "street_h": street_h,
            "top_near": top_near, "grid": grid}


WALK_FROM_CURB = (1.5, 3.5)   # cells inside the curb for the walking line
CROSSWALK_MIN = 8.0           # studs


def build_walkways(grid, road, sidewalk, blocked, street_h, network):
    """Sidewalk lines around the blocks and crosswalks at junction arms."""
    n = grid.n
    not_road = bytearray(0 if road[k] else 1 for k in range(n))
    from_road = chamfer(grid, not_road)
    band = bytearray(1 if sidewalk[k] and WALK_FROM_CURB[0] <= from_road[k] <= WALK_FROM_CURB[1] else 0 for k in range(n))
    for cells in components(grid, band, 1):
        if len(cells) < 40:
            for k in cells:
                band[k] = 0
    skel = clean_skeleton(grid, thin(grid, band))
    nodes, edges = skeleton_graph(grid, skel)
    dist_band = chamfer(grid, band)
    nodes, edges = prune_and_merge(grid, nodes, edges, dist_band)
    centers = [node_center(grid, cluster) for cluster in nodes]
    paths = []
    for a, b, path in edges:
        pts = [grid.center(k) for k in path]
        pts[0] = centers[a]
        pts[-1] = centers[b]
        pts = smooth(resample(pts, CELL), 3)
        if polyline_length(pts) < 6 / SCALE:
            continue
        paths.append({"a": a, "b": b, "pts": pts})

    # Crosswalks: across each arm of a junction, a little way out from it,
    # joining the nearest sidewalk points on both sides of the road.
    samples = []
    for pi, p in enumerate(paths):
        travelled = 0.0
        for i, (x, z) in enumerate(p["pts"]):
            if i:
                travelled += math.hypot(x - p["pts"][i - 1][0], z - p["pts"][i - 1][1])
            samples.append((x, z, pi, travelled))
    E, centers_road, radius = network["edges"], network["centers"], network["radius"]
    links = []
    for v, (cx, cz) in enumerate(centers_road):
        if network["controls"][v]["kind"] == "none" and sum(1 for e in E if v in (e["a"], e["b"])) < 3:
            continue
        for ei, e in enumerate(E):
            if v not in (e["a"], e["b"]) or e["a"] == e["b"]:
                continue
            pts = e["pts"] if e["a"] == v else list(reversed(e["pts"]))
            # Point on the arm just outside the junction.
            target = radius[v] + 4 / SCALE
            travelled, arm = 0.0, None
            for i in range(1, len(pts)):
                travelled += math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1])
                if travelled >= target:
                    arm = i
                    break
            if arm is None:
                continue
            px, pz = pts[arm]
            tx, tz = tangents(pts)[arm]
            nx, nz = -tz, tx
            reach = e["half"] + 3.5 / SCALE
            best = []
            for sign in (1, -1):
                gx, gz = px + nx * reach * sign, pz + nz * reach * sign
                candidates = [(math.hypot(x - gx, z - gz), x, z, pi, d) for x, z, pi, d in samples]
                candidates = [c for c in candidates if c[0] < 6 / SCALE]
                best.append(min(candidates) if candidates else None)
            if not best[0] or not best[1] or best[0][3] == best[1][3] and abs(best[0][4] - best[1][4]) < 30 / SCALE:
                continue
            (_, ax, az, pa, da), (_, bx, bz, pb, db) = best
            length = math.hypot(bx - ax, bz - az)
            if studs(length) < CROSSWALK_MIN:
                continue
            steps = max(2, int(length / (CELL * 0.5)))
            runs, previous, ok = 0, False, True
            line_pts = []
            for s in range(steps + 1):
                f = s / steps
                x, z = ax + (bx - ax) * f, az + (bz - az) * f
                k = grid.cell_of(x, z)
                if k < 0 or blocked[k] or not (road[k] or sidewalk[k]):
                    ok = False
                    break
                if road[k] and not previous:
                    runs += 1
                previous = bool(road[k])
                line_pts.append((x, z))
            if not ok or runs != 1:
                continue
            # Every cell is kept: the crosswalk steps down from the curb to the
            # asphalt and back up, and those heights must survive (no simplify).
            links.append({"a": pa, "da": da, "b": pb, "db": db, "node": v, "edge": ei, "pts": resample(line_pts, CELL)})
    for p in paths:
        p["pts"] = simplify(p["pts"], CELL * 0.15)
    print("walkways", len(paths), "walk nodes", len(nodes), "crosswalks", len(links))
    return {"paths": paths, "nodes": centers, "links": links}


def draw_network(grid, road, sidewalk, blocked, network, walkways, debug_dir):
    pixels = base_image(grid, road, sidewalk, blocked)
    for lane in network["lanes"]:
        pts = lane["pts"]
        color = (0, 200, 255) if lane["oneway"] else ((90, 255, 120) if lane["index"] == 0 else (255, 230, 60))
        for i in range(1, len(pts)):
            line(pixels, grid, pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1], color)
        # Arrow-ish marker: brighter dot near the lane end.
        dot(pixels, grid, pts[-1][0], pts[-1][1], (255, 255, 255), 1)
    for connector in network["connectors"]:
        pts = connector["pts"]
        for i in range(1, len(pts)):
            line(pixels, grid, pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1], (200, 200, 200))
    exits = {c["from"] for c in network["connectors"]}
    for i, lane in enumerate(network["lanes"]):
        if i not in exits:
            dot(pixels, grid, lane["pts"][-1][0], lane["pts"][-1][1], (255, 0, 255), 2)
    for v, (x, z) in enumerate(network["centers"]):
        kind = network["controls"][v]["kind"]
        color = {"light": (0, 255, 0), "yield": (255, 140, 0), "none": (120, 120, 120)}[kind]
        dot(pixels, grid, x, z, color, 2)
    write_png(os.path.join(debug_dir, "2_lanes.png"), grid.columns, grid.rows, pixels)

    # Sidewalks (white), crosswalks (cyan), air lanes coloured by the
    # obstacle height under them (green low, red high).
    pixels = base_image(grid, road, sidewalk, blocked)
    for p in walkways["paths"]:
        pts = p["pts"]
        for i in range(1, len(pts)):
            line(pixels, grid, pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1], (235, 235, 235))
    for link in walkways["links"]:
        pts = link["pts"]
        for i in range(1, len(pts)):
            line(pixels, grid, pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1], (0, 220, 255))
    write_png(os.path.join(debug_dir, "3_walkways.png"), grid.columns, grid.rows, pixels)
    pixels = base_image(grid, road, sidewalk, blocked)
    top_near = network["top_near"]
    for lane in network["air"]:
        pts = lane["pts"]
        for i in range(1, len(pts)):
            t = min(1.0, max(0.0, studs(top_near(*pts[i]) - FLOOR_Y) / 120))
            line(pixels, grid, pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1], (int(255 * t), int(255 * (1 - t)), 40))
    write_png(os.path.join(debug_dir, "4_air.png"), grid.columns, grid.rows, pixels)


def write_luau(out_path, network, walkways):
    grid, street_h, top_near = network["grid"], network["street_h"], network["top_near"]

    def f(v):
        return "%.4f" % v

    def ground(points):
        return ", ".join("%s, %s, %s" % (f(x), f(surface_y(grid, street_h, x, z)), f(z)) for x, z in points)

    def sky(points):
        return ", ".join("%s, %s, %s" % (f(x), f(top_near(x, z)), f(z)) for x, z in points)

    controls = {"none": 0, "light": 1, "yield": 2}
    turns = {"straight": 0, "right": 1, "left": 2, "uturn": 3}
    lines = [
        "--!strict",
        "",
        "-- GENERATED by scripts/build_city2059_streets.py from the City2059 GLB and",
        "-- World/City2059Data colliders. Do not edit; rerun the script instead.",
        "-- Coordinates are glTF units (the City2059Data frame); the client maps them",
        "-- to the world with the transform the server publishes on the FreeRoam model.",
        "-- Indices are 1-based. Debug maps: see the script header.",
        "",
        "return table.freeze({",
        "\tVersion = 1,",
        "\t-- { x, y, z, radius, control } control: 0 none, 1 traffic light, 2 yield (roundabout)",
        "\tNodes = table.freeze({",
    ]
    for v, (x, z) in enumerate(network["centers"]):
        lines.append("\t\ttable.freeze({ %s, %s, %s, %s, %d })," % (f(x), f(surface_y(grid, street_h, x, z)), f(z),
                                                                    f(network["radius"][v]), controls[network["controls"][v]["kind"]]))
    lines += ["\t}),", "\t-- Light phase (1 or 2) of each approach street, per light node: [node] = { [street] = phase }",
              "\tPhases = table.freeze({"]
    for v, control in enumerate(network["controls"]):
        if control["kind"] == "light":
            entries = ", ".join("[%d] = %d" % (ei + 1, phase) for ei, phase in sorted(control["phases"].items()))
            lines.append("\t\t[%d] = table.freeze({ %s })," % (v + 1, entries))
    lines += ["\t}),", "\t-- { street, fromNode, toNode, flags, x, y, z, ... } flags: 1 one-way, 2 roundabout",
              "\tLanes = table.freeze({"]
    for lane in network["lanes"]:
        flags = (1 if lane["oneway"] else 0) + (2 if lane["ring"] else 0)
        lines.append("\t\ttable.freeze({ %d, %d, %d, %d, %s })," % (lane["edge"] + 1, lane["from"] + 1, lane["to"] + 1, flags, ground(lane["pts"])))
    lines += ["\t}),", "\t-- { fromLane, toLane, node, turn, x, y, z, ... } turn: 0 straight, 1 right, 2 left, 3 U-turn",
              "\tConnectors = table.freeze({"]
    for c in network["connectors"]:
        lines.append("\t\ttable.freeze({ %d, %d, %d, %d, %s })," % (c["from"] + 1, c["to"] + 1, c["node"] + 1, turns[c["turn"]], ground(c["pts"])))
    lines += ["\t}),", "\t-- Flying traffic over the streets: { street, fromNode, toNode, x, top, z, ... }",
              "\t-- (top = highest obstacle under the point, the minimum safe height)",
              "\tAirLanes = table.freeze({"]
    for lane in network["air"]:
        lines.append("\t\ttable.freeze({ %d, %d, %d, %s })," % (lane["edge"] + 1, lane["from"] + 1, lane["to"] + 1, sky(lane["pts"])))
    lines += ["\t}),", "\t-- { fromAirLane, toAirLane, x, top, z, ... }", "\tAirConnectors = table.freeze({"]
    for c in network["air_connectors"]:
        lines.append("\t\ttable.freeze({ %d, %d, %s })," % (c["from"] + 1, c["to"] + 1, sky(c["pts"])))
    lines += ["\t}),", "\t-- Sidewalk lines: { fromWalkNode, toWalkNode, x, y, z, ... }", "\tWalkways = table.freeze({"]
    for p in walkways["paths"]:
        lines.append("\t\ttable.freeze({ %d, %d, %s })," % (p["a"] + 1, p["b"] + 1, ground(p["pts"])))
    lines += ["\t}),", "\tWalkNodes = table.freeze({"]
    for x, z in walkways["nodes"]:
        lines.append("\t\ttable.freeze({ %s, %s, %s })," % (f(x), f(surface_y(grid, street_h, x, z)), f(z)))
    lines += ["\t}),", "\t-- Crosswalks: { walkwayA, walkwayB, node, street, x, y, z, ... } (first and last",
              "\t-- points lie on the two sidewalks; street = the road arm crossed)", "\tCrosswalks = table.freeze({"]
    for link in walkways["links"]:
        lines.append("\t\ttable.freeze({ %d, %d, %d, %d, %s })," % (link["a"] + 1, link["b"] + 1, link["node"] + 1, link["edge"] + 1, ground(link["pts"])))
    lines += ["\t}),", "})", ""]
    with open(out_path, "w", encoding="utf-8", newline="\n") as out:
        out.write("\n".join(lines))
    print("wrote", out_path, os.path.getsize(out_path) // 1024, "KB")


main()
