cmake_minimum_required(VERSION 3.22)
project(retrostation_native C CXX ASM)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

# Windows (escritorio): Clang de Visual Studio, DLLs junto al .exe de Flutter.
# Núcleos: NES, SNES, GB/GBC/GBA, gpSP, GBA Link, PS1 (intérprete) y DS
# (melonDS con JIT). PSP aún no: necesita OpenGL por hardware.
if(WIN32)
  option(RS_WINDOWS_EXTRA_CORES "Compilar también PS1 y DS en Windows" ON)
  add_compile_definitions(_CRT_SECURE_NO_WARNINGS _CRT_NONSTDC_NO_DEPRECATE)
  # Las DLL no dependen del runtime de C++ dinámico (no hace falta instalar nada).
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded")
  # zlib: la copia de mGBA, compilada aparte (Windows no la trae).
  set(RS_ZLIB ${CMAKE_CURRENT_SOURCE_DIR}/third_party/mgba/src/third-party/zlib)
  add_library(rs_zlib STATIC
    ${RS_ZLIB}/adler32.c ${RS_ZLIB}/compress.c ${RS_ZLIB}/crc32.c ${RS_ZLIB}/deflate.c
    ${RS_ZLIB}/inffast.c ${RS_ZLIB}/inflate.c ${RS_ZLIB}/inftrees.c ${RS_ZLIB}/trees.c
    ${RS_ZLIB}/uncompr.c ${RS_ZLIB}/zutil.c)
  target_include_directories(rs_zlib PUBLIC ${RS_ZLIB})
  target_compile_options(rs_zlib PRIVATE -w)
  # Cabeceras de POSIX que faltan en Windows (unistd.h, strings.h, sys/time.h).
  set(RS_WIN_COMPAT ${CMAKE_CURRENT_SOURCE_DIR}/compat/win)
endif()

# iPhone (cmake -DCMAKE_SYSTEM_NAME=iOS): cada biblioteca .dylib se empaqueta
# luego como .framework dentro de la app (tool/build_ios_native.sh). Primera
# etapa: NES, SNES, GB/GBC/GBA y el cable link de GBA. iOS no deja generar
# código en tiempo real (JIT): PS1, DS y gpSP usan sus intérpretes.
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
  set(RS_IOS ON)
endif()

# Versión del enlazador GNU para exportar solo retro_*; en Windows (lld-link)
# los núcleos ya exportan con __declspec(dllexport) desde libretro.h, y el
# enlazador de Apple no admite --version-script.
function(rs_version_script target script)
  if(NOT WIN32 AND NOT APPLE)
    target_link_options(${target} PRIVATE -Wl,--version-script=${script})
  endif()
endfunction()

# ---------------------------------------------------------------------------
# Núcleo mGBA (MPL-2.0) compilado como núcleo libretro: libmgba_libretro.so
# Solo el núcleo: sin frontends, depuradores, scripting ni dependencias externas.
# ---------------------------------------------------------------------------
set(LIBMGBA_ONLY OFF CACHE BOOL "" FORCE)
foreach(opt BUILD_QT BUILD_SDL BUILD_GL BUILD_GLES2 BUILD_GLES3 BUILD_STATIC
            BUILD_SHARED BUILD_PERF BUILD_TEST BUILD_SUITE BUILD_CINEMA
            BUILD_ROM_TEST BUILD_EXAMPLE BUILD_PYTHON BUILD_DOCGEN USE_EPOXY
            USE_DEBUGGERS USE_EDITLINE USE_GDB_STUB USE_FFMPEG USE_ZLIB
            USE_MINIZIP USE_PNG USE_LIBZIP USE_SQLITE3 USE_ELF USE_LUA USE_LZMA
            USE_DISCORD_RPC ENABLE_SCRIPTING)
  set(${opt} OFF CACHE BOOL "" FORCE)
endforeach()
set(BUILD_LIBRETRO ON CACHE BOOL "" FORCE)
set(SKIP_LIBRARY ON CACHE BOOL "" FORCE)
set(DISABLE_DEPS ON CACHE BOOL "" FORCE)
set(M_CORE_GBA ON CACHE BOOL "" FORCE)
set(M_CORE_GB ON CACHE BOOL "" FORCE)

if(WIN32)
  # mGBA enlaza la biblioteca matemática "m" de Unix; en Windows va en el runtime de C.
  add_library(m INTERFACE)
endif()
add_subdirectory(third_party/mgba ${CMAKE_BINARY_DIR}/mgba)
# Android empaqueta y carga bibliotecas con el prefijo "lib".
set_target_properties(mgba_libretro PROPERTIES PREFIX "lib")
# -fwrapv: la CPU emulada calcula flags (p. ej. overflow) con aritmética con
# signo que desborda. Sin esta opción, clang -O2 elimina esas comprobaciones
# (comportamiento indefinido en C) y falla gba-tests/thumb, prueba 102.
target_compile_options(mgba_libretro PRIVATE -fwrapv)

# ---------------------------------------------------------------------------
# FCEUmm (GPL-2.0): núcleo libretro de NES -> libfceumm_libretro.so
# Lista de fuentes tomada de third_party/fceumm/Makefile.common.
# ---------------------------------------------------------------------------
set(FCEUMM_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/fceumm/src)
set(FCEUMM_COMMON ${FCEUMM_DIR}/drivers/libretro/libretro-common)
file(GLOB FCEUMM_BOARDS ${FCEUMM_DIR}/boards/*.c)
file(GLOB FCEUMM_INPUT ${FCEUMM_DIR}/input/*.c)
add_library(fceumm_libretro SHARED
  ${FCEUMM_BOARDS} ${FCEUMM_INPUT}
  ${FCEUMM_DIR}/drivers/libretro/libretro.c
  ${FCEUMM_DIR}/drivers/libretro/libretro_dipswitch.c
  ${FCEUMM_DIR}/cart.c ${FCEUMM_DIR}/cheat.c ${FCEUMM_DIR}/crc32.c
  ${FCEUMM_DIR}/fceu-endian.c ${FCEUMM_DIR}/fceu-memory.c ${FCEUMM_DIR}/fceu.c
  ${FCEUMM_DIR}/fds.c ${FCEUMM_DIR}/fds_apu.c ${FCEUMM_DIR}/file.c ${FCEUMM_DIR}/filter.c
  ${FCEUMM_DIR}/general.c ${FCEUMM_DIR}/input.c ${FCEUMM_DIR}/md5.c ${FCEUMM_DIR}/nsf.c
  ${FCEUMM_DIR}/palette.c ${FCEUMM_DIR}/ppu.c ${FCEUMM_DIR}/sound.c ${FCEUMM_DIR}/state.c
  ${FCEUMM_DIR}/video.c ${FCEUMM_DIR}/vsuni.c ${FCEUMM_DIR}/ines.c ${FCEUMM_DIR}/unif.c
  ${FCEUMM_DIR}/x6502.c
  ${FCEUMM_COMMON}/streams/memory_stream.c
  ${FCEUMM_COMMON}/compat/compat_posix_string.c
  ${FCEUMM_COMMON}/compat/compat_snprintf.c
  ${FCEUMM_COMMON}/compat/compat_strcasestr.c
  ${FCEUMM_COMMON}/compat/compat_strl.c
  ${FCEUMM_COMMON}/compat/fopen_utf8.c
  ${FCEUMM_COMMON}/encodings/encoding_utf.c
  ${FCEUMM_COMMON}/file/file_path.c
  ${FCEUMM_COMMON}/file/file_path_io.c
  ${FCEUMM_COMMON}/streams/file_stream.c
  ${FCEUMM_COMMON}/streams/file_stream_transforms.c
  ${FCEUMM_COMMON}/string/stdstring.c
  ${FCEUMM_COMMON}/time/rtime.c
  ${FCEUMM_COMMON}/vfs/vfs_implementation.c
)
target_include_directories(fceumm_libretro PRIVATE
  ${FCEUMM_DIR}/drivers/libretro ${FCEUMM_COMMON}/include
  ${FCEUMM_DIR} ${FCEUMM_DIR}/input ${FCEUMM_DIR}/boards)
target_compile_definitions(fceumm_libretro PRIVATE
  __LIBRETRO__ PATH_MAX=1024 FCEU_VERSION_NUMERIC=9900 FRONTEND_SUPPORTS_RGB565)
target_compile_options(fceumm_libretro PRIVATE -fwrapv -fno-strict-aliasing -w)
set_target_properties(fceumm_libretro PROPERTIES PREFIX "lib")

# ---------------------------------------------------------------------------
# Snes9x (licencia Snes9x: uso no comercial): núcleo de SNES -> libsnes9x_libretro.so
# Fuentes y opciones de third_party/snes9x/libretro/{Makefile.common,jni/Android.mk}.
# ---------------------------------------------------------------------------
set(SNES9X_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/snes9x)
set(SNES9X_COMMON ${SNES9X_DIR}/libretro/libretro-common)
add_library(snes9x_libretro SHARED
  ${SNES9X_DIR}/c4emu.c ${SNES9X_DIR}/msu1.c ${SNES9X_DIR}/zipfile.c ${SNES9X_DIR}/srtc.c
  ${SNES9X_DIR}/obc1.c ${SNES9X_DIR}/bsflash.c ${SNES9X_DIR}/tile.c ${SNES9X_DIR}/bsx.c
  ${SNES9X_DIR}/spc7110.c ${SNES9X_DIR}/fxemu.c ${SNES9X_DIR}/sdd1.c ${SNES9X_DIR}/seta.c
  ${SNES9X_DIR}/sa1hw.c ${SNES9X_DIR}/dsp.c ${SNES9X_DIR}/filter/snes_ntsc.c
  ${SNES9X_DIR}/apu/apu.cpp ${SNES9X_DIR}/apu/bapu/dsp/sdsp.cpp
  ${SNES9X_DIR}/apu/bapu/smp/smp.cpp ${SNES9X_DIR}/apu/bapu/smp/smp_state.cpp
  ${SNES9X_DIR}/cheats2.cpp ${SNES9X_DIR}/clip.cpp ${SNES9X_DIR}/controls.cpp
  ${SNES9X_DIR}/cpu.cpp ${SNES9X_DIR}/cpuexec.cpp ${SNES9X_DIR}/cpuops.cpp
  ${SNES9X_DIR}/crosshairs.cpp ${SNES9X_DIR}/dma.cpp ${SNES9X_DIR}/gfx.cpp
  ${SNES9X_DIR}/globals.cpp ${SNES9X_DIR}/loadzip.cpp ${SNES9X_DIR}/memmap.cpp
  ${SNES9X_DIR}/ppu.cpp ${SNES9X_DIR}/sa1.cpp ${SNES9X_DIR}/sa1cpu.cpp
  ${SNES9X_DIR}/snapshot.cpp ${SNES9X_DIR}/sha256.cpp ${SNES9X_DIR}/bml.cpp
  ${SNES9X_DIR}/fscompat.cpp ${SNES9X_DIR}/libretro/libretro.cpp
  ${SNES9X_COMMON}/compat/compat_posix_string.c
  ${SNES9X_COMMON}/compat/compat_strcasestr.c
  ${SNES9X_COMMON}/compat/compat_snprintf.c
  ${SNES9X_COMMON}/compat/compat_strl.c
  ${SNES9X_COMMON}/compat/fopen_utf8.c
  ${SNES9X_COMMON}/encodings/encoding_utf.c
  ${SNES9X_COMMON}/encodings/encoding_deflate.c
  ${SNES9X_COMMON}/file/file_path.c
  ${SNES9X_COMMON}/file/file_path_io.c
  ${SNES9X_COMMON}/streams/file_stream.c
  ${SNES9X_COMMON}/streams/file_stream_transforms.c
  ${SNES9X_COMMON}/string/stdstring.c
  ${SNES9X_COMMON}/time/rtime.c
  ${SNES9X_COMMON}/vfs/vfs_implementation.c
  ${SNES9X_COMMON}/vfs/vfs_hybrid.c
  ${SNES9X_COMMON}/file/retro_dirent.c
)
target_include_directories(snes9x_libretro PRIVATE
  ${SNES9X_DIR}/libretro ${SNES9X_COMMON}/include ${SNES9X_DIR}
  ${SNES9X_DIR}/apu ${SNES9X_DIR}/apu/bapu)
target_compile_definitions(snes9x_libretro PRIVATE
  __LIBRETRO__ ALLOW_CPU_OVERCLOCK GIT_VERSION="")
if(ANDROID)
  target_compile_definitions(snes9x_libretro PRIVATE ANDROID HAVE_STRINGS_H)
elseif(WIN32)
  target_compile_definitions(snes9x_libretro PRIVATE strcasecmp=_stricmp strncasecmp=_strnicmp)
  # Con el ABI de MSVC, C++ decora también las variables globales: los .c del
  # núcleo que usan Settings, OpenBus... tienen que compilarse como C++.
  foreach(f msu1 srtc)
    set_source_files_properties(${SNES9X_DIR}/${f}.c PROPERTIES LANGUAGE CXX)
  endforeach()
  # Los demás .c usan estas dos variables de C++ con su nombre de C: el
  # enlazador las resuelve con su nombre decorado.
  target_link_options(snes9x_libretro PRIVATE
    "LINKER:/alternatename:OpenBus=?OpenBus@@3EA"
    "LINKER:/alternatename:LineMatrixData=?LineMatrixData@@3PAUSLineMatrixData@@A")
endif()
target_compile_options(snes9x_libretro PRIVATE -fwrapv -fno-strict-aliasing -w)
set_target_properties(snes9x_libretro PROPERTIES PREFIX "lib" CXX_STANDARD 14)
# Solo se exportan los símbolos retro_* (versión de enlace oficial).
rs_version_script(snes9x_libretro ${SNES9X_DIR}/libretro/link.T)

if(NOT WIN32 OR RS_WINDOWS_EXTRA_CORES)
  include(cores/pcsx_rearmed.cmake)
  include(cores/melonds.cmake)
endif()
include(cores/gpsp.cmake)
include(cores/gbalink.cmake)
if(ANDROID)
  include(cores/desmume.cmake)
endif()

# ---------------------------------------------------------------------------
# Frontend libretro de RetroStation (API C expuesta a Dart FFI)
# ---------------------------------------------------------------------------
add_library(retrostation_native SHARED
  frontend/rs_frontend.cpp
  frontend/audio_output.cpp
  frontend/hw_render.cpp
  frontend/hw_render_win.cpp
  frontend/netplay.cpp
)
target_include_directories(retrostation_native PRIVATE
  frontend
  third_party/mgba/src/platform/libretro   # libretro.h
)
target_compile_options(retrostation_native PRIVATE -Wall -Wextra -fvisibility=hidden)
if(ANDROID)
  # AAudio (Android 8.0+) se carga con dlopen; OpenSL ES es la alternativa en 7.x.
  # EGL y GLES 3: renderizado por GPU de núcleos como PPSSPP.
  target_link_libraries(retrostation_native android log dl OpenSLES EGL GLESv3 z)
elseif(WIN32)
  # zlib (estados del multijugador): rs_zlib, definida al principio.
  target_link_libraries(retrostation_native rs_zlib ws2_32 ole32 opengl32)
elseif(APPLE)
  # Sonido con CoreAudio (RemoteIO); zlib viene con el sistema.
  target_link_libraries(retrostation_native "-framework AudioToolbox" "-framework CoreFoundation" z)
endif()
# El núcleo se carga en tiempo de ejecución, pero debe compilarse siempre
# junto al frontend para que se empaquete con la app.
# (En iPhone no: cada núcleo se compila por separado y uno que falle no debe
# impedir compilar el motor; ver tool/build_ios_native.sh.)
foreach(core mgba_libretro fceumm_libretro snes9x_libretro pcsx_rearmed_libretro
             melonds_libretro gpsp_libretro desmume2015_libretro gbalink_libretro)
  if(TARGET ${core} AND NOT RS_IOS)
    add_dependencies(retrostation_native ${core})
  endif()
endforeach()

# Prueba del multijugador desde adb shell (no se incluye en la app):
# cmake -DRS_BUILD_TOOLS=ON ... && ninja rs_netplay_test
option(RS_BUILD_TOOLS "Herramientas de prueba de línea de comandos" OFF)
if(RS_BUILD_TOOLS AND NOT WIN32)
  add_executable(rs_netplay_test tools/netplay_test.cpp)
  target_include_directories(rs_netplay_test PRIVATE frontend)
  target_link_libraries(rs_netplay_test retrostation_native)
endif()
