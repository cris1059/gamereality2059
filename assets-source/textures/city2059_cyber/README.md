# REALITY 2059 — Texturas cyberpunk de City2059

Texturas 100 % procedurales (sin imágenes externas), generadas por [scripts/generate_cyber_textures.py](../../../scripts/generate_cyber_textures.py):

```
blender -b --python scripts/generate_cyber_textures.py -- assets-source/textures/city2059_cyber 1024
```

Las UV de la ciudad son proyecciones a escala de mundo (~8.26 repeticiones por unidad glTF, V hacia abajo en las paredes), así que **cada repetición mide ~7.3 studs** a escala 60: un piso de edificio, siempre derecho.

| Plantilla | Mallas | Tinte | Imágenes |
|---|---|---|---|
| `Facade` | Torres (`.009`, `.021`, `.022`) | No | Color, Normal, Roughness, Metalness |
| `Panels` | Monorriel, plataformas, guarniciones (`.008`, `.007`, `.027`) | Color de la pieza | Color, Normal, Roughness, Metalness |
| `Residential` | Casas (`.020`, `.025`) | Color de la pieza | Color, Normal, Roughness |
| `Asphalt` | Calles, camellones y postes (`.011`) | No | Color, Normal, Roughness |
| `Pavement` | Plazas, banquetas y losa base (`.004`, `.005`, `.003`) | No | Color, Normal, Roughness |

Archivos: `Reality2059Cyber_<Plantilla>_<Mapa>.png` (17 imágenes, 1024×1024). Los mapas normales usan la convención OpenGL (verde = arriba), la que usa Roblox.

## Instalación en Studio (modo edición)

1. Command Bar:
   ```lua
   local T = require(game.ServerScriptService.CyberpunkOnlineServer.Services.CityTextureTool)
   T.Prepare()
   ```
   Crea `ServerStorage > TexturasCyber` con 5 SurfaceAppearance vacíos.
2. Selecciona cada plantilla y, en **Propiedades**, elige sus imágenes en `ColorMap`, `NormalMap`, `RoughnessMap` y (solo Facade y Panels) `MetalnessMap`. Studio las sube a tu cuenta.
3. Command Bar:
   ```lua
   T.Install()
   ```
   Copia cada plantilla a sus mallas (`CyberSurface`) con el tinte correcto. `T.Remove()` las quita. Todo se puede deshacer con Ctrl+Z.
4. Guarda el lugar.

Las ventanas encendidas de la textura no brillan de noche (Roblox no tiene mapa emisivo); el brillo nocturno lo dan las ventanas de neón del modelo, que el ciclo de día y noche ya enciende.
