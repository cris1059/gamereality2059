# REALITY 2059 — City2059 PBR material pack

This folder replaces the texture files that were absent from the purchased city archive. The original `.blend` refers to eight external files (`Meshpart2`, `Meshpart28`, `Meshpart32` and `Meshpart35`, each with `_diff` and `_nmap` variants), but none are included or packed into the Blender file. The exported GLB therefore contains only one white `1×1` placeholder image.

## Deliverables

Four reusable, tileable material sets are included:

- `Reality2059_Asphalt_*`
- `Reality2059_Concrete_*`
- `Reality2059_Metal_*`
- `Reality2059_Facade_*`

Each set contains:

- `Color.png` — 1024×1024 albedo/color.
- `Normal.png` — 1024×1024 OpenGL tangent-space normal map (green/+Y points up).
- `Roughness.png` — 1024×1024 grayscale roughness.
- `Metalness.png` — 1024×1024 grayscale metalness.

The source albedos named `city_*_albedo.png` are retained for provenance. `manifest.json` is the machine-readable inventory. The final maps were resampled to 1024×1024 and edge-matched before deriving normal, roughness and metalness, so repeating borders do not create a hard color seam.

## Roblox names and settings

Create these `MaterialVariant` objects below `MaterialService`. After importing and assigning all four maps, add the Boolean attribute `Reality2059PBRReady = true` and the string attribute `Reality2059MaterialRole` with the role in the first column. Roblox protects map IDs from server scripts, so this explicit Studio-authored marker records that the four maps were reviewed. `CityWorldService` also verifies the base material and `StudsPerTile`; otherwise it keeps the safe built-in material and reports the reason in Output.

| Role attribute | Variant | Base material | Studs per tile | Maps |
| --- | --- | --- | ---: | --- |
| `Asphalt` | `R2059_Asphalt` | Asphalt | 16 | `Reality2059_Asphalt_*` |
| `Concrete` | `R2059_Concrete` | Concrete | 12 | `Reality2059_Concrete_*` |
| `Metal` | `R2059_Metal` | Metal | 10 | `Reality2059_Metal_*` |
| `Facade` | `R2059_Facade` | Metal | 12 | `Reality2059_Facade_*` |

Do not apply these maps to `City2059/Colisiones`. Emissive city groups remain `Neon`. The three special groups `Cuberpunk2077.002`, `.030` and `.031` deliberately retain their imported state because their missing source images could have contained transparency, road markings or prop-specific art.

## Generation record

Mode: separate image generation followed by deterministic PBR derivation.

- Asphalt prompt: seamless square dark wet urban asphalt, PBR-style top-down albedo scan, charcoal and blue-gray gravel, microcracks and tire abrasion; no markings, puddles, perspective, text or logos.
- Concrete prompt: seamless cool-gray architectural concrete, PBR-style albedo with pores, aggregate, hairline wear and rain grime; neutral flat lighting; no graffiti or text.
- Metal prompt: seamless dark industrial gunmetal cladding with brushed grain, oxidation, scuffs, micro-scratches and subtle modular seams; neutral lighting; no chrome, neon or text.
- Facade prompt: seamless matte near-black navy/graphite composite facade panels with rain streaks, grime and wear; neutral lighting; no windows, signs, neon or text.

These are project-bound generated assets for REALITY 2059. Review them in Studio under both daytime and nighttime lighting before final publication.
