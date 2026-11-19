# Validación de REALITY 2059

Revisión iniciada el 12/11/2026 y retomada el 15/11/2026. Lugar local: `../Proyecto C.rbxl`; Studio 0.747.0.7471481. Código sincronizado con Rojo 7.7.1 en localhost:34872. No se publicó la experiencia.

## Comprobado

- Recorrido con clics reales: modo libre → MENÚ → MODO LIBRE → JUGAR → ciudad, con personaje a 100 de salud. Corregido el inventario que tapaba MENÚ: ambos usan el mismo margen de interfaz y quedan separados por 12 píxeles.
- Compilación `rojo build default.project.json` y `git diff --check`.
- Rojo reconectado el 15/11: un comentario temporal en ShotValidator llegó a Studio y su retirada se sincronizó. No queda el comentario.
- Doce suites en Studio: Phase B 8/8, C.1 4/4, C.2 4/4, C.3.1 163/163, variantes 25/25, avatar 3/3, lobby 6/6, modo libre 3/3, inventario 5/5, grupos 7/7, vida urbana 4/4 y validación de combate 22/22. Total: 254/254.
- Pruebas con dos clientes reales mediante StudioTestService: entrada/salida de ciudad, creación y unión a sala privada, estado listo, inicio, cuenta atrás y partida en DistritoNexus.
- Ciclo de partida con dos clientes: 30 eliminaciones inducidas por un script temporal del servidor, reapariciones, puntuación, estados `ended` y `closed` recibidos por ambos. Esta prueba valida el ciclo de partida; no demuestra precisión, equilibrio ni impactos reales entre clientes.
- Corregida la transición ciudad → partida: el controlador activo de modo libre ya no bloquea la activación del mapa y del HUD de combate.
- DistritoNexus generado con el constructor existente, sin sobrescribir mapas. 28 armas importadas con WeaponImporter; inspección posterior: cero LuaSourceContainers dentro de ServerStorage.Weapons.
- Los dos sonidos provisionales de CombatAudioConfig cargan con AssetFetchStatus.Success al precargar instancias Sound. Calidad auditiva y mezcla pendientes de revisión humana.
- Scripts temporales Reality2059QA y Reality2059QAClient retirados del lugar.

## Rendimiento y límites

En las pruebas con dos clientes, ventanas sin foco, muestras de aproximadamente ocho segundos dieron unos 67–68 ms por cuadro y P95 de 68–70 ms; memoria reportada por cada cliente alrededor de 2.1–2.2 GB. Estos números no permiten atribuir un cuello de botella: incluyen Studio, dos clientes y posible limitación de segundo plano. No equivalen a una medición en móvil ni a un benchmark de lanzamiento.

F3 permite repetir la observación en primer plano. P95 usa una ventana móvil de hasta 300 cuadros. Antes de optimizar la ciudad, capturar MicroProfiler en el dispositivo objetivo y la misma ruta de prueba.

Persiste una advertencia de tipo para `rbxassetid://203785492` (metadatos: audio Pop Close Sound). No se encontró una referencia literal en el código del proyecto ni en las propiedades de contenido revisadas del lugar. No se eliminó contenido por suposición.

Persistencia observada: Mock porque este archivo local no está publicado. No se verificaron DataStores reales ni emparejamiento entre servidores. Competitivo permanece bloqueado.

## Prueba manual

1. Mantener Rojo conectado a localhost:34872 y pulsar Play: aparece la interfaz inicial (`DevConfig.QuickStart = false`). Completar el flujo inicial y entrar al modo libre desde JUGAR en el lobby.
2. Caminar, saltar, recorrer rampas, probar cámara y regresar por MENÚ.
3. En JUGAR seleccionar MODO LIBRE y pulsar JUGAR para volver a la ciudad.
4. Para combate, crear una partida privada e invitar otro cliente; probar disparo, recarga, daño, muerte y reaparición con armas reales.
5. Para medir rendimiento, activar F3 y repetir la misma ruta con el cliente en primer plano; revisar móvil por separado.
