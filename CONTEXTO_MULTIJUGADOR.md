# REALITY 2059 — Contexto: lobby y multijugador

Estado del lobby, el MorphLab y el shooter multijugador (5 vs 5 en tercera persona) para retomar el trabajo en cualquier sesión. Complementa a [CONTEXTO.md](CONTEXTO.md); donde ambos difieran, **este archivo es el más reciente**.

_Última actualización: 26/10/2026._

> **Nada de esto se ha probado completo en Studio.** Se fue validando por partes con el Output; las pruebas automáticas corren al darle Play (en el Output).

---

## 1. Decisiones vigentes

| Tema | Decisión |
|---|---|
| Enfoque | Primero **PARTIDA RÁPIDA** (y luego Competitivo). El modo libre queda para después. |
| Menú JUGAR | Muestra **MODO LIBRE** bloqueado arriba y **MULTIJUGADOR** debajo; al entrar en Multijugador aparecen Competitivo, Partida rápida, Partida privada y Modo entrenamiento. |
| Equipos | **5 vs 5**. Partida rápida y Competitivo conservan escuadrones de 5; una sala de Partida privada acepta hasta 10 y los divide 5/5 (`TeamSize = 5`). |
| PARTIDA RÁPIDA | Solo **duelo por equipos** (gana el equipo con más eliminaciones), con reaparición. |
| PARTIDA PRIVADA | **Habilitada.** Crear sala o colocar código de 6 caracteres; admite 1–10 jugadores y divide 5/5. Los códigos vencen en 2 horas. |
| COMPETITIVO | **Bloqueado** (`locked = true` en `LobbyConfig` y `PartyConfig`). |
| MODO LIBRE | **Bloqueado** para jugadores; en Studio se puede entrar para pruebas. |
| Cámara | Tercera persona sobre el hombro; **el mouse mueve la cámara** (bloqueado al centro) y el personaje mira hacia donde apunta. |
| Armas | **Máximo 2** por jugador. E agarra; con 2, E **intercambia** (la del arma en mano cae al piso). |
| Iluminación | Cada mapa es **de día o de noche** (`MapsConfig`). Distrito Nexus = día. |
| Moneda | **NEOCRÉDITOS**, se compran con Robux (Developer Products). |
| Idioma | Todo lo que ve el jugador en español; código e ids en inglés. |

---

## 2. Lobby (hub)

- **Escena:** azotea frente a la ciudad (`LobbySceneBuilder`), ahora **más baja** (`LobbyConfig.CityHeightFraction = 0.35`, `CityFrontGap = 90`) para que los edificios suban detrás. **Cámara fija** (sin deriva); cada pestaña tiene su encuadre.
- **Mismo fondo que el MorphLab:** ciudad, lluvia, neblina y el **vórtice animado** (`MorphLabVortex`) en lugar del portal original del skyline. El neón rosa de la ciudad y del skyline se bajó de intensidad.
- **Pestañas:** JUGAR · PERSONAJE · ESCUADRÓN · **TIENDA** · AJUSTES · CRÉDITOS. El título (REALITY 2059) bajó para no quedar bajo los botones de Roblox.
- **Modos (JUGAR):** aparecen **MODO LIBRE** arriba (atenuado y bloqueado) y **MULTIJUGADOR** debajo. Al entrar en Multijugador se muestran COMPETITIVO, PARTIDA RÁPIDA, PARTIDA PRIVADA y MODO ENTRENAMIENTO. PARTIDA RÁPIDA y PARTIDA PRIVADA están habilitadas; Competitivo y Entrenamiento siguen bloqueados. El servidor rechaza los modos bloqueados (`PartyCore.setMode` → `MODE_LOCKED`). El flujo interno de MODO LIBRE se conserva para pruebas en Studio.
- **PARTIDA PRIVADA:** al abrirla aparecen **CREAR PARTIDA** y **COLOCAR CÓDIGO**. Crear genera un código de seis caracteres sin caracteres ambiguos, válido durante 2 horas, que se muestra en el lobby para compartir. Colocar código une a la sala local o, si está en otro servidor del lobby, usa MemoryStore + `TeleportAsync` para llevar al jugador al servidor anfitrión. La sala admite 1–10 jugadores; todos salvo el líder marcan LISTO. Al iniciar obtiene un servidor reservado propio y nunca se mezcla con otros grupos. Los primeros cinco integrantes forman Team A y los siguientes cinco Team B.
- En Studio los códigos funcionan entre jugadores del mismo Team Test; Roblox no permite probar teletransportes reales desde Studio. Para publicación deben estar habilitados Memory Stores y hay que pegar el place id de partidas en `PartyConfig.Matchmaking.PlaceIds.private`.
- La capacidad del grupo ahora depende del modo (`PartyCore.capacity`): 5 normalmente y 10 en privada. No permite cambiar una sala de más de cinco jugadores a Partida rápida o Competitivo.
- **Implementación de códigos:** configuración en `PartyConfig.PrivateRooms`; interfaz en `HubUI` / `LobbyController`; solicitudes `create_private` y `join_private` en `PartyController` / `PartyService`; validación pura de ingreso en `PartyCore.joinPrivate`. Al cerrarse una sala se retira su código de MemoryStore; código inexistente, sala llena, sala ocupada y fallos de teletransporte se informan al jugador en español.
- **TIENDA** ([HubUI.luau](src/client/Lobby/HubUI.luau), [ShopConfig.luau](src/shared/Config/ShopConfig.luau), [ShopService.luau](src/server/Services/ShopService.luau)):
  - Saldo de NEOCRÉDITOS y botón **+ OBTENER** → 4 paquetes (500 / 1 200 / 2 600 / 7 000 por 49 / 99 / 199 / 499 Robux).
  - Navegación por categorías (DESTACADO, ATUENDOS, ACCESORIOS, IMPLANTES, ARMAS, EMOTES). Sin artículos aún: cada una muestra "VUELVE PRONTO". Los artículos se agregan en `ShopConfig.Items`.
  - Compra: el cliente abre la ventana de Roblox; el servidor (`ProcessReceipt`) acredita **una sola vez por recibo** (`PlayerDataService:GrantCredits` guarda el id en `inventory.receipts`) y avisa con `CurrencyChanged`.
  - **Pendiente del usuario:** crear los 4 Developer Products en Creator Hub y pegar sus ids en `ShopConfig.CreditPacks[].productId` (con 0 dice "AÚN NO ESTÁ A LA VENTA").

## 3. MorphLab (creador de personaje)

- Azotea al lado del lobby (`MorphLabConfig.RooftopOffset = (-120, 0, 0)`), misma altura y fondo. Sin menú lateral; columnas en los bordes de la pantalla.
- **Izquierda:** CUERPO (clásico/esbelto) · ROSTRO · CABELLO · **ATUENDO** por piezas (CHAQUETA / CAMISA / PANTALÓN / TENIS, cada una con "ninguno") · PALETA DE COLOR (PIEL, NEÓN 1, NEÓN 2, METAL).
- **Derecha:** CLASE (al elegir una aparece su tarjeta de estadísticas y el personaje se recorre a la izquierda) · IMPLANTES · ACCESORIOS · VISTA PREVIA // DATOS (retrato 3D).
- Cada fila termina en **MÁS**: un panel sube con todas las opciones y sus nombres.
- **Abajo:** ALEATORIO · CONFIRMAR (siempre disponible) · RESTABLECER. Se quitó INICIAR VIAJE.
- Personaje nuevo empieza **en ropa interior** (todas las piezas en "none"). Bóxer si no hay pantalón; sostén en cuerpo esbelto si no hay camisa ni chaqueta.
- **Caras dibujadas** sobre la cabeza de bloques ([FaceArt.luau](src/shared/Character/FaceArt.luau)): 13 expresiones (incluye ASOMBRO), parpadeo, guiño y gestos; se quitan la cara clásica y las texturas de la cabeza. Ya no se usan cabezas dinámicas.
- Prendas por capas verificadas en la API de Roblox (`CharacterCatalog.OutfitPieces` / `PieceInfo`). Personajes guardados antes del cambio siguen funcionando (`CharacterDraft.pieces` usa `outfitId`).

## 4. Mapas multijugador

- **Plan:** 5 mapas. Construidos en bloques ("greybox") por código y luego ajustados a mano en Studio; los detalles se modelan en Blender (1 unidad = 1 stud, importar con unidad "Studs").
- **Medidas de referencia:** personaje ≈ 5.2 studs; pasillos 10–14; puertas 8×10; cobertura baja 3–4 / alta 8; techos ≥ 14; mapa ≈ 280×340 para 5 vs 5.
- **Kit:** [Blockout.luau](src/server/Maps/Blockout.luau) (colores: gris estructura, amarillo cobertura baja, naranja alta, azul rampas, cian/magenta aparición A/B).
- **Mapa 1 — Distrito Nexus** ([DistritoNexus.luau](src/server/Maps/DistritoNexus.luau)): 3 carriles (calle con autos / plaza con plataforma / galería techada), callejones en z = ±60, cuarto de salida por equipo con 3 puertas. Simétrico. Atributos `MapId = nexus_grid`, `TimeOfDay = day`.
- **Construirlo (una vez, Command Bar, sin Play):**
  ```lua
  require(game.ServerScriptService.CyberpunkOnlineServer.Maps.DistritoNexus).Build()
  ```
  Queda en `Workspace.MapWorkshop.DistritoNexus` (z = 2500, y = 40, lejos de la ciudad). `Build()` no sobrescribe; `Build(true)` empieza de cero. Guardar el place.
- **Estructura que el juego espera:** `Geometry/`, `Spawns/TeamA`, `Spawns/TeamB`, `Bounds/PlayArea`; opcional `WeaponSpawns/` (partes donde aparecen armas).
- **Pendiente:** los otros 4 mapas (Mercado Neón, Azotea Kairo, Puerto de Datos, Subnivel 7), **veto de mapas** en partida rápida con elección automática, y un place de partidas.

## 5. Probar en Studio: `MapTest`

En [DevConfig.luau](src/shared/Config/DevConfig.luau): `QuickStart = "MapTest"`, `MapTest = "DistritoNexus"`. Al dar Play:
- Apareces en la zona del equipo A, en **modo shooter** (sin HUD del modo libre, reloj, inventario, tráfico ni peatones) con la luz del mapa.
- **Armería:** todas las armas en pedestales frente a la salida del equipo A (reaparecen a los 4 s).
- **5 maniquíes** de práctica en la plaza (reaparecen a los 3 s).
- Volver a `QuickStart = false` para el flujo normal.

## 6. Armas

- **Importar (una vez, Command Bar):**
  ```lua
  require(game.ServerScriptService.CyberpunkOnlineServer.Weapons.WeaponImporter).Import()
  ```
  Descarga los modelos gratis de `WeaponConfig.CatalogAssets` (sin los de Sketchfab ni la SMG pesada), les quita scripts, los suelda y escala, y guarda un Tool por arma en `ServerStorage.Weapons`. Guardar el place.
- **Listar / quitar por posición** (1 = la de más a la izquierda en la armería):
  ```lua
  local W = require(game.ServerScriptService.CyberpunkOnlineServer.Weapons.WeaponImporter)
  W.List()
  W.RemoveByPosition({ 4, 5, 13 })  -- todas en un solo comando
  ```
  Las quitadas se recuerdan (`Excluded` en la carpeta) y no vuelven al reimportar. El usuario pidió quitar 4, 5, 13, 15, 17, 18, 19, 23, 25 y 26.
- Si un arma se sostiene mal: en su Tool ajustar `GripPos` / `GripForward`.
- **Loadout** ([WeaponService.luau](src/server/Services/WeaponService.luau)): el servidor manda; 2 espacios; cambiar con 1 / 2 / rueda ([WeaponController.luau](src/client/Combat/WeaponController.luau)).
- **Pack de pago recomendado** (no comprado): Low Poly Gun Pack Sci-Fi, 139815628366381 ($2.99), un solo estilo para todas las clases.

## 7. Combate

- **Clases y números** ([WeaponStats.luau](src/shared/Combat/WeaponStats.luau)): pistola, subfusil, rifle, escopeta (8 perdigones), francotirador. Clase por atributo `WeaponClass`, nombre o tamaño.
- **Daño por zona:** cabeza ×2 (francotirador ×2.5), torso ×1, brazos/piernas ×0.75. El tirador ve **números de daño** flotando con color y etiqueta (CABEZA / TORSO / BRAZO / PIERNA) y marca de impacto (roja si elimina).
- **Validación en servidor** ([CombatService.luau](src/server/Services/CombatService.luau)): el cliente manda solo origen, direcciones y hora del disparo; el servidor revisa cadencia, munición, recarga, que el tiro salga de la cabeza, choca contra muros y compara contra las **posiciones pasadas** de los objetivos (historial de 1 s, rebobina hasta 0.4 s). Sin fuego amigo. Munición en atributos del Tool (`Ammo`, `Magazine`, `Reloading`).
- **Cliente** ([CombatController.luau](src/client/Combat/CombatController.luau)): disparo inmediato a través de la mira, trazadores, impactos, destello, retroceso de cámara, contador de munición, recarga automática al vaciar.
- **Retroceso corregido (causa real):** la cámara de Roblox conserva su rotación de un cuadro al siguiente y el código le sumaba el retroceso completo en cada cuadro, así que un disparo subía la mira ~6 veces lo previsto y nunca regresaba. Ahora solo se aplica la diferencia de cada cuadro: la mira sube poco (máximo 3°) y vuelve sola. El golpe del arma en las manos también bajó (tope 6°).
- **Remotes:** `WeaponFire`, `WeaponReload`, `WeaponHit` (al tirador), `WeaponShots` (trazadores a los demás, no confiable), `WeaponAim` (pose, no confiable), `WeaponEquip`, `WeaponLoadout`, `CurrencyChanged`.

## 8. Animación y movimiento

- **Animación procedural** ([ShooterAnimation.luau](src/client/Combat/ShooterAnimation.luau)): tras las animaciones de Roblox se coloca el arma frente al pecho apuntando a la mira y los **dos brazos la toman con IK de dos huesos** (derecha en la empuñadura, izquierda bajo el cañón; con pistola, manos juntas). Torso y cabeza siguen la mira; al apuntar el arma sube; retroceso y recarga. Piernas: agachado y deslizamiento. Todos los clientes posan a todos (la pose viaja como atributos del personaje).
- **Cámara** ([ShooterCamera.luau](src/client/Combat/ShooterCamera.luau)): mouse bloqueado al centro, personaje relativo a la cámara, mira; **Alt izquierdo** suelta el mouse; clic derecho = apuntar (FOV 70 → 48); Q cambia de hombro (rig del modo libre).
- **Movimiento** ([MovementController.luau](src/client/Combat/MovementController.luau), ideas de sysscan/Roblox-FPS-Movement): Shift corre con stamina (barra abajo al centro), C / Ctrl se agacha, C corriendo = deslizamiento que frena con curva `progress^2.8`. Prioridad de velocidad: deslizar > agachado > apuntando > correr > caminar.

**Controles:** clic izq. disparar · clic der. apuntar · R recargar · E agarrar / intercambiar · 1 / 2 / rueda cambiar arma · Shift correr · C / Ctrl agacharse · Q hombro · Alt soltar mouse.

## 9. Partidas en el mismo servidor (para probar con varias personas)

- **Partida privada = partida real en el servidor de la sala** (`MatchConfig.LocalPrivateMatches = true`): sin teletransporte ni place de partidas. Funciona en **Studio Team Test** y en el juego publicado. El líder crea la sala, los demás entran con el código, todos marcan LISTO y el líder inicia.
- **Servidor** ([MatchService.luau](src/server/Match/MatchService.luau)): copia el mapa (`ServerStorage.Maps` o `Workspace.MapWorkshop`) a su propio espacio (`MatchConfig.SlotOrigin`, varias partidas a la vez), arma **dos equipos parejos** (mitad y mitad, con los `Teams` de Roblox: sin fuego amigo y la lista de jugadores muestra Bajas/Muertes), hace aparecer a cada uno en las salidas de su equipo con un rifle y una pistola (`WeaponService:DefaultWeapons`, o `MatchConfig.StartingWeapons`) y reaparece a los 3 s.
- **Reglas (duelo por equipos):** cuenta regresiva de 5 s, gana el primero a 30 bajas o quien vaya arriba a los 8 min (empate posible), 15 s de resultados y vuelta al lobby. La baja se le da al último que dañó (`LastAttacker` que pone CombatService).
- **Cliente** ([MatchController.luau](src/client/Match/MatchController.luau)): marcador arriba (equipos, tiempo, "PRIMERO A 30"), tu equipo, cuenta regresiva, registro de bajas y resultados (VICTORIA / DERROTA / EMPATE con tabla de bajas y muertes). **Mantener P** para salir antes.
- Aparición y armas reutilizan el modo libre en modo shooter (`FreeRoamService:SetSpawnProvider`): los jugadores de una partida pueden entrar aunque MODO LIBRE esté bloqueado.
- **Cómo probar con varias personas:**
  1. `DevConfig.QuickStart = false` (con "MapTest" no se ve el lobby).
  2. El mapa DistritoNexus construido y el place guardado; armas importadas.
  3. **Studio:** Test → Clients and Servers → 2 o más jugadores → Start. Cada uno crea su personaje; uno crea la sala privada, los demás ponen el código.
  4. **Publicado:** publicar (el mapa y las armas van dentro del place), invitar amigos al mismo servidor; si caen en servidores distintos, el código los lleva al servidor de la sala (requiere Memory Stores).
- PARTIDA RÁPIDA sigue usando emparejamiento entre servidores: necesita el place de partidas (`PartyConfig.Matchmaking.PlaceIds.quick`) y que ese servidor arranque en modo partida (pendiente).

## 10. Recursos externos revisados

| Recurso | Uso |
|---|---|
| sysscan/Roblox-FPS-Movement (MIT) | Solo ideas (ya aplicadas en MovementController). Su `applyCurrentSpeed` está vacío. |
| NevermoreEngine (MIT) | Si se necesita, copiar a mano solo `Spring.lua` (suavizado de retroceso / balanceo). Nada de npm ni el loader. |
| FastCast Redux | No incluirlo (sin mantenimiento desde 2020, sin fuente oficial, no valida impactos). Su técnica de segmentos se reimplementa para proyectiles lentos cuando haga falta. |
| Vanguard | No usar (framework general, pre-1.0, sin combate). |
| raycastHitbox (MIT) | Solo si agregamos armas cuerpo a cuerpo. |

## 11. Pendientes

1. Probar todo en Studio con `MapTest` y ajustar: manos en el arma, clases mal detectadas, balance.
2. Sonidos de disparo e impacto; HUD de vida propia; pantalla de muerte / reaparición.
3. Probar la partida privada en el mismo servidor con 2+ jugadores (Team Test). Después: PARTIDA RÁPIDA entre servidores (place de partidas que arranque en modo partida leyendo `TeleportData` y reutilice MatchService).
4. Veto de mapas en partida rápida + elección automática.
5. Mapas 2–5 en bloques, luego detalle (Blender).
6. Developer Products de NEOCRÉDITOS y artículos de la tienda.
7. Pruebas con más de un jugador (Test → Team Test) para verificar daño, poses y trazadores entre jugadores.

## 12. Mapa de archivos (nuevos o muy cambiados)

| Área | Archivos |
|---|---|
| Config | `src/shared/Config/{LobbyConfig, PartyConfig, ShopConfig, WeaponConfig, MapsConfig, MorphLabConfig, DevConfig}.luau` |
| Combate (compartido) | `src/shared/Combat/WeaponStats.luau` |
| Personaje | `src/shared/Character/{FaceArt, CharacterDraft, AvatarDescription}.luau`, `src/shared/Catalog/CharacterCatalog.luau` |
| Partidas | `src/shared/Config/MatchConfig.luau`, `src/server/Match/MatchService.luau`, `src/client/Match/MatchController.luau` |
| Servidor | `src/server/Services/{CombatService, WeaponService, ShopService, MorphLabSceneBuilder, FreeRoamService, PlayerDataService}.luau`, `src/server/Maps/*`, `src/server/Weapons/WeaponImporter.luau`, `src/server/Party/PartyCore.luau` |
| Cliente | `src/client/Combat/*`, `src/client/MorphLab/*`, `src/client/Lobby/{HubUI, LobbyController}.luau`, `src/client/FreeRoam/FreeRoamController.luau` |
