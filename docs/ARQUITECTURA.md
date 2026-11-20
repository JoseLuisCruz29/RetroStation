# Arquitectura de RetroStation

## Capas

```
presentation/  (pantallas y widgets: solo UI, sin lógica de emulación)
      │  Riverpod (providers)
      ▼
game_library/ save_manager/ settings/ discovery/ download_manager/ metadata/
      │
      ▼
storage/  (SQLite con drift + directorios privados)      engines/ (registro de consolas)
                                                              │
emulation/  (sesión de emulación en Dart) ── Dart FFI ──► native/frontend (C++, API libretro)
                                                              │
                                                     núcleos libretro enlazados estáticamente
                                                     (mGBA → GBA; después GB/GBC, NES, SNES...)
```

## Módulos (`lib/`)

| Módulo | Responsabilidad | Estado |
|---|---|---|
| `app/` | Arranque, router (go_router), tema, shell de navegación | Etapa 1 ✓ |
| `core/` | Utilidades comunes (formato, errores, hashing) | Etapa 1 (formato) |
| `storage/` | Base de datos drift, directorios privados, uso de disco, validación de rutas | Etapa 1 ✓ |
| `engines/` | Descriptores de consola: extensiones, núcleo, licencia, estado | Etapa 1 ✓ |
| `game_library/` | Repositorio de juegos, categorías y filtros | Etapa 1 (lectura y favoritos) · importación en Etapa 4 |
| `save_manager/` | Save states y SRAM | Etapa 1 (listado y borrado) · creación en Etapa 3 |
| `settings/` | Ajustes persistentes | Etapa 1 (apariencia) |
| `emulation/` | `EmulatorSession` (textura, botones, pausa, ciclo de vida) y `RetroNative` (bindings FFI escritos a mano) | Etapa 2 ✓ |
| `controllers/` | Controles táctiles y mandos | Etapa 3 / 7 |
| `metadata/` | Portadas, DATs No-Intro, metadatos | Etapa 4-5 |
| `discovery/` | `SourceAdapter` y un adaptador por fuente | Etapa 5 |
| `download_manager/` | Descargas, verificación y extracción | Etapa 6 |
| `presentation/` | Pantallas: Inicio, Descubrir, Biblioteca, Consolas, Reproductor, Partidas, Ajustes | Etapa 1 ✓ |

Las carpetas de los módulos que aún no tienen código se crean en la etapa que las implementa.

## Decisiones

- **Frontend libretro propio en C++**: todos los núcleos comparten una interfaz (video, audio, input, `retro_serialize`, `RETRO_MEMORY_SAVE_RAM`). Añadir una consola consiste en compilar su núcleo y registrar un `ConsoleDescriptor`.
- **Núcleos enlazados estáticamente**: iOS prohíbe cargar código ejecutable descargado, y así Android usa el mismo modelo.
- **Video mediante textura nativa** (`Texture` de Flutter): no se copian fotogramas a Dart.
- **Audio con miniaudio** (AAudio/OpenSL en Android, CoreAudio en iOS) y un buffer circular para la sincronización.
- **Estado con Riverpod**: los providers raíz (`databaseProvider`, `appPathsProvider`, `initialSettingsProvider`) se inicializan en `main()` y se sobrescriben en las pruebas.
- **Base de datos drift (SQLite)** dentro del directorio privado de soporte de la app. El SHA-1 del ROM es único y evita duplicados. Las claves foráneas están activadas, así que al borrar un juego se borran sus save states.
- **Material**: en Flutter 3.50 se importa desde `package:material_ui/material_ui.dart`.

## Código nativo (`native/`)

- `CMakeLists.txt` compila mGBA como `libmgba_libretro.so` (sin frontends ni dependencias, con `-fwrapv`) y el frontend `libretrostation_native.so`. Gradle lo incluye mediante `externalNativeBuild` y siempre en Release/-O2.
- `frontend/rs_frontend.h`: API C (`rs_load`, `rs_start`, `rs_set_paused`, `rs_set_buttons`, `rs_reset`, `rs_save_sram`, `rs_get_fps`, `rs_unload`...).
- Hilos: el núcleo solo se llama con `core_mutex` tomado. La superficie se protege con `window_mutex`, porque Kotlin puede cambiarla en cualquier momento mediante JNI (`NativeVideo.setSurface`).
- Kotlin (`MainActivity`): canal `retrostation/video` con `create` (crea el `SurfaceProducer` y devuelve el id de la textura) y `release`.
- Añadir un núcleo: compilarlo como objetivo CMake con prefijo `lib`, y darle `coreLibrary` y `status: available` en su `ConsoleDescriptor`.

## Datos

- `games`: título, consola, ruta del ROM, sha1, tamaño, portada, género, año, procedencia (`sourceId`, `sourceUrl`), estado (`installed`/`pending`/`downloading`), favorito, fechas y tiempo jugado.
- `save_states`: juego, ranura (única por juego), archivo, miniatura y fecha.
- `setting_entries`: pares clave/valor de ajustes.

## Directorios privados

`<ApplicationSupport>/retrostation/{roms,saves,states,covers,downloads,system}`. La SRAM se guarda en `saves/<sha1>.srm`. `AppPaths.contains()` valida que una ruta no salga de este directorio; se usará en la extracción de ZIP y 7Z (protección contra zip-slip).
