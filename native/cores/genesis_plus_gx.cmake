# ---------------------------------------------------------------------------
# Genesis Plus GX (licencia no comercial de Genesis Plus GX; ver
# third_party/genesis_plus_gx/LICENSE.txt): Sega Mega Drive / Genesis, Master
# System, Game Gear, SG-1000 y Mega-CD -> libgenesis_plus_gx_libretro.so/.dll
# Traducción de libretro/Makefile.common y libretro/jni/Android.mk.
# Todo por software y sin JIT: funciona igual en Android, Windows e iPhone.
# ---------------------------------------------------------------------------
set(GPGX ${CMAKE_CURRENT_SOURCE_DIR}/third_party/genesis_plus_gx)
set(GPGX_LRC ${GPGX}/libretro/libretro-common)
set(GPGX_DEPS ${GPGX}/libretro/deps)

set(GPGX_DIRS core core/z80 core/m68k core/ntsc core/sound core/sound/minimp3
    core/input_hw core/cd_hw core/cart_hw core/cart_hw/svp)
set(GPGX_SRC)
set(GPGX_INC ${GPGX}/libretro ${GPGX_LRC}/include
    ${GPGX_DEPS}/libchdr/include ${GPGX_DEPS}/lzma-19.00/include
    ${GPGX_DEPS}/zlib-1.2.11 ${GPGX_DEPS}/zstd/lib ${GPGX}/core/sound/tremor)
foreach(dir ${GPGX_DIRS})
  file(GLOB files ${GPGX}/${dir}/*.c)
  list(APPEND GPGX_SRC ${files})
  list(APPEND GPGX_INC ${GPGX}/${dir})
endforeach()
file(GLOB GPGX_TREMOR ${GPGX}/core/sound/tremor/*.c)
list(APPEND GPGX_SRC ${GPGX_TREMOR}
  ${GPGX}/libretro/libretro.c
  # libretro-common
  ${GPGX_LRC}/streams/file_stream.c ${GPGX_LRC}/streams/file_stream_transforms.c
  ${GPGX_LRC}/compat/fopen_utf8.c ${GPGX_LRC}/compat/compat_snprintf.c
  ${GPGX_LRC}/compat/compat_strl.c ${GPGX_LRC}/compat/compat_strcasestr.c
  ${GPGX_LRC}/compat/compat_posix_string.c ${GPGX_LRC}/encodings/encoding_utf.c
  ${GPGX_LRC}/file/file_path.c ${GPGX_LRC}/file/retro_dirent.c
  ${GPGX_LRC}/lists/string_list.c ${GPGX_LRC}/lists/dir_list.c
  ${GPGX_LRC}/memmap/memalign.c ${GPGX_LRC}/string/stdstring.c
  ${GPGX_LRC}/vfs/vfs_implementation.c
  # zlib, lzma, zstd y libchdr (discos de Mega-CD en .chd)
  ${GPGX_DEPS}/zlib-1.2.11/adler32.c ${GPGX_DEPS}/zlib-1.2.11/crc32.c
  ${GPGX_DEPS}/zlib-1.2.11/inffast.c ${GPGX_DEPS}/zlib-1.2.11/inflate.c
  ${GPGX_DEPS}/zlib-1.2.11/inftrees.c ${GPGX_DEPS}/zlib-1.2.11/zutil.c)
foreach(f Alloc Bra86 BraIA64 CpuArch Delta LzFind Lzma86Dec LzmaDec LzmaEnc Sort)
  list(APPEND GPGX_SRC ${GPGX_DEPS}/lzma-19.00/src/${f}.c)
endforeach()
foreach(f bitstream cdrom chd flac huffman)
  list(APPEND GPGX_SRC ${GPGX_DEPS}/libchdr/src/libchdr_${f}.c)
endforeach()
foreach(f common/entropy_common common/error_private common/fse_decompress common/zstd_common
          common/xxhash decompress/huf_decompress decompress/zstd_ddict
          decompress/zstd_decompress decompress/zstd_decompress_block)
  list(APPEND GPGX_SRC ${GPGX_DEPS}/zstd/lib/${f}.c)
endforeach()

add_library(genesis_plus_gx_libretro SHARED ${GPGX_SRC})
target_include_directories(genesis_plus_gx_libretro PRIVATE ${GPGX_INC})
# INLINE y GIT_VERSION llevan espacios o comillas: van en una cabecera que se
# incluye en todos los archivos (las definiciones con espacios se rompen en la
# línea de órdenes de Windows).
file(WRITE ${CMAKE_BINARY_DIR}/gpgx_defs/gpgx_defs.h
  "#define INLINE static inline
#define GIT_VERSION \" 4fd32efe\"
")
target_compile_options(genesis_plus_gx_libretro PRIVATE
  -include ${CMAKE_BINARY_DIR}/gpgx_defs/gpgx_defs.h)
target_compile_definitions(genesis_plus_gx_libretro PRIVATE
  USE_LIBTREMOR USE_16BPP_RENDERING LSB_FIRST BYTE_ORDER=LITTLE_ENDIAN
  __LIBRETRO__ FRONTEND_SUPPORTS_RGB565 ALIGN_LONG ALIGN_WORD
  M68K_OVERCLOCK_SHIFT=20 Z80_OVERCLOCK_SHIFT=20 HAVE_YM3438_CORE HAVE_OPLL_CORE
  USE_LIBCHDR _7ZIP_ST ZSTD_DISABLE_ASM USE_LIBRETRO_VFS USE_PER_SOUND_CHANNELS_CONFIG
  MAXROMSIZE=16777216)
target_compile_options(genesis_plus_gx_libretro PRIVATE -w -O2 -ffast-math -funroll-loops)
if(WIN32)
  target_compile_definitions(genesis_plus_gx_libretro PRIVATE strcasecmp=_stricmp strncasecmp=_strnicmp)
  target_include_directories(genesis_plus_gx_libretro PRIVATE ${RS_WIN_COMPAT})
endif()
set_target_properties(genesis_plus_gx_libretro PROPERTIES PREFIX "lib")
rs_version_script(genesis_plus_gx_libretro ${GPGX}/libretro/link.T)
