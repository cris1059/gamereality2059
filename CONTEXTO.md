# REALITY 2059 — Contexto del proyecto

Estado de trabajo para retomar el proyecto en cualquier sesión. El detalle técnico de cada fase está en [README.md](README.md); este archivo resume **qué estamos haciendo, cómo está armado y qué sigue**.

> **Lobby, MorphLab y multijugador (5 vs 5, armas, combate, mapas): ver [CONTEXTO_MULTIJUGADOR.md](CONTEXTO_MULTIJUGADOR.md)**, más reciente que este archivo en esos temas.

_Última actualización: 24/10/2026._

## Qué es

Juego de Roblox de mundo abierto, competitivo y rápido, ambientación cyberpunk (NEO-EDEN, año 2059). Se construye **por fases**, una a la vez, sin adelantarse.

- **Herramientas:** Roblox Studio + VS Code + Rojo + Luau; Blender (modo consola) para los modelos 3D.
- **Idioma:** todo lo que ve el jugador va en **español**; los ids internos y el código en inglés.
- **Lugar de trabajo en Studio:** `Place1.fixed.rbxlx`. Tiene **StreamingEnabled activado** (ver Reglas).

## Flujo del jugador

```
PANTALLA DE TÍTULO (INICIAR, animada) → (jugador nuevo) MORPHLAB → guarda en servidor → HUB
                                      (jugador existente) ─────────────────────────→ HUB
HUB = el lobby 3D ES el menú principal: JUGAR · PERSONAJE · ESCUADRÓN · AJUSTES · CRÉDITOS (Q/E o L1/R1)
  JUGAR: un solo lugar para los modos → MODO LIBRE · PARTIDA RÁPIDA · COMPETITIVO (estado real de cada uno)
  Botón principal (abajo a la derecha) dice lo que hará: JUGAR / ESTOY LISTO / ESPERANDO / BUSCAR PARTIDA / CANCELAR / NO DISPONIBLE
  ESCUADRÓN = lo multijugador (hasta 4): integrantes, invitar, sacar, salir. Franja del escuadrón siempre visible abajo.
  PERSONAJE → EDITAR EN MORPHLAB (Esc vuelve sin guardar) · HUD del modo libre (MENÚ) → HUB
  PARTIDA: buscando → PARTIDA ENCONTRADA (aceptar/rechazar) → carga → sala → resultados → VOLVER AL LOBBY
```
Hub: [HubUI.luau](src/client/Lobby/HubUI.luau) (vista) + [LobbyController.luau](src/client/Lobby/LobbyController.luau) (estado, cámara por pestaña, tinte por modo). El menú 2D anterior y `LobbyUI` se eliminaron (24/10/2026). `DevConfig.QuickStart` = `false`.

## Hoja de ruta actual: Competitivo y Partida rápida (desde el 26/10/2026)

El modo libre queda para después. Fases (el usuario valida cada una): **1** menú y flujo de partida · **2** servidor de partida (estados, equipos, reaparición) · **3** combate base y cámara · **4** habilidades por clase (5 clases, 2 c/u) · **5** modos (Rápida = combate por equipos 4v4; Competitivo = rondas de eliminación 4v4, primero a 6) · **6** primer mapa en bloques de prueba · **7** rango y progreso · **8** pulido y assets.

**Fase 1 (hecha, sin probar en Studio):** flujo `buscando → PARTIDA ENCONTRADA (aceptar/rechazar, 15 s) → cargando → sala de partida → resultados → volver al lobby`.
- Reglas puras en `Party/PartyCore` (`beginMatch`, `acceptMatch`, `declineMatch`, `expireMatch`, `launchMatch`, `returnToLobby`); el servidor (`PartyService`) es dueño del estado y las acciones `accept_match`, `decline_match`, `return_lobby`; pantallas en `Party/MatchOverlay`.
- **Simulación solo para Studio** (`PartyConfig.StudioSimulation`): sin place de partidas configurado, buscar "encuentra" una partida simulada a los 4–7 s y recorre carga, sala y resultados con equipos de relleno. Está rotulada "SIMULACIÓN DE STUDIO" y no inventa estadísticas. En un servidor publicado nunca corre.
- **Pendiente real:** aceptación entre escuadrones distintos (hoy cada escuadrón acepta por su lado y luego viaja), publicar, y que el servidor reservado arranque en "modo partida" leyendo `TeleportData` (fase 2). Se puede usar el mismo place (`PlaceIds` = el id de este place) con `ReserveServer`.

## Estética del hub y pruebas cerradas (26/10/2026)

- **Look nocturno del hub** (`LobbyConfig.Look`, aplicado en cliente y restaurado al salir): iluminación púrpura, bloom, gradación de color y profundidad de campo sobre la ciudad. **Pon `Lighting.Technology = Future` en Studio** (no se puede cambiar por script): sin eso se pierden las sombras de los focos y los reflejos del piso; el juego avisa en la consola.
- **Escena** (`LobbySceneBuilder`, `LobbyConfig.Lighting` y `.Rain`): dos focos frontales compartidos (con sombras), un contraluz por personaje del color de su anillo; lluvia con salpicaduras. La lluvia usa la textura de destellos del motor estirada: una textura de gota propia se vería mejor.
- **Composición como la imagen de referencia (SceneVersion 4, 26/10/2026):** los 5 juntos en una línea curva (`SquadSlots` a 3.2 studs, anillos de 3 studs: cian, rojo, magenta = tú, amarillo, cian), cámara que los encuadra a la derecha del menú (`LobbyConfig.Camera`/`CameraPresets`). Piso mojado: reflejos pintados autoiluminados bajo cada anillo y del neón de la ciudad (`LobbyConfig.Reflections`). El lobby se puso más alto y más lejos de la ciudad (`CityHeightFraction` 0.72, `CityFrontGap` 70) para ver el skyline con cielo encima: **se ajusta mirando el juego**.
- **Skyline del menú** (`LobbySkyline`, en `ReplicatedStorage.CyberpunkOnline.Runtime`): ventanas iluminadas (las texturas `Reality2059Windows_*` ya subidas, autoiluminadas), franjas de neón y letreros verticales en las paredes de la ciudad que mira la cámara, columnas de luz y el portal (colocado por ángulo desde la cámara para que siempre salga en el cielo). El cliente lo clona solo mientras el hub está abierto: el modo libre no lo ve.
- **UI del hub como la imagen:** logo grande con lema, columna izquierda con las tarjetas de modo y el botón JUGAR debajo, tarjeta de ubicación NEO-EDEN abajo a la izquierda, panel de escuadrón con retratos abajo a la derecha.
- **Posturas** (`Character/R15Pose:SetStance`, `LobbyConfig.Stances` / `StanceBySlot`): tú "confident", anillo 1 mano abierta, 2 brazos cruzados, 3 mano a la cara, 4 relajado, en las articulaciones R15. Valores puestos a ojo: **hay que ajustarlos mirando el juego**. Cubiertas por `AvatarTests`.
- **Cámara** con deriva lenta (`LobbyConfig.CameraDrift`) para dar paralaje.
- **Línea de amigos de prueba** solo en Studio: `DevConfig.PreviewSquad = true` llena los anillos vacíos con personajes al azar (decorado, no entran al escuadrón).
- **Pruebas cerradas:** `Config/AccessConfig` + `Services/AccessService`: con `Enabled = true`, un servidor publicado expulsa a quien no esté en `UserIds`/grupo. Apagado por defecto; Studio nunca se restringe.

## Fases terminadas

| Fase | Qué incluye |
|---|---|
| A–B | Infraestructura: Rojo, datos del jugador con **MockDataStore**, estados (cargando / nuevo / existente / error). |
| C (MORPHLAB) | Creador de personaje. **Desde el 26/10/2026 sobre avatares R15 estándar de Roblox** (ver "Personaje"): **CUERPO** (clásico/esbelto, altura, ancho, cabeza, 10 tonos de piel), **ROSTRO** (12 caras clásicas), **CABELLO** (13 peinados del catálogo + calvo), **ROPA Y ACCES.** (6 atuendos de ropa por capas + 10 accesorios: visores, cuernos, audífonos, máx. 3), **IMPLANTES** (6 piezas de cyberware propias), **CLASE** (5 roles con estadísticas), **COLOR** (neón principal/secundario, acabado metálico). HUD 3D inclinado, iconos 3D, miniaturas del catálogo. ENTRAR A LA REALIDAD aparece cuando se editaron las 7 secciones. |
| D (Lobby) | Lobby estilo Fortnite sobre una azotea frente a la ciudad. Los anillos del escuadrón quedan vacíos para jugadores invitados. |
| E.1 (Modo libre) | La ciudad jugable, el personaje caminando y corriendo, día y noche. **En curso** (ver abajo). |

## Arquitectura (dónde está cada cosa)

- `src/shared` → `ReplicatedStorage.CyberpunkOnline` (configs, catálogo, validación, animador, ciclo de día).
- `src/server` → `ServerScriptService.CyberpunkOnlineServer` (servicios, datos, pruebas, `World/City2059Data`).
- `src/client` → `StarterPlayerScripts.CyberpunkOnlineClient` (MorphLab, Lobby, FreeRoam, UI).
- Escenas generadas en Play: `Workspace/Reality2059Runtime/{MorphLab, Lobby, FreeRoam}`.

**Personaje (avatar R15 estándar desde el 26/10/2026; el rig Quaternius se eliminó)**
- Datos: `CharacterDraft` (setters validados) + `CharacterValidator` (el servidor valida todo). Formato `avatarVersion = 2`: cuerpo, piel, cara, cabello, atuendo, accesorios, implantes, escalas (altura/ancho/cabeza 0..1), clase, colores. Esquema de datos **v3**: un personaje del rig viejo se reemplaza por el predeterminado y el jugador vuelve a MORPHLAB (`PlayerMigrations[2]`).
- Catálogo: [CharacterCatalog.luau](src/shared/Catalog/CharacterCatalog.luau). Cabello, caras, ropa por capas y accesorios son **artículos reales del catálogo de Roblox** (IDs verificados con la API pública y sus miniaturas el 26/10/2026); se aplican con `HumanoidDescription`, así que el jugador no necesita tenerlos. Si un artículo deja de cargar, el servidor usa el cuerpo sin artículos. Para cambiar la selección: agregar IDs al catálogo (solo agregar; quitar un id invalida personajes guardados).
- `Character/AvatarDescription`: borrador → `HumanoidDescription` (proporciones de bloques: BodyType y Proportion en 0). La **cara** no va en el modelo del servidor: se pinta la imagen de la cara (`FaceInfo.imageId`, sacada del propio artículo) en el decal `face` de la cabeza (`ApplyFace`), en cliente y en el personaje real.
- Iluminación de MorphLab y del hub bajada para avatares de plástico claro (focos 1.2–3, exposición ~0, bloom solo para neón: `Threshold` > 1). Con los valores del rig viejo el R15 se quemaba a blanco.
- Servidor `Services/AvatarService`: arma los modelos de vista previa (solo artículos, caché en `ReplicatedStorage.CyberpunkOnline.Runtime/AvatarModels`, remote `AvatarModel`), el grupo de looks de peatones (`Runtime/PedestrianLooks`) y el **personaje real** del jugador (`LoadCharacterWithHumanoidDescription` + cyberware).
- Cliente `MorphLab/AvatarPreview`: clona el modelo del servidor y pinta localmente piel, escalas y cyberware (cambios instantáneos); MorphLab, anillos del lobby y peatones.
- `Character/R15Cyberware`: implantes propios soldados a las partes R15 (cabeza, torso, antebrazo derecho), en servidor y cliente.
- `Character/R15Pose`: animación procedural de los rigs sin jugador (idle, caminar, posturas del lobby) escribiendo `Motor6D.Transform`. El personaje real usa la animación normal de Roblox.

**Modo libre**
- Servidor: `CityWorldService` (encuentra, escala y colorea la ciudad; crea el piso, los muros del borde y los puntos de aparición) y `FreeRoamService` (el jugador aparece como su avatar R15 vía `AvatarService`, remotes `EnterFreeRoam` / `LeaveFreeRoam`, época del reloj). Ya no hay cápsula invisible: las banquetas de 2–3 studs pueden requerir saltar.
- Cliente: `FreeRoamController`, `FreeRoamLighting` (día y noche), `FreeRoamHUD`.
- Config: [FreeRoamConfig.luau](src/shared/Config/FreeRoamConfig.luau) (escala, posición, colisiones, movimiento, día y noche).

**Sistemas agregados el 24/10/2026** (pendientes de prueba en Studio salvo lo indicado)
- **Cámara** (`FreeRoamConfig.Camera`): tercera persona fija a 7 studs sobre el hombro (personaje a la derecha; Q cambia de lado), V primera persona, sin zoom con la rueda, colisión propia contra `City2059/Colisiones`.
- **Inventario** (I / Y / botón): `InventoryConfig` (catálogo vacío), `InventoryService` (servidor dueño, guarda en el perfil), `InventoryController`. Esquema de datos **v2** (`inventory.items`, `inventory.equipped`; migración 1→2 automática).
- **Escuadrones** (hasta 4): `Party/PartyCore` (reglas), `PartyService` (remotes `PartyRequest/Update/Invite/Launch`), cliente `Party/PartyController` (estado, solicitudes, disponibilidad de modos e invitaciones en cualquier pantalla; la vista está en el hub). Los compañeros aparecen en los anillos del lobby.
- **Emparejamiento** (`Party/MatchmakingService`): cola en MemoryStore por modo, agrupa escuadrones completos, `ReserveServer` + `TeleportAsync`. **Requiere** publicar, un place de partidas y su id en `PartyConfig.Matchmaking.PlaceIds` (hoy 0 → responde "no configurado"). En Studio no teletransporta.
- **Ciudad viva** (`CityLife` → `CityTraffic` + `CityPedestrians`, red `World/CityStreets`, config `CityLifeConfig`). La red de calles **se detecta de la geometría real** con [build_city2059_streets.py](scripts/build_city2059_streets.py) → `World/City2059Streets` (generado): calles = malla de asfalto `Cuberpunk2077.005` a nivel de calle menos edificios; banquetas = superficie elevada `Cuberpunk2077.003`. Esqueleto de cada calle → grafo de cruces (47) y tramos; carriles a la derecha (1–2 por sentido según el ancho), curvas de cruce que solo se aceptan si quedan sobre el asfalto, glorieta central de un sentido (antihorario) que cede el paso, semáforos de 2 fases en 16 cruces (reloj del servidor: todos los jugadores ven lo mismo), vueltas en U en calles sin salida. Aéreos: carriles sobre las calles con la altura del obstáculo debajo (suben antes del monorriel). Peatones: avatares R15 al azar (`Character/RandomCharacter`, looks armados por `AvatarService`) en las banquetas, cruzan en 25 pasos peatonales cuando el semáforo detiene esa calle el tiempo suficiente. Los pies y las llantas usan la altura exacta de la superficie. Local en cada cliente. El servidor publica la transformación (`CityRef*` en el modelo FreeRoam). Los carriles mantienen 3.6 studs de cualquier banqueta, pilar o poste (los pilares del monorriel se esquivan; postes de ≤8 celdas se ignoran) y los autos se detienen antes de los pasos peatonales. **Ojo:** en un Model con PrimaryPart, `WorldPivot` se ignora; el pivote va en `PrimaryPart.PivotOffset` (era la causa de los autos hundidos). Al arrancar, `CityLife` verifica la altura de la red contra el piso y la corrige si hiciera falta (mensaje "Calles: altura verificada" en la consola).
- **Calidad gráfica** (`GraphicsConfig`, CONFIGURACIÓN): Auto/Baja/Media/Alta → sombras, bloom, niebla y densidad de la ciudad.
- **Caídas**: el servidor devuelve al jugador a su último punto seguro si cae 25 studs bajo el piso; antes de aparecer pide streaming del área.
- **Guardado**: `Persistence.Backend = "Auto"` → DataStore real si responde; en Studio sin acceso a APIs usa Mock (con aviso). En un servidor publicado nunca cae a Mock.
- **F3**: panel de rendimiento (FPS, ping, memoria, agentes).
- Pruebas nuevas al dar Play: Inventory 5/5, Party 6/6, City life 4/4.

## En qué estamos ahora: la ciudad del modo libre

- La ciudad (`Reality2059_City2059.glb`, unas 30 mallas separadas por material) se importa en Studio. El juego la encuentra aunque tenga otro nombre o esté dentro de carpetas y la renombra `City2059`. El modelo guardado está a escala efectiva 60 (aproximadamente 1,227 × 415 × 1,179 studs). `RescaleCity = false`, por lo que conserva exactamente ese tamaño; las colisiones se calculan usando la escala real. Su centro se mantiene en `CityCenter` (0, 0, -1200).
- **Materiales de la ciudad:** el paquete original no incluía las ocho texturas externas que referencia el `.blend`; el GLB solo conservó una imagen provisional blanca de 1×1. `CityMaterialConfig` asigna de forma segura asfalto, concreto, metal y fachada a los grupos conocidos. Sin assets personalizados usa materiales nativos de Roblox; cuando `MaterialService` contiene las variantes `R2059_Asphalt`, `R2059_Concrete`, `R2059_Metal` y `R2059_Facade` marcadas `Reality2059PBRReady` para su rol, con material base y escala de mosaico correctos, cambia automáticamente al paquete PBR 1024 px de `assets-source/textures/city2059_pbr`. Una variante vacía o mal configurada no se cuenta como PBR. Los neones y los tres grupos UV/alpha ambiguos (`.002`, `.030`, `.031`) no se sustituyen. Nunca se aplican texturas a `City2059/Colisiones`.
- El importador de Roblox **gira la ciudad 180° dentro de las mallas**; el servidor lo detecta solo (`CityAxisSigns`).
- Los colores del GLB se reaplican solo a las piezas que siguen en el gris del importador; lo que se recolorea en Studio se respeta.
- **Colisiones:** las mallas de la ciudad no colisionan (cada una abarca la ciudad entera). Las colisiones son Parts dentro de `City2059/Colisiones`: en Play se vuelven invisibles y sólidas, y se escalan con la ciudad. Las colisiones generadas en Play están apagadas (`GeneratedColliders = false`).
- **Flujo acordado: generar y luego retocar a mano.** En modo edición, en la Command Bar:
  ```lua
  require(game.ServerScriptService.CyberpunkOnlineServer.Services.CityWorldService).GenerateEditableCollision()
  require(game.ServerScriptService.CyberpunkOnlineServer.Services.CityWorldService).AuditEditableCollision()
  require(game.ServerScriptService.CyberpunkOnlineServer.Services.CityWorldService).SetCollisionVisible(false) -- o true
  ```
  Las 14,072 cajas de la versión 5 salen de un mapa de alturas calculado por [build_city2059_data.py](scripts/build_city2059_data.py): 3,570 estructuras y 10,502 superficies transitables. A escala 60, ambas capas tienen resolución horizontal de 1.5 studs; las rampas conservan pasos verticales máximos de 0.75 studs. La lámina transitable mide 0.48 studs de grosor y queda completamente debajo de la geometría visible, por lo que no sobresale sobre calles, banquetas ni rampas. En edición, las estructuras son rojas y las superficies cian solo cuando se activa la inspección; en Play todas son invisibles. Regenerar reemplaza únicamente las cajas con el atributo `GeneratedCollision` y conserva las correcciones manuales.
  **Revisión del 16/10/2026 (auditoría geometría vs. colisión, celdas de 1.5 studs):** alineación exacta con las 30 mallas (0.00 studs), 0 paredes invisibles, 12/12 torres cerradas, 8/8 puntos de aparición válidos. La "zona de estacionamiento" es una granja de paneles solares (bloqueada a propósito: bajo los paneles hay 4.8 studs y el personaje mide 5.7). Datos **v6**: mismas 3,570 estructuras, 8,122 superficies (se quitaron 2,380 a ras de calle que ya cubre el piso; en Play también se podan del lugar guardado con v5). La cápsula usa `HipHeight = 3.2` para subir sola los 82 bordes de 2–3 studs (banquetas, camellón); con eso quedan 0 paredes visibles atravesables.
- **Día y noche:** `DayCycle` en la config (`DaySeconds` 600, `NightSeconds` 300, `StartClockTime` 8.5, `FixedClockTime` para dejar una hora fija). La apariencia de cada hora está en `LightingKeys`. Las ventanas se encienden de noche.
- **Movimiento:** caminar 16, correr 28 (Shift o botón CORRER), salto 50; reaparece a los 3 s si cae.

## Pendientes y próximos pasos

1. Hacer una última prueba manual a pie en Studio por calles, banquetas, rampas, escaleras, azoteas y entradas; la generación y la auditoría automática v5 ya están completas.
2. ~~Reimportar los FBX de ropa Quaternius~~ (ya no aplica: avatares R15 estándar desde el 26/10/2026). Los modelos viejos de `ServerStorage` (UniversalBase*) se pueden borrar del place.
3. La plataforma del lobby flota frente a la ciudad y se ve desde las calles: decidir si se mueve o se oculta en el modo libre.
4. ~~Guardar el personaje al confirmar~~ (hecho 24/10/2026).
5. Ronda de depuración en Studio de todo lo del 24/10/2026 (ver arriba).
6. Para emparejamiento real: publicar, crear el place de partidas y poner su id en `PartyConfig`.
7. Animaciones: pulir giros y transiciones con retroalimentación visual; reemplazar los peatones provisionales por modelos reales.
8. Después: contenido del modo libre (interacciones, PvP) y el juego dentro del place de partidas.

## Reglas del proyecto

- Construir **fase por fase**; no adelantarse ni reestructurar sin consultar.
- Persistencia en modo **Auto** (autorizado el 24/10/2026): DataStore real cuando responde, Mock solo en Studio sin acceso a APIs. Publicar el juego sigue siendo decisión del usuario.
- Cambios no destructivos: lo que hace el juego con la ciudad y las escenas ocurre en Play, no modifica el lugar guardado.
- **StreamingEnabled:** toda escena que el cliente deba ver sin un personaje cerca (MorphLab, lobby, ciudad, piso) va con `ModelStreamingMode = Persistent`.
- Los callbacks de la UI de MorphLab van siempre dentro de `BindControls`.
- Cada fase agrega pruebas que corren al dar Play en Studio (por ejemplo `Free roam tests passed: 5/5`) y una sección en el README.

## Texturas cyberpunk de la ciudad

5 juegos de texturas procedurales (fachada con ventanas, paneles industriales, residencial, asfalto mojado, losetas) en [assets-source/textures/city2059_cyber](assets-source/textures/city2059_cyber/README.md). Cada repetición mide ~7.3 studs (un piso). Instalación en Studio con `CityTextureTool`: `Prepare()` → elegir imágenes en Propiedades → `Install()`. **Pendiente: el usuario sube las 17 imágenes.**

## Identidad por edificio

Las 26 torres comparten malla, así que la textura se repite igual. Cada torre recibe además (al dar Play) su marca ficticia y color: pantalla principal animada, pantalla promocional, tiras de neón en sus esquinas reales y letrero en la azotea. Datos de paredes: `scripts/build_city2059_dressing.py` → `World/City2059Dressing`; estilos en `Config/CityDressingConfig`; servicio `CityDressingService`; animación cliente `CityDressingFX`.

## Fachadas por torre (KitBash3D Neo City)

Cada una de las 26 torres se forra con **su propio material** del pack KB3D (26 materiales, ninguno repetido), liso, sin patrón de ventanas. IDs en `World/CityFacadeConfig.AssetIds` (nombres originales `KB3D_NEC_*`); instalación con `CityTextureTool.InstallFacades()`, que verifica cada ID por su nombre. El pack KB3D tiene licencia del usuario; no publicar los archivos fuera del juego.

## Inicio rápido en Studio

[DevConfig.luau](src/shared/Config/DevConfig.luau): `QuickStart` = `"FreeRoam"` (actual), `"Lobby"`, `"MorphLab"` o `false` (menú normal). Solo aplica en Studio. Lobby y modo libre usan el personaje de prueba `DevConfig.Character`.

## Comandos útiles

- Compilar y verificar: `./tools/rojo/rojo.exe build default.project.json -o <salida>.rbxlx`
- Blender en consola: `blender-launcher.exe -b <archivo.blend> --python <script> -- <args>`
- Datos de colisión de la ciudad: `blender -b --python scripts/build_city2059_data.py -- <city.glb> src/server/World/City2059Data.luau <reporte.json>`
- Ropa: `scripts/generate_outfits.py` · Cabello: `scripts/generate_hair.py`, `scripts/rig_hair.py` · Rig facial: `scripts/rig_face_bones.py`
- Red de calles (Python 3 puro, sirve el de LibreOffice): `"C:\Program Files\LibreOffice\program\python.exe" scripts/build_city2059_streets.py src/assets/environment/city2059/Reality2059_City2059.glb src/server/World/City2059Data.luau src/shared/World/City2059Streets.luau <carpeta_debug>` → imágenes `1_graph.png`, `2_lanes.png` (carriles, curvas; magenta = carril sin salida), `3_walkways.png`, `4_air.png`. Volver a correrlo si cambia la ciudad o sus colisiones. El Blender de la Microsoft Store no se puede ejecutar desde la terminal.
