import math
import os
import sys
import traceback

import bpy
import numpy as np

# Prepares the facade materials for the per-tower cladding:
#   * copies the chosen KitBash3D Neo City materials (Color, Normal, Roughness)
#     resized to 1024 (Roblox's maximum) as Reality2059KB3D_<Name>_<Map>.png,
#   * generates the window overlays Reality2059Windows_<Pattern>.png (RGBA:
#     transparent wall, glass panes, some lit) tiled over each tower.
# KitBash3D files are licensed to the project owner: do not publish them
# outside the game.
# Usage: blender -b --python prepare_kb3d_facades.py -- <kb3d png folder> <out dir>

MATERIALS = [
    "DarkPanels", "WhitePanels", "ConcreteWall", "ConcreteTiles",
    "DecorConcreteCBeige", "WoodDarkGreyTower", "SpeedwayTiles", "ConcreteAccent",
]
MAPS = {"basecolor": "Color", "normal": "Normal", "roughness": "Roughness"}
SIZE = 1024
WINDOW_SIZE = 512


def save_rgba(path, rgba):
    size = rgba.shape[0]
    image = bpy.data.images.new(os.path.basename(path), size, size, alpha=True)
    image.colorspace_settings.name = "sRGB"
    image.pixels.foreach_set(np.ascontiguousarray(rgba[::-1], dtype=np.float32).ravel())
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)


def copy_resized(source, target, color):
    image = bpy.data.images.load(source)
    image.colorspace_settings.name = "sRGB" if color else "Non-Color"
    if image.size[0] != SIZE:
        image.scale(SIZE, SIZE)
    image.filepath_raw = target
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)


def windows(pattern, seed):
    """RGBA tile: transparent wall, dark glass panes with frames, ~30 % lit."""
    rng = np.random.default_rng(seed)
    n = WINDOW_SIZE
    rgba = np.zeros((n, n, 4))
    if pattern == "Grid":       # 4 x 4 square windows
        cells, (w0, w1, h0, h1) = (4, 4), (0.18, 0.82, 0.2, 0.8)
    elif pattern == "Bands":    # 2 x 4 wide ribbon windows
        cells, (w0, w1, h0, h1) = (2, 4), (0.04, 0.96, 0.28, 0.78)
    else:                       # Slits: 8 x 2 tall narrow windows
        cells, (w0, w1, h0, h1) = (8, 2), (0.3, 0.7, 0.08, 0.92)
    cols, rows = cells
    cw, ch = n // cols, n // rows
    warm = np.array([1.0, 0.72, 0.38])
    cool = np.array([0.45, 0.85, 1.0])
    pink = np.array([1.0, 0.45, 0.8])
    for r in range(rows):
        for c in range(cols):
            x0, x1 = c * cw + int(w0 * cw), c * cw + int(w1 * cw)
            y0, y1 = r * ch + int(h0 * ch), r * ch + int(h1 * ch)
            # Frame.
            rgba[y0 - 3:y1 + 3, x0 - 3:x1 + 3] = [0.03, 0.03, 0.04, 1]
            lit = rng.random() < 0.32
            if lit:
                tone = [warm, cool, pink][rng.integers(0, 3)] if rng.random() < 0.85 else warm
                gy = np.linspace(1.0, 0.6, y1 - y0)[:, None, None]
                pane = tone[None, None, :] * gy * (0.75 + 0.25 * rng.random())
            else:
                gy = np.linspace(0.18, 0.08, y1 - y0)[:, None, None]
                pane = np.array([0.35, 0.45, 0.7])[None, None, :] * gy
            rgba[y0:y1, x0:x1, :3] = pane
            rgba[y0:y1, x0:x1, 3] = 1
            # Mullion in wide windows.
            if x1 - x0 > ch * 0.8:
                mid = (x0 + x1) // 2
                rgba[y0:y1, mid - 2:mid + 2] = [0.03, 0.03, 0.04, 1]
    return rgba


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    source_dir, out_dir = args
    os.makedirs(out_dir, exist_ok=True)
    for name in MATERIALS:
        for kb3d, suffix in MAPS.items():
            source = os.path.join(source_dir, "KB3D_NEC_%s_%s.png" % (name, kb3d))
            copy_resized(source, os.path.join(out_dir, "Reality2059KB3D_%s_%s.png" % (name, suffix)), kb3d == "basecolor")
    for index, pattern in enumerate(("Grid", "Bands", "Slits")):
        save_rgba(os.path.join(out_dir, "Reality2059Windows_%s.png" % pattern), windows(pattern, 59 + index))


try:
    main()
except Exception:
    args = sys.argv[sys.argv.index("--") + 1:]
    with open(os.path.join(args[1], "error.txt"), "w") as f:
        f.write(traceback.format_exc())
    raise
