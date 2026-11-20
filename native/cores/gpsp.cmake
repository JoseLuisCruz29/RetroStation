# ---------------------------------------------------------------------------
# gpSP (GPL-2.0): segundo núcleo de Game Boy Advance -> libgpsp_libretro.so
# Traducción de third_party/gpsp/jni/Android.mk y Makefile.common (5819380).
#
# Se usa solo para el multijugador por Wi-Fi: emula el cable link de Pokémon
# (3.ª generación) y el Adaptador Inalámbrico de GBA a través de la interfaz
# netpacket de libretro (cada jugador con su propio juego y su partida).
# El resto del tiempo la GBA usa mGBA, que es más preciso.
# ---------------------------------------------------------------------------
set(GPSP ${CMAKE_CURRENT_SOURCE_DIR}/third_party/gpsp)
set(GPSP_COMMON ${GPSP}/libretro/libretro-common)

set(GPSP_SRC
  ${GPSP}/bios_data.S ${GPSP}/video.cc ${GPSP}/cpu.cc
  ${GPSP}/main.c ${GPSP}/gba_memory.c ${GPSP}/savestate.c ${GPSP}/input.c ${GPSP}/sound.c
  ${GPSP}/cheats.c ${GPSP}/memmap.c ${GPSP}/serial.c ${GPSP}/gbp.c ${GPSP}/rfu.c
  ${GPSP}/serial_proto.c ${GPSP}/libretro/libretro.c ${GPSP}/gba_cc_lut.c
  ${GPSP}/cpu_threaded.c
  ${GPSP_COMMON}/compat/compat_posix_string.c ${GPSP_COMMON}/compat/compat_strl.c
  ${GPSP_COMMON}/compat/fopen_utf8.c ${GPSP_COMMON}/encodings/encoding_utf.c
  ${GPSP_COMMON}/file/file_path.c ${GPSP_COMMON}/file/file_path_io.c
  ${GPSP_COMMON}/streams/file_stream.c ${GPSP_COMMON}/string/stdstring.c
  ${GPSP_COMMON}/time/rtime.c ${GPSP_COMMON}/vfs/vfs_implementation.c
)
if(ANDROID_ABI STREQUAL "armeabi-v7a")
  list(APPEND GPSP_SRC ${GPSP}/arm/arm_stub.S)
  set(GPSP_ARCH ARM_ARCH)
elseif(ANDROID_ABI STREQUAL "arm64-v8a")
  list(APPEND GPSP_SRC ${GPSP}/arm/arm64_stub.S)
  set(GPSP_ARCH ARM64_ARCH)
elseif(WIN32)
  # Windows x64: recompilador x86 (como el Makefile oficial para "win").
  list(APPEND GPSP_SRC ${GPSP}/x86/x86_stub.S)
  set(GPSP_ARCH X86_ARCH WIN32 __WIN32__ __WIN32_LIBRETRO__)
else()
  list(APPEND GPSP_SRC ${GPSP}/x86/x86_stub.S)
  set(GPSP_ARCH X86_ARCH)
endif()

add_library(gpsp_libretro SHARED ${GPSP_SRC})
target_include_directories(gpsp_libretro PRIVATE ${GPSP}/libretro ${GPSP_COMMON}/include ${GPSP})
if(WIN32)
  target_include_directories(gpsp_libretro PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/compat/win)
endif()
target_compile_definitions(gpsp_libretro PRIVATE
  INLINE=inline __LIBRETRO__ FRONTEND_SUPPORTS_RGB565 ${GPSP_ARCH} MMAP_JIT_CACHE HAVE_DYNAREC
  GIT_VERSION="5819380")
# El recompilador genera código ARM (no Thumb), como LOCAL_ARM_MODE := arm.
target_compile_options(gpsp_libretro PRIVATE -w -O2 -fno-strict-aliasing
  $<$<STREQUAL:${ANDROID_ABI},armeabi-v7a>:-marm>)
set_target_properties(gpsp_libretro PROPERTIES PREFIX "lib")
rs_version_script(gpsp_libretro ${GPSP}/link.T)
