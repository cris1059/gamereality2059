# REALITY 2059

Proyecto Roblox/Rojo con una base multijugador y la Fase B de ingreso de jugadores. **REALITY 2059** es el nombre oficial del videojuego. La persistencia activa es simulada: `GameConfig.Persistence.Backend` permanece en `"Mock"`. El adaptador para `DataStoreService` existe, pero no se conecta mientras esa opción no se cambie deliberadamente.

## Compatibilidad del cambio de identidad

El nombre público anterior fue sustituido sin renombrar identificadores técnicos existentes. Se conservan deliberadamente `ReplicatedStorage/CyberpunkOnline`, `CyberpunkOnlineServer`, `CyberpunkOnlineClient`, `CyberpunkBootstrapUI` y `CyberpunkOnline_PlayerData_v1`. Esos nombres funcionan como rutas o identificadores internos; modificarlos requeriría una migración coordinada y, en el caso del DataStore, podría separar los datos existentes.

## Fase B

- Estados de ingreso: `LOADING`, `NEW_PLAYER`, `EXISTING_PLAYER` y `DATA_ERROR`.
- Esquema versionado con personaje, inventario y progreso separados.
- Personaje universal R15 con identificadores estables para apariencia, ropa, accesorios, cyberware y escalas corporales.
- Capa `PlayerDataStore` intercambiable y dos proveedores: `MockDataStore` y `RobloxDataStore`.
- Lease de sesión adquirido y verificado dentro de `UpdateAsync`, con expiración, renovación y liberación.
- Un servidor que perdió el lease no puede guardar sobre el propietario nuevo.
- Fallos de lectura y conflictos se cierran como `DATA_ERROR`; nunca se convierten en jugador nuevo.
- Cambios de personaje validados en el servidor contra el catálogo compartido y protegidos por límite de solicitudes.
- Interfaz provisional cyberpunk de estado. No incluye el editor completo ni el lobby definitivo.

## Estructura relevante

```text
src/
  client/                         interfaz provisional y consumo de estados
  server/
    Data/                         contrato, esquema, migraciones y proveedores
    Services/                     sesiones, ingreso, validación y rate limiting
    Tests/PhaseBTests.luau        pruebas automatizadas de la Fase B
    Util/                         copia profunda de datos simulados
  shared/
    Catalog/                      IDs de personalización permitidos
    Config/                       backend y parámetros de persistencia
    Network/                      nombres de remotos
    State/                        estados de ingreso
    Types/                        contratos de datos sin Instances de Roblox
    Validation/                   validación autoritativa de personaje
```

## Ejecutar y validar

1. Ejecuta `scripts\start-rojo.cmd` y conecta el plugin Rojo a `localhost:34872`.
2. En Roblox Studio abre la pestaña **Prueba**.
3. Selecciona **Servidor local**, establece **2 jugadores** y pulsa **Iniciar**.
4. En la ventana del servidor abre **Vista > Salida**.
5. Deben aparecer:
   - `Phase B tests passed: 7/7`
   - `[REALITY 2059] Server infrastructure ready (Mock)`
6. No debe aparecer ninguna traza roja de servidor o cliente.

Las siete pruebas cubren jugador nuevo, error de lectura sin escritura, guardado y recarga como jugador existente, conflicto de sesión, recuperación de lease expirado con rechazo del escritor antiguo, rechazo de personalización inválida y migración de esquema.

`NEW_PLAYER`, `EXISTING_PLAYER` y `DATA_ERROR` se validan automáticamente en `PhaseBTests.luau`. `LOADING` se observa al arrancar cada cliente antes de que el servidor resuelva la carga. Como el `MockDataStore` de ejecución es efímero, una sesión manual normal empieza como jugador nuevo; la persistencia entre ejecuciones se incorporará mediante un escenario de pruebas o el backend real únicamente con autorización.

## Restricción de seguridad

No publiques el juego ni habilites **Enable Studio Access to API Services** para esta fase. No cambies el backend a `"DataStoreService"` sin autorización y sin probar primero en una experiencia separada de producción.

## Fase C.1 — MORPHLAB // 2059

La primera instalación visual del creador se genera de forma idempotente en ejecución bajo `Workspace/Reality2059Runtime/MorphLab`. Está separada en `Architecture`, `Platform`, `Scanner`, `Lighting`, `Decorations` y `Cameras`. El generador no modifica ni elimina contenido preexistente de `Workspace`.

Para un jugador `NEW_PLAYER`, el cliente activa una cámara cinematográfica y la interfaz base de MORPHLAB. Todas las categorías y acciones de personalización permanecen marcadas como bloqueadas durante C.1; todavía no guardan ni modifican personajes. `EXISTING_PLAYER` no abre el laboratorio y `DATA_ERROR` mantiene bloqueada la creación.

La escena se genera en runtime para preservar el mapeo conservador de Rojo y evitar administrar de forma destructiva el `Workspace` existente. Durante una prueba puede inspeccionarse desde Explorer y cada grupo está preparado para ser sustituido posteriormente por modelos propios.

## Fase C.2 — Personaje universal y controles de visualización

MORPHLAB genera en cada cliente un único preview neutral R15 mediante `Players:CreateHumanoidModelFromDescriptionAsync`. El modelo se crea localmente, se ancla sobre `CharacterSpawn`, no colisiona, no utiliza la apariencia del usuario y se destruye al cerrar el laboratorio. El servidor y los demás clientes no reciben esa instancia.

La creación está detrás de `PreviewCharacterFactory`, de modo que la implementación Roblox R15 puede sustituirse más adelante sin reescribir `MorphLabController`. Están activos los controles de rotación por botones y arrastre, zoom limitado por botones o rueda, y restablecimiento conjunto. Confirmación y personalización permanecen bloqueadas.

### Requisitos para un futuro rig de Blender

- Exportación y jerarquía compatibles con los quince segmentos R15, o un adaptador explícito.
- `Humanoid`, `HumanoidRootPart`, `Motor6D` y nombres de partes previsibles.
- Pivot, escala y orientación compatibles con `CharacterSpawn`.
- Attachments correctos para cabello, rostro, ropa rígida y accesorios.
- Skinning y huesos compatibles con el pipeline elegido; no se presupone conversión automática a R15.
- Animaciones propias verificadas y con derechos de uso.
- Materiales y texturas optimizados para Roblox.
- Presupuesto definido de triángulos, texturas, memoria y draw calls antes de sustituir la base.

## Próximo hito — C.3

Construir el creador visual R15 sobre `ValidateCharacterDraft` y `SaveCharacter`, añadir previsualización segura con `HumanoidDescription`, ampliar el catálogo de IDs aprobados y definir el flujo de transición al lobby. El lobby completo y la integración de modelos de Blender quedan fuera de esta fase.
## Phase C.3.1: universal customization draft

MORPHLAB now owns a client-local `CharacterDraft` using the same stable catalog IDs and character shape validated by Phase B. `PlayerSchema` also obtains its default character from this shared factory, preventing schema drift.

Only BASE is enabled. Its verified built-in options are `neutral_light`, `neutral_medium`, and `neutral_dark`; selecting one updates the existing local R15 incrementally through `MorphLabAppearanceController`. The draft survives category navigation for the lifetime of the editor and can be restored to defaults. Hair, face, eyes, clothing, cyberware, and identity confirmation remain locked.

The appearance adapter can also project the draft onto a `HumanoidDescription`, while its current preview path updates `BodyColors` and R15 body parts without rebuilding the model. This contract leaves asset-backed Blender adapters for later phases without changing persistent identifiers.

## Phase C.3.2: Quaternius universal preview

`Reality2059_UniversalBase.rbxm` and `Reality2059_UniversalBaseF.rbxm` remain the versioned source assets, but they are not live-mounted by Rojo. Current Roblox/Rojo live sync can instantiate `MeshPart` objects with empty immutable `MeshId`/`MeshContent`, producing replacement boxes even though `rojo build` preserves the IDs. At runtime the bootstrap copies the Studio-authored models into `ReplicatedStorage/Reality2059Assets/UniversalBaseMale` and `UniversalBaseFemale`; `ReplicatedStorage` uses `$ignoreUnknownInstances` so Rojo preserves them. MORPHLAB selects them with the stable draft IDs `base_male` and `base_female`.

`QuaterniusPreviewFactory` validates the expected meshes, animation controller, and key bones before cloning that Studio-authored template locally. The clone is scaled proportionally to 5.7 studs, placed with its feet on `CharacterSpawn`, made non-collidable, and destroyed with the editor session. The source rig and its 63-bone hierarchy are never modified.

This asset is an animatable custom Quaternius rig, not Roblox R15: it has an `AnimationController` and skinned mesh bones but no `Humanoid`. Therefore it does not claim `HumanoidDescription` compatibility and is not used as the playable avatar. If validation or scaling fails, MORPHLAB logs the reason and uses the existing neutral R15 preview factory.

BASE skin selections remain client-local. On the custom preview they use the runtime `SurfaceAppearance.Color` tint on `SuperHero_Male`; changing only `MeshPart.Color` would be hidden by its opaque PBR `ColorMap`. The stable catalog IDs and R15 adapter remain unchanged. A future texture/material adapter can replace this preview-only tint without changing saved player data. The close camera limit is extended while retaining bounded zoom and reset behavior.

Studio regression output must include `Phase C.3.2 tests passed: 9/9` in addition to the earlier phase summaries. MockDataStore remains the only active persistence backend.

## Phase C.3.3: preview idle, face and asset load check

`QuaterniusIdleAnimator` gives the custom preview a procedural idle (relaxed arms, breathing, subtle sway and head movement) by driving `Bone.Transform` locally on the client. Rotations are derived from the rig's own rest geometry, so both bases work without uploaded animation assets. Tuning lives in `MorphLabConfig.Preview.Idle`; the R15 fallback is not animated.

Before cloning, `QuaterniusPreviewFactory` preloads the template meshes and textures. A body mesh that fails to download would render as a textured box, so it now falls back to R15 with `MESH_LOAD_FAILED` in Output and in the `CustomPreviewFailure` attribute.

The Roblox importer merged `MI_Eyes` and `MI_Hair` into one shared map and left an empty duplicate `SurfaceAppearance` on `Eyes`/`Eyebrows`. The preview clone drops the empty duplicate and renders eyebrows with `MorphLabConfig.Preview.EyebrowColor`. Source templates are not modified.

Studio regression output must include `MorphLab idle tests passed: 6/6`.

## Phase C.3.4: concept-art MORPHLAB

`MorphLabConfig.ForcedEnvironmentVariant` fixes the environment to `CORPORATE_LAB` (set it to `""` to restore the random pick). That variant is rebuilt after the concept art: a receding corridor of neon frames with floating head-scan holograms, a "YOURSELF" graffiti and a distant mannequin behind the character (C.3.6 replaced the original glass cylinder), a platform with concentric neon rings, four stasis pods, a body hologram, wall slogans and floor haze. The large MORPHLAB title is intentionally not built. The other two variants are unchanged.

The stasis pods contain static mannequins cloned from the universal templates. Their relaxed pose is baked into `Bone.CFrame` on the server so it replicates; `QuaterniusIdleAnimator` now lives in `shared/Character` for that reason. The server installs the templates before building the scene.

The MORPHLAB UI follows the same layout: BODY / FACE / HAIR / IMPLANTS / CLASS / COLOR modules (only BODY is active), body cards, seven skin tones, body presets and MUSCLE / HEIGHT / MASS sliders (presets and sliders are visual and locked), RANDOMIZE (body base and skin tone from the catalog, client draft only) and a locked ENTER REALITY. Bloom and color grading are parented to the camera only while MORPHLAB is active.

The catalog appends four skin tone IDs (`neutral_porcelain`, `neutral_sand`, `neutral_tan`, `neutral_deep`); existing IDs and the default `neutral_medium` are unchanged.

## Phase C.3.5: body sliders and softer neon

BODY PRESETS and the two locked body cards were removed. MUSCLE, HEIGHT and MASS are now live and write the draft `bodyScales` (`bodyType`, `height`, `width`; 0..1, 0.5 neutral) through `CharacterDraft.setBodyScale`, so the persisted shape and validation are unchanged. On the Quaternius preview:

- HEIGHT rescales the whole model (`Preview.BodyShape.HeightMin`..`HeightMax`) and keeps the feet on the platform.
- MASS and MUSCLE thicken the body mesh front-to-back and, through `QuaterniusIdleAnimator:SetShape`, widen shoulders and hips with bone translations and let the arms hang wider.

The base mesh has no muscle or fat morphs, so these are approximations; true variants would need dedicated Blender body meshes. RANDOMIZE also randomizes the three scales. The R15 fallback ignores body shape.

Neon glow is softened with `MorphLabConfig.NeonTransparency` (applied to every neon part of the scene) and a lower camera bloom.

## Phase C.3.6: real 3D figures instead of drawn shapes

The body cards show the actual universal bases in a `ViewportFrame` (`WorldModel`), posed with the baked relaxed stance and tinted blue; the frame-drawn silhouette stays only as a placeholder until the templates replicate. The scene's frame-drawn body schematic was replaced by a `BodyHologram`: a posed copy of the male base on a projector, rendered with the `ForceField` material in cyan.

## Phase C.3.7: gestures and hands

`QuaterniusIdleAnimator` adds random gestures blended over the idle every `GestureIntervalMin`..`GestureIntervalMax` seconds: fists (with arm tension), palm look (one hand raised, wrist turned so the open palm faces the eyes, then closed into a fist), look around (torso and head turn), inspect hand (raised forearm, opening and closing the fist) and neck roll. Fingers now keep a relaxed curl (`FingerRelaxDegrees`) and close to `FistCurlDegrees`; the curl axis is derived from the palm side, inferred from the thumb base. The elbow hinge follows the upper arm, so raised or forward arms still bend correctly. Static mannequins are baked at t = 0 and never gesture. Set `GesturesEnabled = false` to keep only the idle.

## Phase C.3.8: visible eyes

Eyes rendered plain white because both `SurfaceAppearance` instances survived on `Eyes`, and the empty duplicate could win. `prepareFace` now keeps a single appearance: the one whose `ColorMap` or `ColorMapContent` is readable and non-empty, or the first one (the importer writes the textured one first). As a guarantee, the preview also places brown iris and black pupil discs on both eyeballs (`MorphLabConfig.Preview.EyeIris`), positioned from the `Eyes` mesh bounds and following the `Head` bone every frame.

## Phase C.3.9: tilted HUD panels

The MORPHLAB side panels are drawn on `SurfaceGui`s (`AlwaysOnTop`, rendered at 2x) adorned to invisible local plates parented to the camera, one stud in front of it. Each plate keeps the flat layout's inner edge and is turned `Hud.PanelTiltDegrees` so its outer edge comes forward. Plates are re-placed every frame after the camera moves (`BindToRenderStep`, `Last`). Slider drags are projected onto the right plate to get canvas coordinates. Set `Hud.Enabled = false` to fall back to flat ScreenGui panels. The corridor mannequin and the projector hologram were removed; only the stasis pod mannequins remain. Neon transparency is now 0.55 and camera bloom 0.18.

## Phase C.4: FACE category and 3D icons

FACE is the second active MORPHLAB category. With the Quaternius base (separate eye and eyebrow meshes, no FACS head) it supports:

- EYE COLOR: `CharacterCatalog.Eyes` appends `hazel`, `green`, `blue`, `gray`, `cyber_red` and `cyber_cyan` to the persisted default `natural`; `EyeStyles` defines the iris colour and whether it glows (Neon, bright pupil).
- BROW COLOR: eyebrows use the draft `hairColorId` (`HairColorValues`), so they will match hair once hair meshes exist.

Selections go through `CharacterDraft.setEyes` / `setHairColor` and `MorphLabAppearanceController:ApplyFace`. Choosing FACE blends the camera to a close-up of the eyes (`Camera.FaceDistance`, with its own zoom range); BODY returns to the cinematic framing. Expressions and face shape need a new head mesh. RANDOMIZE also picks eyes and brow colour.

Category icons are small `ViewportFrame` scenes: BODY and FACE show the real male base (full body and head close-up), HAIR, IMPLANTS, CLASS and COLOR are part-built props (head with hair cap, circuit chip, neon triangle emblem, paint spheres). Unicode glyphs were dropped because Roblox fonts rendered several as empty boxes.

Eyebrows: the imported brow mesh is too thin to show its colour and sinks into the forehead when MASS/MUSCLE thicken the head. The preview hides it and places two slightly arched brow bars from its bounds, a little in front, following the `Head` bone like the iris discs (`EyeIris.BrowOverlay`). `ApplyFace` colours them (Neon for `neon_blue`) and reports `EYEBROWS_MISSING` if none were found.

## Phase C.4.1: face rig (nose, lips, ears)

`scripts/rig_face_bones.py` (headless Blender) adds nine deforming bones under `Head` — `nose`, `nostril_l/r`, `lip_upper`, `lip_lower`, `lip_corner_l/r`, `ear_l/r` — placed from landmarks measured on each body mesh, with smooth ellipsoid weights taken from the `Head` group (one face bone per vertex). It also leaves a single material on `Eyes` (`MI_Eyes`) and `Eyebrows` (`MI_Hair`), which caused the duplicate SurfaceAppearance. Outputs are copies: `blender/*_Face.blend` and `exports/*_Face.fbx`; scale, orientation and height match the original exports.

Import both `_Face.fbx` files with the Studio 3D Importer into ServerStorage. `UniversalAssetBootstrapService` accepts rigs with at least 63 bones and prefers the one with the most bones, so the face-rigged import wins over the original without deleting it.

FACE gains NOSE LEN, NOSE W, LIPS, MOUTH W and EARS sliders stored in the optional `draft.faceShape` (`CharacterCatalog.FaceShapeKeys`, 0..1, 0.5 neutral; profiles without it stay valid). `QuaterniusIdleAnimator:SetFaceShape` translates the facial bones along model-space directions scaled by the ear-to-ear width. Without the face rig the sliders are locked and the panel says so.

Feature close-ups: in FACE, using a control frames its feature at `Camera.FeatureDistance` — nose (NOSE LEN / NOSE W), mouth (LIPS / MOUTH W), ear in a three-quarter view (EARS), eyes (EYE COLOR) and brows (BROW COLOR). Targets are the live positions of the facial bones and overlay parts. Dragging the same feature keeps the user's zoom; selecting FACE again returns to the whole face, BODY to the full body.

## Phase C.4.2: Spanish UI and nose profile

Spanish is the primary language: every player-facing text (START screen, loading screen, MORPHLAB panels, statuses, scene signs) is in Spanish. Internal identifiers stay in English (category ids `BODY`/`FACE`, catalog and draft keys, attributes), so saved data and tests are unaffected; MORPHLAB categories carry a separate `label`. NOSE LENGTH ("LARGO NARIZ") frames the nose in a true side profile; the other features keep their close-ups.

## Phase C.5: HAIR

`scripts/rig_hair.py` adds the six Quaternius (CC0) hairstyles — `Hair_Buzzed`, `Hair_SimpleParted`, `Hair_Beard` (authored on the male base) and `Hair_BuzzedFemale`, `Hair_Buns`, `Hair_Long` (female) — to each face-rigged base: rotated to the bases' +Y facing, offset by the difference in eye landmarks when moved to the other head, and skinned 100% to `Head`. Materials are shared per texture set, textures (including the body and eye maps the source .blend had lost) are relinked from the pack, scaled to 1024 px and embedded. Outputs: `blender/*_Hair.blend`, `exports/*_Hair.fbx` (~8.8 MB).

Import both `_Hair.fbx` files into ServerStorage. The bootstrap now scores templates by bones and then mesh parts, so the hair import wins over `_Face` and the original.

CABELLO is the third active category: PEINADO (six 3D head cards: sin cabello, rapado, de lado, corto, chongos, largo), COLOR DE CABELLO (shared with the brows; the neutral-grey hair textures are tinted through `SurfaceAppearance.Color`) and VELLO FACIAL (sin barba / barba). `hairId` keeps its persisted default `none`; `facialHairId` is a new optional field. The camera frames the head in a three-quarter view (`Camera.HairView*`). Hair meshes are hidden in the body cards, the FACE icon and the pod mannequins.

## Phase C.5.1: generated hairstyles

`scripts/generate_hair.py` (headless Blender) builds five extra styles on each base's own scalp — the hair-covered skin faces of the body mesh, offset along their normals with a smoothed hairline — so they fit both heads without per-head tuning: `Hair_Mohawk` (shaved sides, crest of spikes along the midline), `Hair_Afro` (rounded base with large smooth curl puffs, ~7.5k tris), `Hair_Undercut` (close-cut sides, raised top swept forward), `Hair_Ponytail` (slicked back, tied tail clear of the neck) and `Hair_Spiky`. They use `MI_Hair_1` with smart-projected UVs, are skinned 100% to `Head`, and the script can render front/back previews. Outputs: `blender/*_HairV2.blend` and `exports/*_HairV2.fbx` (~9.5 MB). The template score (bones, then mesh parts) makes the V2 import win automatically.

CABELLO lists 11 styles (catalog ids `mohawk`, `afro`, `undercut`, `ponytail`, `spiky` appended; Spanish names CRESTA, AFRO, DEGRADADO, COLETA, PICOS) in a 5-column grid of smaller 3D cards.

## Phase C.6: IMPLANTES

IMPLANTES is the fourth active category. Six cyberware pieces are built at runtime from parts by `MorphLabCyberware` — no import needed: OJO BIÓNICO (`cyber_eye`, monocle with a glowing lens), VISOR ÓPTICO (`visor`), PLACA MANDIBULAR (`jaw_plate`, needs the face rig), CIRCUITOS FACIALES (`face_circuits`), PUERTOS NUCALES (`neck_ports`) and BRAZO CIBERNÉTICO (`cyber_arm`, right forearm). Each piece keeps an offset from its bone's bind pose (`Head`, `neck_01`, `lowerarm_r`), captured by the preview before the first animation step, so it follows head turns, gestures and the HEIGHT slider. The skin surface is not readable at runtime, so facial pieces are placed on an ellipsoid fitted to the ears and eyes.

The selection is the existing `cyberwareIds` array (catalog ids appended; `{ "none" }` still means an empty loadout; max 8). `CharacterDraft.toggleImplant` installs or removes one implant with validation. Cards toggle, show INSTALADO / INSTALAR and a counter; the camera frames head to forearms (`Camera.ImplantView*`). RANDOMIZE installs zero to two implants.

## Phase C.7: CLASE

CLASE is the fifth active category: the combat role. Five classes — CORREDOR (`runner`, default), NETRUNNER (`netrunner`), EJECUTOR (`enforcer`), FANTASMA (`ghost`) and MEDTECH (`medtech`) — live in `CharacterCatalog.Classes` with `ClassInfo` (colour and 1..5 stats for `speed`, `armor`, `hacking`, `stealth`, `support`). The stats are data only for now; the server will read them once combat exists. The choice is stored in the new optional `classId` (profiles without it stay valid) through `CharacterDraft.setClass`.

The page lists one card per class (colour bar, name, role) and five stat bars for the selection. The platform's `OuterEnergyRing` and `CoreEnergyRing` take the class colour locally and get their colours back on Deactivate. The camera uses the full-body framing. RANDOMIZE picks a class.

## Phase C.8: COLOR

COLOR is the sixth and last MORPHLAB category. It colours the installed cyberware (and is meant for outfits later): NEÓN PRINCIPAL (`neonPrimary`: bionic lens, circuits, ports, jaw slit, arm strip) and NEÓN SECUNDARIO (`neonSecondary`: visor band) from eight neon colours, and ACABADO METÁLICO (`metal`: grafito, cromo, negro, oro, blanco; chrome and gold add reflectance). Values live in `CharacterCatalog` (`NeonColorValues`, `MetalFinishValues`, `DefaultColors`); the selection is the new optional `draft.colors` (profiles without it stay valid) set through `CharacterDraft.setColor`. `MorphLabCyberware.Build` now takes a style table instead of a single accent, and the preview rebuilds the cyberware when a colour changes. A note asks to install implants when there are none. The camera uses the implants framing.

## Phase C.8.1: section progress and ENTRAR A LA REALIDAD

Each MORPHLAB section counts as done after the player edits any control in it (the category active when an edit handler succeeds; RANDOMIZE does not count). Done sections show a check mark instead of the chevron, and the bottom-centre tagline reads "COMPLETA CADA SECCIÓN // n / 6". With all six done the tagline gives way to ENTRAR A LA REALIDAD in the same spot, with a pulsing outline. Its action (saving the identity through the server) is the next phase; for now it reports that in the status line.

## Phase D.1: lobby

After MORPHLAB, ENTRAR A LA REALIDAD hands a copy of the draft to `LobbyController` (`MorphLabController:SetConfirmHandler`); an EXISTING_PLAYER goes straight to the lobby with the saved character. OPERADOR returns to MORPHLAB with the same draft and progress.

`LobbySceneBuilder` (server, idempotent, `Workspace/Reality2059Runtime/Lobby`) places a rooftop in front of `City2059` — resolved from the city's bounding box at runtime, `LobbyConfig.FallbackOrigin` otherwise — with the player's ring (`Platform/CharacterSpawn`, the same contract as MORPHLAB), four coloured squad rings with anchors, the NEO-EDEN // SECTOR 7 sign, a sky rift (neon ring, force-field swirl, debris) and city dressing (holographic signs, light columns, coloured lights). City2059 itself is not modified.

The client reuses the MORPHLAB preview stack, so the lobby character has the full appearance (body shape, face, hair, cyberware, colours) and the idle animation. A client-only `Atmosphere` adds purple haze and is restored on exit. `LobbyUI` shows the logo, tabs (JUGAR, OPERADOR; the rest locked), credits and level from the profile, game modes (Modo libre selectable; Competitivo and Rápida locked), JUGAR, the location card, the squad panel with a portrait of the player and billboards ("TÚ // LISTO", "+ INVITAR"). JUGAR announces that free roam is the next phase. Studio output must include `Lobby tests passed: 5/5`.

## Phase D.2: lobby closer to the concept art

The squad rings now hold four AI placeholders (`LobbyConfig.ShowAISquad`, names Nova, Raze, Vex, Kairo) until parties exist. Each one is a full preview — `MorphLabPreviewController:SetSpawn` places it on its `Squad/SquadSpawnN` ring — with a random but validated character built through the `CharacterDraft` setters, seeded by the player's UserId so the squad is stable, and a class different from the player's. The scene sign gained a neon emblem.

`LobbyUI` was rebuilt after the art: centred REALITY / 2059 logo, tabs with 3D icons, wallet pills (credits from the profile; the gem pill shows 0 until a second currency exists) with social buttons, mode cards with a skyline backdrop and 3D icons, a gradient JUGAR with a play triangle, the location card, the squad panel with five portraits plus an add button, and name tags with a class badge and a green "Listo" tick. All icons are part-built ViewportFrame scenes; no uploaded images are needed.

## Phase D.2.1: empty squad rings

`LobbyConfig.ShowAISquad` is now `false`: the four squad rings stay empty with "+ INVITAR" billboards, because they are reserved for invited players. The AI placeholder code remains behind the flag.

## Phase C.9: ROPA

ROPA is the seventh MORPHLAB category (between CABELLO and IMPLANTES; ENTRAR A LA REALIDAD now needs 7 / 7 sections). There are four outfits, two per body base: VANGUARDIA (`vanguard`, male default) and MERCENARIO (`mercenary`) for `base_male`; INFILTRADORA (`infiltrator`, female default) and NÓMADA (`nomad`) for `base_female`. They were modelled with `scripts/generate_outfits.py` as garment shells built on the body surface that keep its skin weights, so they bend with the skeleton. Each outfit is a set of MeshParts `Outfit_<id>_<Top|Overlay|Bottom|Boots|Trim>`; colours and materials come from `CharacterCatalog.OutfitInfo`, and `Trim` glows with the COLOR primary neon.

The choice is the new optional `outfit.outfitId` (profiles without it stay valid), set through `CharacterDraft.setOutfit`; the validator rejects an outfit of the other body, and switching body switches to that body's default outfit. The page shows two full-body 3D cards for the current body. MASS / MUSCLE thicken the garments together with the body. RANDOMIZE picks one of the two outfits. The lobby character wears the outfit through `ApplyDraft`.

Import into Studio (same steps as the hair models): `src/assets/characters/universal/exports/Reality2059_UniversalBase_Outfit.fbx` and `Reality2059_UniversalBaseF_Outfit.fbx` into ServerStorage. The bootstrap picks the most complete import automatically. Without them the page says "ROPA NO INSTALADA". Studio output must include `Phase C.3.1 tests passed: 48/48`.

Fix C.9.1: the first `_Outfit` exports had no skin weights (Blender 3+ keeps vertex group names on the mesh, and the generator built each garment on a new mesh), so in Roblox the garments stayed frozen in the T-pose while the arms moved. `generate_outfits.py` now copies the group names, fails if any garment vertex is unweighted, and renders a lowered-arms check (`<outfit>_posed.png`). VANGUARDIA's shoulder plates now take the COLOR metal finish instead of plain white. Re-import both `_Outfit.fbx` files.

## Phase E.1: MODO LIBRE

JUGAR in the lobby (Modo libre selected) puts the player in City2059; the LOBBY button in the free-roam HUD goes back. Characters now exist only in free roam (`Players.CharacterAutoLoads` is off).

**City (server, `CityWorldService`, runtime only).** The imported city is found by its tower mesh (`Cuberpunk2077.009`), even if it was imported under another name, and renamed `City2059`. The saved model is at effective scale 60 (~1,227 × 415 × 1,179 studs). `RescaleCity` is disabled, so it keeps exactly that size; its floor centre stays at `CityCenter` (0, 0, -1200). Every piece gets back the glTF colour and a material (the importer had left them all grey); glowing pieces remain Neon. `World/CityMaterialConfig` maps the safe mesh groups to Asphalt, Concrete, Metal or Facade and `CityWorldService` applies optimized Roblox materials immediately. If `MaterialService` contains a matching `R2059_*` MaterialVariant marked `Reality2059PBRReady` for its role, with the correct base material and tile scale, the same code switches to the custom 1024 px PBR pack in `assets-source/textures/city2059_pbr`; otherwise it keeps a textured native-material fallback. The three ambiguous UV/alpha groups remain untouched. The city meshes lose their collision: they are split by material, so each spans the whole city and Roblox's automatic collision would fill the streets. Collision v5 comes instead from 14,072 editable boxes in `src/server/World/City2059Data.luau`: 3,570 structural boxes plus 10,502 thin walkable surfaces. At scale 60 both layers have 1.5-stud horizontal resolution, while ramps use 0.75-stud vertical steps. Walkable surfaces are 0.48 studs thick and sit entirely below the rendered road, sidewalk, ramp or platform, so they cannot protrude above it. Structures can be shown in red and surfaces in cyan for editing; all are invisible in Play. The same script picks 8 open street spawn spots. `Workspace/Reality2059Runtime/FreeRoam` holds a 4400-stud asphalt ground flush with the city slab, invisible edge walls and the spawns.

Regenerate the data after changing the city GLB:
`blender -b --python scripts/build_city2059_data.py -- <Reality2059_City2059.glb> src/server/World/City2059Data.luau <report.json>`

**Players.** Each player is an invisible capsule (`StarterCharacter`: HumanoidRootPart 2×2×1 + Humanoid, HipHeight 1.85). `EnterFreeRoam` validates the character with `CharacterValidator`, stores it in the player's `AvatarData` attribute and spawns the capsule; every client draws each player's custom character on it with the MORPHLAB preview stack in follow mode (`MorphLabPreviewController:SetFollow`), so body shape, face, hair, outfit, cyberware and colours match the editor. Walk 16 studs/s, SHIFT (or CORRER on touch) runs at 28, jump power 50; a fall respawns after 3 s.

**Animation.** `QuaterniusIdleAnimator` gained a locomotion layer (`SetLocomotion(speed, grounded, verticalSpeed)`, settings in `MorphLabConfig.Preview.Locomotion`): pelvis bob and twist, thigh/knee/ankle gait with heel strike and toe roll, counter-swinging arms, forward lean and fists when running, a tuck in the air and a crouch on landing. Stride length follows the leg length, so the feet keep pace with the speed. The idle breathing, sway and gestures fade out while moving and return when standing still. MORPHLAB, the lobby and the thumbnails are unchanged (no locomotion input = the old idle).

**Day and night.** One shared cycle (`shared/World/DayCycle`, server epoch in the runtime `DayCycleEpoch` attribute) starting at 08:30. In `FreeRoamConfig.DayCycle`: `DaySeconds` (600: 06:12 to 18:36) and `NightSeconds` (300) set each half separately, `StartClockTime` the hour at server start, `NightStart` / `NightEnd` when night begins and ends, and `FixedClockTime` (e.g. 22) freezes the hour for testing; the look of each hour is in `LightingKeys`. The client interpolates `LightingKeys` (dawn, day, sunset, dusk, night: ambient, brightness, atmosphere colour/haze, colour grade), adds bloom, and switches the city windows from glass by day to glowing at night. The HUD shows the clock (DÍA / NOCHE). Everything is restored on leaving.

Studio output must include `Free roam tests passed: 5/5`.

Fix E.1.1: the Roblox importer turns the city 180 degrees inside its meshes (X and Z negated, part rotation left at identity), so the first collision boxes were mirrored: invisible walls in the streets and walk-through buildings. `CityWorldService` now measures each axis sign from where every mesh actually sits (`MeshCenters` in the data) and the free-roam tests check that collision space lands on the imported parts within 1 stud. City scale raised to 36 (~735 studs across).

Fix E.1.2: the city is found even inside folders (smallest model holding every city mesh) and renamed `City2059`; the server prints `Ciudad '<path>' lista: escala …` at start and the free-roam tests fail if no city is found. The generated collision boxes are off (`GeneratedColliders = false`); collision is now hand-made: Parts inside a Folder/Model named `Colisiones` inside `City2059` become invisible and solid in play and scale/move with the city. Parts recoloured in Studio keep their colours (only import-grey plastic pieces get the glTF colours). `RescaleCity` / `RepositionCity` = false keep the city exactly as placed in Studio.

Fix E.1.4: the saved city was doubled from effective scale 30 to 60 without changing its floor centre. Collision data v5 increases the walkable layer to one sample per source grid cell and always rounds its top downward. The result is 14,072 boxes (3,570 structures + 10,502 surfaces), 1.5-stud horizontal resolution, 0.75-stud ramp-height resolution and no collision volume above the visible road surface.

Collision workflow (E.1.3): in edit mode run in the Command Bar
`require(game.ServerScriptService.CyberpunkOnlineServer.Services.CityWorldService).GenerateEditableCollision()`
to write the generated boxes as visible red Parts into `City2059/Colisiones` at the city's current size and position; then fix them by hand and save the place. Run `AuditEditableCollision()` to verify that all collision Parts are anchored and solid and that no visual MeshPart is accidentally blocking the player. Re-running generation replaces only the generated boxes (attribute `GeneratedCollision`) and keeps hand-made Parts; Ctrl+Z undoes it. `SetCollisionVisible(false/true)` hides or shows them while editing; in play they are always invisible and solid.

Fix E.1.4 (city audit, 16/10/2026): visible GLB geometry was compared against the 14,072 collision Parts saved in the place on a 1.5-stud grid. Alignment with all 30 meshes is exact; no invisible walls, all 12 towers closed, all 8 spawns valid. The only gaps were 82 curbs and steps 2–3 studs high where the capsule (HipHeight 1.85) snagged instead of stepping up; `Movement.HipHeight` is now 3.2 and the re-audit finds no walk-through walls. Collision data v6 (`SURFACE_MIN_RISE`) drops the 2,380 street-level slabs that the ground plane already covers; `CityWorldService` also prunes them in play from places still holding v5 parts (attribute `PrunedStreetSurfaces`). Structures are unchanged between v5 and v6.

Studio quick start (E.1.5): `src/shared/Config/DevConfig.luau` → `QuickStart` = `false` (normal menu), `"MorphLab"`, `"Lobby"` or `"FreeRoam"` skips the INICIAR menu when playing in Studio only (`RunService:IsStudio()`); a published game always uses the normal flow. Lobby and free roam start with `DevConfig.Character`, applied through the validated `CharacterDraft` setters (a rejected field is reported and keeps its default).

Cyberpunk city textures (E.1.6): `scripts/generate_cyber_textures.py` builds five procedural PBR tile sets in `assets-source/textures/city2059_cyber` (Facade, Panels, Residential, Asphalt, Pavement; 17 PNGs). The city UVs are world-scale box projections (~8.26 tiles per glTF unit, V downward on every wall), so a tile is ~7.3 studs at scale 60 — one building floor. `World/CityTextureConfig` maps sets to meshes; `Services/CityTextureTool` (Command Bar: `Prepare()`, `Install()`, `Remove()`) creates SurfaceAppearance templates in `ServerStorage/TexturasCyber` and copies them, tinted where configured, into the city MeshParts as `CyberSurface`. SurfaceAppearance maps are Studio-only properties, so the images are picked (and uploaded) in Properties. Previewed in Blender on the real city UVs before install.

Per-building dressing (E.1.7): all towers share one mesh per material, so a texture repeats identically on every tower. `scripts/build_city2059_dressing.py` finds the 26 towers of the GLB and their largest flat walls (coplanar vertical triangles merged per plane, outward normals, parts hidden behind an overhanging section trimmed) into `World/City2059Dressing`. `CityDressingService` (runtime, after `CityWorldService`, using its `Transform`) gives each tower a fictional brand from `Config/CityDressingConfig` (10 styles: neon colours, font, Japanese tag, Spanish slogan): a main billboard (vertical on tall walls) and a promo screen as SurfaceGuis (gradient, scan lines, neon border; no uploaded images), neon strips on the wall edges and top, an accent band on every other tower, and a lit rooftop sign where a wall reaches the roof. `CityDressingFX` (client) scrolls the screen gradients and makes screens flicker. Previewed in Blender at night on the real walls.

Per-tower facades (E.1.8): `scripts/prepare_kb3d_facades.py` takes 8 KitBash3D Neo City materials (Color/Normal/Roughness, resized to 1024) and generates 3 window overlays (Grid, Bands, Slits; RGBA with ~30 % lit panes) into `assets-source/textures/kb3d_facades` (KitBash3D files are licensed to the project owner; keep them out of public repos). `World/CityFacadeConfig` holds the MaterialVariant settings, 10 tower looks (material, window pattern, floor height, pane tint) and the uploaded asset ids. `CityTextureTool.InstallFacades()` (Command Bar) creates the `R2059_KB3D_*` MaterialVariants. `CityDressingService` clads every tower wall with its look's material plus a tiled window SurfaceGui; `CityDressingFX` makes the windows self-lit at night. Without installed variants the cladding is skipped and towers keep their previous look.

Unique facades (E.1.9): every tower now gets its own KitBash3D material, never repeated — 26 materials for the 26 towers (`CityFacadeConfig.Materials`, sorted then shuffled with seed 59; the tower model carries a `FacadeMaterial` attribute). The cladding is smooth: window overlays are off (`Windows = false`). Asset ids are keyed by their Roblox asset name (`KB3D_NEC_<Name>_basecolor/_normal/_roughness`, the original KitBash3D uploads) and `CityTextureTool.InstallFacades()` verifies each id's name with `MarketplaceService:GetProductInfo`, listing any mismatch under "REVISAR".

Fix E.1.10: the PBR MaterialVariants depend on Studio packaging and uploading a TexturePack, which did not show in play. The cladding now shows each tower's KitBash3D colour map as a tiled `Texture` (`StudsPerTileU/V` = the material's studs per tile) straight from the uploaded image id, so it needs no install step; an installed `R2059_KB3D_*` MaterialVariant is still used underneath when present. `CityTextureTool.TestFacades()` / `RetryFacadeUpload()` remain for checking the PBR variants.

Dark facades (E.1.11): the procedural window facade texture is disabled (`CityTextureConfig.DisabledSets.Facade`): `CityTextureTool.Install()` skips it and `CityDressingService` removes an installed one in play and darkens the uncovered tower shell. Each KitBash3D material carries its measured colour-map luminance (`brightness`); the cladding Texture and panel are tinted down to `TargetBrightness` (0.18) with one of four cool `Hues` per tower, so light materials become dark variants that keep their own pattern.

Plain ground (E.1.12): roads (`.011`) and sidewalks/plazas (`.004`, `.005`, `.003`) lose their textures in play (`CityTextureConfig.PlainSets`): roads near-black, sidewalks smooth grey, both SmoothPlastic with no TextureID or MaterialVariant. Monorail and houses keep their textures, slightly darkened (`PlayTint`).

Fix E.1.13: the place still had the template `Baseplate` (grid texture, top at y = 0); with the city floor centred at y = 0 its grid showed over roads and sidewalks. `CityWorldService` removes it in play.

Fix E.1.14: the checker on roads/sidewalks was z-fighting: `Cuberpunk2077.002` (a decal layer whose texture never shipped — the GLB holds only a 1×1 white placeholder) lies exactly on the sidewalk slab `.003`. It is hidden in play (`CityTextureConfig.HiddenPieces`). The city floor now sits at y = 1 (`CityCenter`) so it never coincides with the y = 0 plane of the template Baseplate or Studio's build grid. Material overrides pointing at facade variants (or on the plain-set materials) are cleared in play and reported.

Fix E.1.15: streets and sidewalks were swapped. The street network is the sheet mesh `.003` (14 large sheets at the street surface, with the texture-less decal layer `.002` on top); the sidewalks and plazas are the base slab `.004`/`.005` that covers the whole city. `Asphalt` (near-black) is now `.003` + `.011`, `Pavement` (smooth grey) is `.004` + `.005`.

Fix E.1.16 (supersedes E.1.15): checked in play, the sidewalks are the sheets `.003` and the streets the base slab `.004`/`.005`. `Pavement` (smooth grey) = `.003`; `Asphalt` (near-black) = `.004` + `.005` + `.011`.

Fix E.1.17: hiding the decal layer `.002` left a gap along the sidewalk edges (the white line) and made the sidewalk look see-through. `.002` is now part of `Pavement` (same smooth grey as `.003`, fully opaque), so the edge is sidewalk and the coplanar pair cannot z-fight; `HiddenPieces` is empty.

Fix E.1.18: coplanar same-colour pieces still z-fought into a two-tone checker (differing normals). In play the lower piece of each pair is dropped slightly (`CityTextureConfig.PieceDrop`: sidewalk edge layer `.002` −0.08 under `.003`; street slab `.005` −0.06 under `.004`).
