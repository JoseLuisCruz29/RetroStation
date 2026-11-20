# PCSX ReARMed (GPL-2.0): núcleo libretro de PlayStation -> libpcsx_rearmed_libretro.so
# Traducción de third_party/pcsx_rearmed/jni/Android.mk (commit 7b0e8f8f):
# - arm64-v8a / armeabi-v7a: recompilador dinámico "ari64" + GPU NEON
# - x86_64: recompilador "lightrec" (GNU Lightning) + GPU NEON/SIMD en C
set(PCSX_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/third_party/pcsx_rearmed)
set(PCSX_CORE ${PCSX_ROOT}/libpcsxcore)
set(PCSX_SPU ${PCSX_ROOT}/plugins/dfsound)
set(PCSX_GPU ${PCSX_ROOT}/plugins/gpulib)
set(PCSX_FE ${PCSX_ROOT}/frontend)
set(PCSX_NEON ${PCSX_ROOT}/plugins/gpu_neon)
set(PCSX_DRC ${PCSX_CORE}/new_dynarec)
set(PCSX_DEPS ${PCSX_ROOT}/deps)
set(PCSX_LRC ${PCSX_DEPS}/libretro-common)
set(LCHDR ${PCSX_DEPS}/libchdr)
set(LCHDR_LZMA ${LCHDR}/deps/lzma-26.02)
set(LCHDR_ZSTD ${LCHDR}/deps/zstd-1.5.7)

set(PCSX_SRC
  ${PCSX_CORE}/cdriso.c ${PCSX_CORE}/cdrom.c ${PCSX_CORE}/cdrom-async.c ${PCSX_CORE}/cheat.c
  ${PCSX_CORE}/database.c ${PCSX_CORE}/decode_xa.c ${PCSX_CORE}/mdec.c ${PCSX_CORE}/misc.c
  ${PCSX_CORE}/pad.c ${PCSX_CORE}/plugins.c ${PCSX_CORE}/ppf.c ${PCSX_CORE}/psxbios.c
  ${PCSX_CORE}/psxcommon.c ${PCSX_CORE}/psxcounters.c ${PCSX_CORE}/psxdma.c
  ${PCSX_CORE}/psxevents.c ${PCSX_CORE}/psxhw.c ${PCSX_CORE}/psxinterpreter.c
  ${PCSX_CORE}/psxmem.c ${PCSX_CORE}/r3000a.c ${PCSX_CORE}/sio.c ${PCSX_CORE}/spu.c
  ${PCSX_CORE}/gpu.c ${PCSX_CORE}/gte.c ${PCSX_CORE}/gte_nf.c ${PCSX_CORE}/gte_divider.c
  ${PCSX_SPU}/dma.c ${PCSX_SPU}/freeze.c ${PCSX_SPU}/registers.c ${PCSX_SPU}/spu.c
  ${PCSX_SPU}/out.c ${PCSX_SPU}/nullsnd.c
  ${PCSX_GPU}/gpu.c ${PCSX_GPU}/prim.c ${PCSX_GPU}/vout_pl.c ${PCSX_GPU}/gpu_async.c
  ${PCSX_ROOT}/plugins/cdrcimg/cdrcimg.c
  ${PCSX_FE}/main.c ${PCSX_FE}/plugin.c ${PCSX_FE}/cspace.c ${PCSX_FE}/libretro.c
  ${PCSX_FE}/pcsxr-threads.c
  ${LCHDR}/src/libchdr_bitstream.c ${LCHDR}/src/libchdr_cdrom.c ${LCHDR}/src/libchdr_chd.c
  ${LCHDR}/src/libchdr_codec_cdfl.c ${LCHDR}/src/libchdr_codec_cdlz.c
  ${LCHDR}/src/libchdr_codec_cdzl.c ${LCHDR}/src/libchdr_codec_cdzs.c
  ${LCHDR}/src/libchdr_codec_flac.c ${LCHDR}/src/libchdr_codec_huff.c
  ${LCHDR}/src/libchdr_codec_lzma.c ${LCHDR}/src/libchdr_codec_zlib.c
  ${LCHDR}/src/libchdr_codec_zstd.c ${LCHDR}/src/libchdr_flac.c ${LCHDR}/src/libchdr_huffman.c
  ${LCHDR_LZMA}/src/LzmaDec.c ${LCHDR_ZSTD}/zstddeclib.c
  ${PCSX_LRC}/compat/compat_posix_string.c ${PCSX_LRC}/compat/fopen_utf8.c
  ${PCSX_LRC}/compat/compat_strl.c ${PCSX_LRC}/encodings/encoding_utf.c
  ${PCSX_LRC}/file/file_path.c ${PCSX_LRC}/file/file_path_io.c ${PCSX_LRC}/file/retro_dirent.c
  ${PCSX_LRC}/streams/file_stream.c ${PCSX_LRC}/streams/file_stream_transforms.c
  ${PCSX_LRC}/string/stdstring.c ${PCSX_LRC}/string/rstrtod.c ${PCSX_LRC}/time/rtime.c
  ${PCSX_LRC}/vfs/vfs_implementation.c ${PCSX_LRC}/features/features_cpu.c
  ${PCSX_DRC}/emu_if.c
  ${PCSX_NEON}/psx_gpu_if.c
)
set(PCSX_DEFS
  HAVE_CHD CHDR_SYSTEM_ZLIB HAVE_LIBRETRO NO_FRONTEND ANDROID REARMED
  P_HAVE_MMAP=1 P_HAVE_PTHREAD=1 P_HAVE_POSIX_MEMALIGN=1 USE_LIBRETRO_VFS
  LIGHTREC_CUSTOM_MAP=0 LIGHTREC_ENABLE_THREADED_COMPILER=0
  LIGHTREC_ENABLE_DISASSEMBLER=0 LIGHTREC_NO_DEBUG=1
  USE_ASYNC_CDROM USE_ASYNC_GPU USE_ASYNC_SPU HAVE_RTHREADS
  NEON_BUILD TEXTURE_CACHE_4BPP TEXTURE_CACHE_8BPP GPU_NEON
)
set(PCSX_INC
  ${PCSX_ROOT}/include ${PCSX_DEPS}/crypto ${LCHDR}/include ${LCHDR_LZMA}/include
  ${LCHDR_ZSTD} ${PCSX_LRC}/include)

if(ANDROID_ABI STREQUAL "arm64-v8a" OR ANDROID_ABI STREQUAL "armeabi-v7a")
  list(APPEND PCSX_SRC ${PCSX_DRC}/new_dynarec.c ${PCSX_DRC}/pcsxmem.c)
  list(APPEND PCSX_DEFS NDRC_THREAD)
  if(ANDROID_ABI STREQUAL "arm64-v8a")
    list(APPEND PCSX_SRC ${PCSX_CORE}/gte_arm64.S ${PCSX_CORE}/gte_nf_arm64.S
         ${PCSX_DRC}/linkage_arm64.S ${LCHDR_LZMA}/Asm/arm64/LzmaDecOpt.S
         ${PCSX_NEON}/psx_gpu/psx_gpu_simd.c)
    list(APPEND PCSX_DEFS Z7_LZMA_DEC_OPT SIMD_BUILD)
  else()
    list(APPEND PCSX_SRC ${PCSX_CORE}/gte_arm.S ${PCSX_CORE}/gte_nf_arm.S
         ${PCSX_SPU}/arm_utils.S ${PCSX_DRC}/linkage_arm.S
         ${PCSX_NEON}/psx_gpu/psx_gpu_arm_neon.S
         ${PCSX_CORE}/gte_neon.S ${PCSX_CORE}/gte_nf_neon.S ${PCSX_FE}/cspace_neon.S)
    list(APPEND PCSX_DEFS HAVE_bgr555_to_rgb565 HAVE_bgr888_to_x)
  endif()
elseif(WIN32)
  # Windows: intérprete (lightrec necesita pthreads). Un PC va de sobra.
  list(APPEND PCSX_DEFS DRC_DISABLE)
  list(APPEND PCSX_SRC ${PCSX_NEON}/psx_gpu/psx_gpu_simd.c)
  list(APPEND PCSX_DEFS SIMD_BUILD)
else()
  # x86_64 (emulador): lightrec
  list(APPEND PCSX_SRC
    ${PCSX_DEPS}/lightrec/blockcache.c ${PCSX_DEPS}/lightrec/constprop.c
    ${PCSX_DEPS}/lightrec/disassembler.c ${PCSX_DEPS}/lightrec/emitter.c
    ${PCSX_DEPS}/lightrec/interpreter.c ${PCSX_DEPS}/lightrec/lightrec.c
    ${PCSX_DEPS}/lightrec/memmanager.c ${PCSX_DEPS}/lightrec/optimizer.c
    ${PCSX_DEPS}/lightrec/regcache.c ${PCSX_DEPS}/lightrec/recompiler.c
    ${PCSX_DEPS}/lightrec/reaper.c ${PCSX_DEPS}/lightrec/tlsf/tlsf.c
    ${PCSX_DEPS}/lightning/lib/jit_disasm.c ${PCSX_DEPS}/lightning/lib/jit_memory.c
    ${PCSX_DEPS}/lightning/lib/jit_names.c ${PCSX_DEPS}/lightning/lib/jit_note.c
    ${PCSX_DEPS}/lightning/lib/jit_print.c ${PCSX_DEPS}/lightning/lib/jit_size.c
    ${PCSX_DEPS}/lightning/lib/lightning.c
    ${PCSX_CORE}/lightrec/plugin.c
    ${PCSX_NEON}/psx_gpu/psx_gpu_simd.c)
  list(APPEND PCSX_DEFS LIGHTREC LIGHTREC_STATIC LIGHTREC_CODE_INV=0 SIMD_BUILD)
  list(APPEND PCSX_INC ${PCSX_DEPS}/lightning/include ${PCSX_DEPS}/lightrec
       ${PCSX_DEPS}/lightrec/tlsf ${PCSX_ROOT}/include/lightning ${PCSX_ROOT}/include/lightrec)
endif()

if(WIN32)
  # Como el Makefile oficial para Windows: mmap emulado (deps/mman), sin audio
  # asíncrono (usa semaphore.h de POSIX), sin pthreads ni código de Android.
  list(APPEND PCSX_SRC ${PCSX_DEPS}/mman/mman.c ${RS_WIN_COMPAT}/pcsx_win_map.c)
  list(APPEND PCSX_INC ${PCSX_CORE})
  list(REMOVE_ITEM PCSX_DEFS ANDROID P_HAVE_PTHREAD=1 P_HAVE_POSIX_MEMALIGN=1 USE_ASYNC_SPU)
  list(APPEND PCSX_DEFS __WIN32__ NO_DYLIB P_HAVE_PTHREAD=0 P_HAVE_POSIX_MEMALIGN=0)
  list(APPEND PCSX_INC ${PCSX_ROOT}/include/mman ${PCSX_DEPS}/mman ${RS_WIN_COMPAT})
  set_source_files_properties(${PCSX_DEPS}/lightning/lib/lightning.c
    PROPERTIES COMPILE_DEFINITIONS "mprotect=_mprotect")
endif()

add_library(pcsx_rearmed_libretro SHARED ${PCSX_SRC})
target_include_directories(pcsx_rearmed_libretro PRIVATE ${PCSX_INC})
target_compile_definitions(pcsx_rearmed_libretro PRIVATE ${PCSX_DEFS})
target_compile_options(pcsx_rearmed_libretro PRIVATE
  $<$<COMPILE_LANGUAGE:C>:-ffast-math -fwrapv -w>)
if(ANDROID_ABI STREQUAL "armeabi-v7a")
  target_compile_options(pcsx_rearmed_libretro PRIVATE -marm -mfpu=neon)
endif()
if(WIN32)
  # -fgnuc-version: el código elige sus ramas de GCC (las de MSVC están
  # incompletas). waitpkg/mwaitx: instrucciones que rthreads solo usa si la CPU
  # las tiene (lo comprueba con CPUID).
  target_compile_options(pcsx_rearmed_libretro PRIVATE -fgnuc-version=13.0
    $<$<COMPILE_LANGUAGE:C,CXX>:-include ${RS_WIN_COMPAT}/rs_posix_compat.h> -mwaitpkg -mmwaitx)
  # __builtin_cpu_supports necesita la biblioteca de soporte de Clang.
  execute_process(COMMAND ${CMAKE_C_COMPILER} --print-file-name=clang_rt.builtins-x86_64.lib
    OUTPUT_VARIABLE RS_CLANG_RT OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(NOT EXISTS "${RS_CLANG_RT}")
    execute_process(COMMAND ${CMAKE_C_COMPILER} --print-resource-dir
      OUTPUT_VARIABLE RS_CLANG_RES OUTPUT_STRIP_TRAILING_WHITESPACE)
    set(RS_CLANG_RT "${RS_CLANG_RES}/lib/windows/clang_rt.builtins-x86_64.lib")
  endif()
  target_link_libraries(pcsx_rearmed_libretro rs_zlib ws2_32 "${RS_CLANG_RT}")
else()
  target_link_libraries(pcsx_rearmed_libretro z log)
  target_link_options(pcsx_rearmed_libretro PRIVATE
    -Wl,--version-script=${PCSX_FE}/libretro-version-script
    -Wl,--script=${PCSX_FE}/libretro-extern.T
    -Wl,--gc-sections -Wl,-z,max-page-size=16384)
endif()
set_target_properties(pcsx_rearmed_libretro PROPERTIES PREFIX "lib")
