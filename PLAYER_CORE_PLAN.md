# TV FULL Android TV Player Core

Este documento congela la dirección técnica después de las pruebas V1-V6. No se eliminan ramas ni experimentos anteriores.

## Objetivo

Construir un único núcleo de reproducción Android TV mantenible y medible, en lugar de crear una rama por cada ajuste de buffer/decoder.

## Principios

1. La carga de listas, panel, clientes y catálogo sigue en Flutter.
2. La reproducción LIVE de Android TV vive en una Activity Android nativa con `SurfaceView` directa.
3. No se envían listas grandes por MethodChannel. Flutter escribe un payload temporal y Android lo carga fuera del hilo UI.
4. El motor principal es Media3/ExoPlayer moderno con MediaCodec, decoder fallback y NextLib/FFmpeg como extensión.
5. Android MediaPlayer es un segundo backend realmente distinto.
6. Si ambos backends nativos fallan, se vuelve al reproductor MPV ya existente en Flutter.
7. Cada decisión de fallback debe estar respaldada por telemetría local: primer frame, decoder, dropped frames, errores de codec, buffering y resolución.
8. Un solo branch de trabajo de Player Core; las mejoras se hacen por commits, no por nuevas ramas de prueba.

## Política inicial de motores

- MEDIA3: primera opción.
- NATIVE: fallback cuando Media3 no entrega primer frame, falla el codec o acumula caída severa de frames.
- MPV: último fallback a la implementación existente de TV FULL.

## Criterios de salud

- timeout de primer frame: 8 s.
- fallo de codec/player: fallback inmediato.
- dropped frames severos de Media3: dos ventanas malas consecutivas antes de cambiar motor.
- un motor que falla no se reintenta en bucle sobre el mismo canal.

## Red LIVE

- `DefaultHttpDataSource` con headers originales del canal.
- redirecciones entre protocolos habilitadas.
- connect timeout 8 s.
- read timeout 15 s.
- buffer basado en tiempo, no en decenas de MB: 3-12 s; 0.8 s para arrancar; 1.2 s tras rebuffer.

## Diagnóstico

El reproductor debe mostrar bajo demanda:
- backend actual;
- decoder;
- codec/formato y resolución;
- dropped frames;
- buffer;
- razón del último fallback;
- Android/API/ABI.

También guarda un JSONL local para poder diagnosticar una TV real sin adivinar.
