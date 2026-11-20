# melonDS (GPL-3.0): núcleo libretro de Nintendo DS -> libmelonds_libretro.so
# Traducción de third_party/melonds/{jni/Android.mk,Makefile.common} (commit fab81072):
# renderizado por software (sin OpenGL), JIT en arm64-v8a y x86_64.
set(MDS_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/third_party/melonds)
set(MDS ${MDS_ROOT}/src)
set(MDS_CORE ${MDS}/libretro)
set(MDS_LRC ${MDS_CORE}/libretro-common)

set(MDS_SRC
  ${MDS}/xxhash/xxhash.c ${MDS}/tiny-AES-c/aes.c ${MDS}/fatfs/diskio.c ${MDS}/fatfs/ff.c
  ${MDS}/fatfs/ffsystem.c ${MDS}/fatfs/ffunicode.c ${MDS}/sha1/sha1.c
  ${MDS_LRC}/streams/memory_stream.c ${MDS_LRC}/compat/compat_strl.c
  ${MDS_LRC}/compat/fopen_utf8.c ${MDS_LRC}/compat/compat_posix_string.c
  ${MDS_LRC}/compat/compat_strcasestr.c ${MDS_LRC}/encodings/encoding_utf.c
  ${MDS_LRC}/file/file_path.c ${MDS_LRC}/streams/file_stream.c
  ${MDS_LRC}/streams/file_stream_transforms.c ${MDS_LRC}/string/stdstring.c
  ${MDS_LRC}/vfs/vfs_implementation.c
  ${MDS_LRC}/rthreads/rthreads.c ${MDS_LRC}/rthreads/rsemaphore.c
)
foreach(f NDS AREngine ARCodeFile ARM ARMInterpreter ARMInterpreter_ALU ARMInterpreter_Branch
          ARMInterpreter_LoadStore CP15 CRC32 DMA DSi DSi_AES DSi_Camera DSi_DSP DSi_I2C
          DSi_NAND DSi_NDMA DSi_NWifi DSi_SD DSi_SPI_TSC DSiCrypto GBACart GPU GPU2D GPU2D_Soft
          GPU3D GPU3D_Soft NDSCart NDSCart_SRAMManager RTC Savestate SPI SPU Wifi WifiAP
          frontend/Util_ROM)
  list(APPEND MDS_SRC ${MDS}/${f}.cpp)
endforeach()
foreach(f config input libretro platform screenlayout utils)
  list(APPEND MDS_SRC ${MDS_CORE}/${f}.cpp)
endforeach()
foreach(f ahbm apbp btdmp disassembler_c disassembler dma memory_interface mmio parser
          processor teakra_c teakra timer)
  list(APPEND MDS_SRC ${MDS}/teakra/src/${f}.cpp)
endforeach()

set(MDS_DEFS __LIBRETRO__ MELONDS_VERSION="0.9.3" HAVE_THREADS)
set(MDS_INC ${MDS_LRC}/include ${MDS_CORE} ${MDS} ${MDS}/teakra/include ${MDS}/teakra/src)

# En Windows, sin JIT: su enlace con el código generado falla con el ABI de
# MSVC, y el intérprete ya va a 60 FPS en un PC.
if(ANDROID_ABI STREQUAL "arm64-v8a" OR ANDROID_ABI STREQUAL "x86_64")
  list(APPEND MDS_SRC ${MDS}/ARMJIT.cpp ${MDS}/ARMJIT_Memory.cpp ${MDS}/ARM_InstrInfo.cpp
       ${MDS}/dolphin/CommonFuncs.cpp)
  list(APPEND MDS_DEFS JIT_ENABLED)
  if(ANDROID_ABI STREQUAL "arm64-v8a")
    list(APPEND MDS_SRC ${MDS}/dolphin/Arm64Emitter.cpp ${MDS}/dolphin/MathUtil.cpp
         ${MDS}/ARMJIT_A64/ARMJIT_Compiler.cpp ${MDS}/ARMJIT_A64/ARMJIT_ALU.cpp
         ${MDS}/ARMJIT_A64/ARMJIT_LoadStore.cpp ${MDS}/ARMJIT_A64/ARMJIT_Branch.cpp
         ${MDS}/ARMJIT_A64/ARMJIT_Linkage.S)
    list(APPEND MDS_INC ${MDS}/ARMJIT_A64)
    list(APPEND MDS_DEFS ARCHITECTURE_ARM64)
  else()
    list(APPEND MDS_SRC ${MDS}/dolphin/x64ABI.cpp ${MDS}/dolphin/x64CPUDetect.cpp
         ${MDS}/dolphin/x64Emitter.cpp ${MDS}/ARMJIT_x64/ARMJIT_ALU.cpp
         ${MDS}/ARMJIT_x64/ARMJIT_Branch.cpp ${MDS}/ARMJIT_x64/ARMJIT_Compiler.cpp
         ${MDS}/ARMJIT_x64/ARMJIT_LoadStore.cpp ${MDS}/ARMJIT_x64/ARMJIT_Linkage.S)
    list(APPEND MDS_INC ${MDS}/ARMJIT_x64)
    list(APPEND MDS_DEFS ARCHITECTURE_X64)
  endif()
endif()

add_library(melonds_libretro SHARED ${MDS_SRC})
target_include_directories(melonds_libretro PRIVATE ${MDS_INC})
target_compile_definitions(melonds_libretro PRIVATE ${MDS_DEFS})
target_compile_options(melonds_libretro PRIVATE -w -fwrapv -O3
  $<$<COMPILE_LANGUAGE:CXX>:-fexceptions>)
# Sin JIT (32 bits) todo el tiempo se va en el intérprete: en armeabi-v7a se
# compila en modo ARM (no Thumb, más rápido en bucles calientes) y se ajusta
# para los Cortex-A53/A55 de los móviles de gama media. -mtune no limita en
# qué procesadores funciona.
if(ANDROID_ABI STREQUAL "armeabi-v7a")
  target_compile_options(melonds_libretro PRIVATE -marm -mtune=cortex-a55)
endif()
set_target_properties(melonds_libretro PROPERTIES PREFIX "lib" CXX_STANDARD 17)
if(WIN32)
  # NOMINMAX: sin las macros min/max de windows.h (rompen std::max).
  # _MSVC_VER: así lo escribe x64CPUDetect.cpp para usar el __cpuid de MSVC.
  target_compile_definitions(melonds_libretro PRIVATE __WIN32__ NOMINMAX _MSVC_VER=1
    _XCR_XFEATURE_ENABLED_MASK=0)
  target_include_directories(melonds_libretro PRIVATE ${RS_WIN_COMPAT})
  target_compile_options(melonds_libretro PRIVATE
    $<$<COMPILE_LANGUAGE:C,CXX>:-include ${RS_WIN_COMPAT}/rs_posix_compat.h>)
  target_link_libraries(melonds_libretro ws2_32)
elseif(APPLE)
  # iPhone: sin JIT ni --version-script (el enlazador de Apple no lo admite).
else()
  target_link_options(melonds_libretro PRIVATE -Wl,--version-script=${MDS_CORE}/link.T)
  target_link_libraries(melonds_libretro log)
endif()
