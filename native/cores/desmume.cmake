# DeSmuME 2015 (GPL-2.0): núcleo libretro de Nintendo DS -> libdesmume2015_libretro.so
# Traducción de third_party/desmume2015/desmume/src/libretro/jni/Android.mk y
# Makefile.common (commit 422b6880).
#
# Solo se compila para armeabi-v7a: su recompilador dinámico (utils/arm_arm)
# genera código ARM de 32 bits, justo lo que le falta a melonDS en los móviles
# con Android de 32 bits. En 64 bits se usa melonDS, que allí tiene JIT propio.
if(NOT ANDROID_ABI STREQUAL "armeabi-v7a")
  return()
endif()

set(DSM ${CMAKE_CURRENT_SOURCE_DIR}/third_party/desmume2015/desmume/src)

set(DSM_SRC
  armcpu.cpp arm_instructions.cpp bios.cpp cp15.cpp emufile.cpp encrypt.cpp FIFO.cpp
  firmware.cpp GPU.cpp mc.cpp path.cpp readwrite.cpp wifi.cpp MMU.cpp NDSSystem.cpp
  render3D.cpp rtc.cpp saves.cpp slot1.cpp slot2.cpp SPU.cpp matrix.cpp gfx3d.cpp
  thumb_instructions.cpp utils/advanscene.cpp utils/datetime.cpp utils/emufat.cpp
  utils/xstring.cpp utils/decrypt/crc.cpp utils/decrypt/decrypt.cpp utils/decrypt/header.cpp
  utils/vfat.cpp addons/slot2_auto.cpp addons/slot2_mpcf.cpp addons/slot2_paddle.cpp
  addons/slot2_gbagame.cpp addons/slot2_none.cpp addons/slot2_rumblepak.cpp
  addons/slot2_guitarGrip.cpp addons/slot2_expMemory.cpp addons/slot2_piano.cpp
  addons/slot2_passme.cpp addons/slot1_none.cpp addons/slot1_r4.cpp addons/slot1comp_mc.cpp
  addons/slot1comp_rom.cpp addons/slot1comp_protocol.cpp addons/slot1_retail_mcrom.cpp
  addons/slot1_retail_nand.cpp addons/slot1_retail_auto.cpp cheatSystem.cpp texcache.cpp
  rasterize.cpp mic.cpp driver.cpp libretro/libretro.cpp libretro/scrc32.cpp
  addons/slot1_retail_mcrom_debug.cpp utils/fsnitro.cpp utils/task.cpp
  # JIT de ARM de 32 bits (DESMUME_JIT_ARM := 1 en Android.mk).
  utils/arm_arm/arm_gen.cpp utils/arm_arm/arm_jit.cpp
  # C
  utils/libfat/partition.c utils/libfat/cache.c utils/libfat/directory.c utils/libfat/disc.c
  utils/libfat/fatdir.c utils/libfat/fatfile.c utils/libfat/filetime.c
  utils/libfat/file_allocation_table.c utils/libfat/libfat.c utils/libfat/libfat_public_api.c
  utils/libfat/lock.c libretro-common/rthreads/rthreads.c common.c utils/dlditool.c
  libretro-common/memmap/memalign.c libretro-common/streams/file_stream.c
  libretro-common/features/features_cpu.c libretro-common/compat/compat_strl.c
  libretro-common/file/retro_dirent.c libretro-common/file/retro_stat.c
  libretro-common/file/file_path.c libretro-common/string/stdstring.c version.c
)
list(TRANSFORM DSM_SRC PREPEND ${DSM}/)

add_library(desmume2015_libretro SHARED ${DSM_SRC})
target_include_directories(desmume2015_libretro PRIVATE
  ${DSM}/libretro-common/include ${DSM} ${DSM}/libretro)
target_compile_definitions(desmume2015_libretro PRIVATE
  HAVE_JIT ANDROID FRONTEND_SUPPORTS_RGB565 GIT_VERSION="422b6880"
  # Sin la temporización avanzada del bus (opción que la app no usa): evita
  # comprobarla en cada acceso a memoria. Ver MMU_timing.h.
  RS_NO_ADVANCED_TIMING)
# -marm: el intérprete y el código que llama al JIT van mejor en modo ARM
# que en Thumb; -mtune solo ajusta, no limita los procesadores compatibles.
target_compile_options(desmume2015_libretro PRIVATE -w -O3 -fwrapv -fno-strict-aliasing
  -marm -mtune=cortex-a55
  $<$<COMPILE_LANGUAGE:CXX>:-fexceptions -Wno-write-strings -Wno-c++11-narrowing>)
set_target_properties(desmume2015_libretro PROPERTIES PREFIX "lib" CXX_STANDARD 11)
# ThinLTO: permite integrar entre archivos las funciones de memoria (MMU) que
# el JIT y el intérprete llaman millones de veces por segundo.
target_compile_options(desmume2015_libretro PRIVATE -flto=thin)
target_link_options(desmume2015_libretro PRIVATE -flto=thin -O3)
target_link_options(desmume2015_libretro PRIVATE
  -Wl,--version-script=${DSM}/libretro/link.T)
target_link_libraries(desmume2015_libretro z log)
