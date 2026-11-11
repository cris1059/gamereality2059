import math
import os
import sys
import traceback

import bpy
import numpy as np

# Procedural cyberpunk PBR tiles for City2059 (no external images).
# The city's UVs are world-scale box projections (~8.26 tiles per glTF unit,
# V growing downward on walls), so one tile = ~7.3 studs at CityScale 60:
# about one building floor. Every map tiles seamlessly in both directions.
# Usage (headless):
#   blender -b --python generate_cyber_textures.py -- <out_dir> [size]
# Writes Reality2059Cyber_<Set>_<Color|Normal|Roughness|Metalness>.png.
# Normal maps are OpenGL convention (green = +Y up), as Roblox expects.

SIZE = 1024
RNG = np.random.default_rng(2059)


def periodic_noise(size, scale, octaves=4, seed=0):
    """Tileable fractal noise in 0..1 built in the frequency domain."""
    rng = np.random.default_rng(seed)
    result = np.zeros((size, size))
    amplitude, total = 1.0, 0.0
    for octave in range(octaves):
        freq = scale * (2 ** octave)
        spectrum = rng.normal(size=(size, size)) + 1j * rng.normal(size=(size, size))
        fy = np.fft.fftfreq(size)[:, None] * size
        fx = np.fft.fftfreq(size)[None, :] * size
        radius = np.sqrt(fx * fx + fy * fy)
        band = np.exp(-((radius - freq) ** 2) / (2 * (freq * 0.6) ** 2))
        layer = np.real(np.fft.ifft2(spectrum * band))
        layer = (layer - layer.min()) / (layer.max() - layer.min() + 1e-9)
        result += layer * amplitude
        total += amplitude
        amplitude *= 0.5
    return result / total


def coords(size):
    v, u = np.mgrid[0:size, 0:size] / size
    return u, v


def rect(u, v, u0, v0, u1, v1):
    return (u >= u0) & (u < u1) & (v >= v0) & (v < v1)


def bevel(u, v, u0, v0, u1, v1, width):
    """0 at the rectangle edge rising to 1 inside over `width`."""
    d = np.minimum.reduce([u - u0, u1 - u, v - v0, v1 - v])
    return np.clip(d / width, 0, 1) * rect(u, v, u0, v0, u1, v1)


def lerp_color(mask, base, color):
    return base * (1 - mask[..., None]) + np.array(color)[None, None, :] * mask[..., None]


def normal_from_height(height, strength):
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    # Image rows grow downward; OpenGL normal maps want +Y = up.
    nx, ny, nz = -dx * strength, dy * strength, np.ones_like(height)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / length * 0.5 + 0.5, ny / length * 0.5 + 0.5, nz / length * 0.5 + 0.5], axis=-1)


def save(path, pixels):
    """pixels: HxWx3 (or HxW) floats 0..1, row 0 = top of the image."""
    if pixels.ndim == 2:
        pixels = np.repeat(pixels[..., None], 3, axis=-1)
    size = pixels.shape[0]
    rgba = np.ones((size, size, 4), dtype=np.float32)
    rgba[..., :3] = np.clip(pixels, 0, 1)
    rgba = rgba[::-1]  # Blender images start at the bottom row
    name = os.path.basename(path)
    image = bpy.data.images.new(name, size, size, alpha=False)
    image.colorspace_settings.name = "sRGB" if path.endswith("_Color.png") else "Non-Color"
    image.pixels.foreach_set(rgba.ravel())
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)


def facade(size):
    """One tower floor: cornice with a neon line, four window bays, spandrel."""
    u, v = coords(size)
    grime = periodic_noise(size, 6, seed=1)
    fine = periodic_noise(size, 40, octaves=3, seed=2)
    streaks = periodic_noise(size, 3, octaves=2, seed=3)
    streak = np.clip((np.roll(streaks, 0, axis=0) - 0.55) * 4, 0, 1) * (0.6 + 0.4 * np.sin(u * math.pi * 26) ** 2)
    color = np.zeros((size, size, 3)) + np.array([0.075, 0.08, 0.1])
    height = np.zeros((size, size)) + 0.5
    rough = np.zeros((size, size)) + 0.55
    metal = np.zeros((size, size)) + 0.6

    # Cornice / floor slab band.
    slab = rect(u, v, 0, 0, 1, 0.11)
    color = lerp_color(slab.astype(float), color, (0.11, 0.115, 0.13))
    height = np.where(slab, 0.7, height)
    rough = np.where(slab, 0.8, rough)
    metal = np.where(slab, 0.1, metal)
    neon = rect(u, v, 0, 0.09, 1, 0.096)
    color = lerp_color(neon.astype(float) * 0.6, color, (0.1, 0.85, 1.0))
    rough = np.where(neon, 0.25, rough)
    metal = np.where(neon, 0.0, metal)

    # Window bays.
    # Mostly dark glass: on a repeating tile, few lit panes read as a city at
    # work instead of wallpaper. One warm bay, one cool half-pane (bay 2).
    states = [
        ("lit", (1.0, 0.6, 0.26)),
        ("dark", (0.1, 0.13, 0.26)),
        ("dark", (0.07, 0.1, 0.2)),
        ("dark", (0.22, 0.07, 0.22)),
    ]
    bay_width = 1 / len(states)
    top, bottom = 0.15, 0.76
    for index, (state, tint) in enumerate(states):
        u0 = index * bay_width
        frame = rect(u, v, u0, top - 0.02, u0 + bay_width, bottom + 0.02)
        glass = rect(u, v, u0 + 0.022, top, u0 + bay_width - 0.022, bottom)
        color = lerp_color(frame.astype(float), color, (0.05, 0.055, 0.065))
        height = np.where(frame, 0.85, height)
        metal = np.where(frame, 0.95, metal)
        rough = np.where(frame, 0.35, rough)
        local_v = (v - top) / (bottom - top)
        local_u = (u - u0) / bay_width
        if index == 2:
            half = rect(local_u, local_v, 0.5, 0.0, 1.0, 1.0)
            cool = np.array((0.2, 0.75, 0.9))[None, None, :] * (0.45 + 0.4 * (1 - local_v[..., None]))
        if state == "lit":
            interior = np.array(tint)[None, None, :] * (0.55 + 0.45 * (1 - local_v[..., None]))
            blinds = (np.sin(local_v * math.pi * 34) > 0.55) & (local_v < 0.35)
            interior = interior * np.where(blinds[..., None], 0.55, 1.0)
            # Simple furniture: a desk and a shelf block against the glow.
            furniture = rect(local_u, local_v, 0.12, 0.72, 0.55, 1.0) | rect(local_u, local_v, 0.68, 0.45, 0.9, 1.0)
            interior = interior * np.where(furniture[..., None], 0.3, 1.0)
            ceiling = rect(local_u, local_v, 0.08, 0.04, 0.92, 0.07)
            interior = np.where(ceiling[..., None], 1.0, interior)
        else:
            reflection = np.clip(1.2 - np.abs(local_u - local_v * 0.6 - 0.2) * 3, 0, 1) * 0.35
            interior = np.array(tint)[None, None, :] * (0.35 + 0.4 * local_v[..., None]) + reflection[..., None] * 0.25
        if index == 2:
            interior = np.where(half[..., None], cool, interior)
        color = np.where(glass[..., None], interior, color)
        height = np.where(glass, 0.3, height)
        rough = np.where(glass, 0.08, rough)
        metal = np.where(glass, 0.0, metal)
        # Mullion splitting each bay.
        mullion = rect(u, v, u0 + bay_width * 0.5 - 0.006, top, u0 + bay_width * 0.5 + 0.006, bottom)
        color = lerp_color(mullion.astype(float), color, (0.05, 0.055, 0.065))
        height = np.where(mullion, 0.8, height)
        metal = np.where(mullion, 0.95, metal)

    # Spandrel: ribbed dark panel with seams and small vents.
    spandrel = rect(u, v, 0, 0.8, 1, 1.0)
    ribs = (np.sin(u * math.pi * 2 * 32) > 0.7) & spandrel
    height = np.where(spandrel, 0.55 + 0.1 * ribs, height)
    seam = spandrel & ((np.abs(((u * 4) % 1) - 0.5) > 0.495) | (np.abs(v - 0.8) < 0.004))
    height = np.where(seam, 0.35, height)
    color = lerp_color((spandrel & ~seam).astype(float) * 0.6, color, (0.09, 0.1, 0.13))
    vents = spandrel & rect(u % 0.25, v, 0.16, 0.86, 0.23, 0.94) & (np.sin(v * math.pi * 2 * 60) > 0)
    color = lerp_color(vents.astype(float), color, (0.02, 0.02, 0.025))
    height = np.where(vents, 0.4, height)

    # Wear: grime, rain streaks under the sills, fine noise.
    dirt = np.clip(grime * 0.7 + streak * 0.6 * (v > 0.76), 0, 1)
    glass_mask = (rough < 0.1)
    color = color * (1 - 0.35 * dirt[..., None] * (~glass_mask)[..., None]) * (0.92 + 0.16 * fine[..., None])
    rough = np.clip(rough + 0.15 * dirt * (~glass_mask), 0, 1)
    height = height + 0.03 * fine
    return color, normal_from_height(height, 6.0), rough, metal


def panels(size):
    """Industrial plates: 2x2 bevelled plates, rivets, vents, a hazard strip."""
    u, v = coords(size)
    grime = periodic_noise(size, 5, seed=11)
    fine = periodic_noise(size, 48, octaves=3, seed=12)
    color = np.zeros((size, size, 3)) + np.array([0.33, 0.34, 0.36])
    height = np.zeros((size, size))
    rough = np.zeros((size, size)) + 0.5
    metal = np.zeros((size, size)) + 0.85
    for row in range(2):
        for col in range(2):
            u0, v0 = col * 0.5 + 0.006, row * 0.5 + 0.006
            plate = bevel(u, v, u0, v0, u0 + 0.488, v0 + 0.488, 0.02)
            height = np.maximum(height, plate * 0.8)
            shade = 0.9 + 0.1 * ((row + col) % 2)
            color = np.where((plate > 0)[..., None], color * shade, color)
            for cu in (u0 + 0.03, u0 + 0.458):
                for cv in (v0 + 0.03, v0 + 0.458):
                    rivet = np.clip(1 - np.sqrt((u - cu) ** 2 + (v - cv) ** 2) / 0.011, 0, 1)
                    height = np.maximum(height, rivet * 1.0)
                    color = lerp_color((rivet > 0).astype(float) * 0.5, color, (0.5, 0.5, 0.52))
    seams = height < 0.05
    color = lerp_color(seams.astype(float), color, (0.06, 0.06, 0.07))
    rough = np.where(seams, 0.8, rough)
    # Vent slots on the top-right plate.
    vents = rect(u, v, 0.6, 0.1, 0.9, 0.34) & (np.sin(v * math.pi * 2 * 40) > 0.2)
    height = np.where(vents, 0.2, height)
    color = lerp_color(vents.astype(float), color, (0.04, 0.04, 0.05))
    # Hazard strip along the bottom-left plate.
    hazard = rect(u, v, 0.03, 0.9, 0.47, 0.97)
    stripes = ((u + v) * 22 % 1) < 0.5
    color = np.where(hazard[..., None], np.where(stripes[..., None], np.array([0.95, 0.72, 0.05]), np.array([0.04, 0.04, 0.04])), color)
    metal = np.where(hazard, 0.1, metal)
    rough = np.where(hazard, 0.6, rough)
    dirt = np.clip(grime * 1.1 - 0.2, 0, 1)
    color = color * (1 - 0.45 * dirt[..., None]) * (0.9 + 0.2 * fine[..., None])
    rough = np.clip(rough + 0.25 * dirt, 0, 1)
    height = height + 0.04 * fine
    return color, normal_from_height(height, 5.0), rough, metal


def residential(size):
    """Weathered block wall with a small window, an AC unit and stains."""
    u, v = coords(size)
    grime = periodic_noise(size, 4, seed=21)
    fine = periodic_noise(size, 60, octaves=3, seed=22)
    blocks = periodic_noise(size, 14, octaves=2, seed=23)
    color = np.zeros((size, size, 3)) + np.array([0.62, 0.6, 0.57])
    height = np.zeros((size, size)) + 0.5
    rough = np.zeros((size, size)) + 0.9
    metal = np.zeros((size, size))
    # Block courses.
    mortar = (np.abs(((v * 8) % 1) - 0.5) > 0.47) | (np.abs((((u * 4) + 0.5 * (np.floor(v * 8) % 2)) % 1) - 0.5) > 0.485)
    color = lerp_color(mortar.astype(float), color * (0.9 + 0.2 * blocks[..., None]), (0.4, 0.39, 0.37))
    height = np.where(mortar, 0.3, height)
    # Window with a lit warm interior and a frame.
    frame = rect(u, v, 0.14, 0.2, 0.52, 0.66)
    glass = rect(u, v, 0.165, 0.225, 0.495, 0.635)
    color = lerp_color(frame.astype(float), color, (0.12, 0.12, 0.13))
    height = np.where(frame, 0.75, height)
    local_v = (v - 0.225) / 0.41
    color = np.where(glass[..., None], np.array([1.0, 0.7, 0.35])[None, None, :] * (0.4 + 0.5 * (1 - local_v[..., None])), color)
    height = np.where(glass, 0.25, height)
    rough = np.where(glass, 0.1, rough)
    bars = glass & ((np.abs(((u - 0.165) / 0.33 * 5) % 1 - 0.5) > 0.44))
    color = lerp_color(bars.astype(float), color, (0.06, 0.06, 0.07))
    height = np.where(bars, 0.8, height)
    metal = np.where(bars | frame, 0.7, metal)
    # AC unit with a grille.
    ac = rect(u, v, 0.64, 0.5, 0.86, 0.7)
    grille = ac & (np.sin(u * math.pi * 2 * 70) > 0.3)
    color = lerp_color(ac.astype(float), color, (0.7, 0.72, 0.74))
    color = lerp_color(grille.astype(float), color, (0.25, 0.26, 0.28))
    height = np.where(ac, 0.85 - 0.15 * grille, height)
    metal = np.where(ac, 0.6, metal)
    rough = np.where(ac, 0.5, rough)
    # Rust stain dripping from the AC, overall grime.
    drip = rect(u, v, 0.7, 0.7, 0.8, 1.0) * np.clip(1 - (v - 0.7) / 0.3, 0, 1) * (0.5 + 0.5 * np.sin(u * 90) ** 2)
    color = lerp_color(drip * 0.45, color, (0.35, 0.17, 0.08))
    dirt = np.clip(grime * 1.2 - 0.25, 0, 1)
    color = color * (1 - 0.4 * dirt[..., None]) * (0.9 + 0.2 * fine[..., None])
    height = height + 0.05 * fine
    return color, normal_from_height(height, 4.0), rough, metal


def asphalt(size):
    """Dark wet asphalt: aggregate, slab joints, cracks and glossy puddles."""
    u, v = coords(size)
    aggregate = periodic_noise(size, 120, octaves=2, seed=31)
    patches = periodic_noise(size, 3, octaves=3, seed=32)
    cracks_noise = periodic_noise(size, 8, octaves=4, seed=33)
    cracks = np.clip(1 - np.abs(cracks_noise - 0.5) / 0.02, 0, 1) * (patches > 0.4)
    joints = ((np.abs(u - 0.5) > 0.497) | (np.abs(v - 0.5) > 0.497)).astype(float)
    cracks = np.maximum(cracks, joints)
    puddles = np.clip((patches - 0.6) * 5, 0, 1)
    base = 0.11 + 0.04 * aggregate
    color = np.stack([base * 0.95, base, base * 1.12], axis=-1)
    color = color * (1 - 0.6 * cracks[..., None])
    color = color * (1 - 0.25 * puddles[..., None]) + puddles[..., None] * np.array([0.02, 0.03, 0.06])
    height = aggregate * 0.6 - cracks * 0.5 - puddles * 0.3
    rough = np.clip(0.88 - 0.5 * puddles, 0.35, 1)
    metal = np.zeros((size, size))
    return color, normal_from_height(height, 3.0), rough, metal


def pavement(size):
    """Dark concrete pavers (2x2 per tile) with joints, wear and damp patches."""
    u, v = coords(size)
    grime = periodic_noise(size, 4, seed=41)
    fine = periodic_noise(size, 70, octaves=3, seed=42)
    damp = np.clip((periodic_noise(size, 3, octaves=3, seed=43) - 0.62) * 5, 0, 1)
    color = np.zeros((size, size, 3)) + np.array([0.27, 0.28, 0.3])
    height = np.zeros((size, size))
    for row in range(2):
        for col in range(2):
            u0, v0 = col * 0.5 + 0.008, row * 0.5 + 0.008
            paver = bevel(u, v, u0, v0, u0 + 0.484, v0 + 0.484, 0.015)
            height = np.maximum(height, paver)
            shade = (0.9, 1.0, 1.06, 0.95)[row * 2 + col]
            color = np.where((paver > 0)[..., None], color * shade, color)
    joints = height < 0.05
    color = lerp_color(joints.astype(float), color, (0.08, 0.08, 0.09))
    dirt = np.clip(grime * 1.1 - 0.25, 0, 1)
    color = color * (1 - 0.35 * dirt[..., None]) * (0.9 + 0.2 * fine[..., None])
    color = color * (1 - 0.3 * damp[..., None])
    height = height * 0.8 + 0.05 * fine
    rough = np.clip(0.85 - 0.45 * damp + 0.1 * joints, 0.3, 1)
    metal = np.zeros((size, size))
    return color, normal_from_height(height, 4.0), rough, metal


# Sets whose metalness is all zero skip that map (fewer images to upload).
METALLIC_SETS = {"Facade", "Panels"}

SETS = {
    "Facade": facade,
    "Panels": panels,
    "Residential": residential,
    "Asphalt": asphalt,
    "Pavement": pavement,
}


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    out_dir = args[0]
    size = int(args[1]) if len(args) > 1 else SIZE
    os.makedirs(out_dir, exist_ok=True)
    for name, builder in SETS.items():
        color, normal, rough, metal = builder(size)
        base = os.path.join(out_dir, "Reality2059Cyber_%s_" % name)
        save(base + "Color.png", color)
        save(base + "Normal.png", normal)
        save(base + "Roughness.png", rough)
        if name in METALLIC_SETS:
            save(base + "Metalness.png", metal)
        elif os.path.exists(base + "Metalness.png"):
            os.remove(base + "Metalness.png")


try:
    main()
except Exception:
    args = sys.argv[sys.argv.index("--") + 1:]
    with open(os.path.join(args[0], "error.txt"), "w") as f:
        f.write(traceback.format_exc())
    raise
