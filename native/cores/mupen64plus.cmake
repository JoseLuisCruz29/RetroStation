# ---------------------------------------------------------------------------
# Mupen64Plus-Next (GPL-2.0): Nintendo 64 -> libmupen64plus_next_libretro
# Traducción de third_party/mupen64plus/{Makefile,Makefile.common,libretro/jni/Android.mk}.
#
# Gráficos con GLideN64 por GPU: OpenGL en Windows y OpenGL ES 3 en Android e
# iPhone (el frontend da el contexto: hw_render*.cpp). Audio y RSP en HLE.
# CPU: intérprete con caché por ahora (el recompilador necesita generar
# cabeceras de ensamblador a partir de un objeto compilado; ver más abajo).
# ---------------------------------------------------------------------------
set(M64 ${CMAKE_CURRENT_SOURCE_DIR}/third_party/mupen64plus)
set(M64_CORE ${M64}/mupen64plus-core)
include(${CMAKE_CURRENT_LIST_DIR}/mupen64plus_sources.cmake)

set(M64_LIBPNG ${M64}/custom/dependencies/libpng)
set(M64_ZLIB ${M64}/custom/dependencies/libzlib)
set(M64_MINIZIP ${M64_CORE}/subprojects/minizip)

set(M64_SRC
  ${M64_SRC_CORE} ${M64_SRC_GLIDE} ${M64_SRC_LIBRETRO} ${M64_SRC_RSP}
  ${M64_CORE}/subprojects/md5/md5.c
  ${M64_MINIZIP}/zip.c ${M64_MINIZIP}/unzip.c ${M64_MINIZIP}/ioapi.c
  ${M64}/libretro-common/libco/libco.c
  ${M64}/libretro-common/glsym/rglgen.c
  ${M64}/GLideN64/src/CRC_OPT.cpp
  ${M64}/GLideN64/src/3DMath.cpp)
foreach(f png pngerror pngget pngmem pngpread pngread pngrio pngrtran pngrutil pngset
          pngtrans pngwio pngwrite pngwtran pngwutil)
  list(APPEND M64_SRC ${M64_LIBPNG}/${f}.c)
endforeach()
foreach(f adler32 compress crc32 deflate gzclose gzlib gzread gzwrite infback inffast
          inflate inftrees trees uncompr zutil)
  list(APPEND M64_SRC ${M64_ZLIB}/${f}.c)
endforeach()

set(M64_INC
  ${M64}/custom ${M64}/custom/mupen64plus-core ${M64}/custom/android/include
  ${M64}/custom/GLideN64 ${M64}/GLideN64/src ${M64}/GLideN64/src/osal
  ${M64_CORE}/src ${M64_CORE}/src/api
  ${M64}/custom/mupen64plus-core/plugin/audio_libretro
  ${M64}/libretro-common/include ${M64}/libretro ${M64}/GLideN64/src/inc
  ${M64}/GLideN64/src/GLideNHQ/inc ${M64_CORE}/subprojects/md5
  ${M64_LIBPNG} ${M64_MINIZIP} ${M64}/xxHash ${M64_ZLIB})

set(M64_DEFS
  __STDC_CONSTANT_MACROS __STDC_LIMIT_MACROS __LIBRETRO__ USE_FILE32API
  M64P_PLUGIN_API M64P_CORE_PROTOTYPES _ENDUSER_RELEASE SINC_LOWER_QUALITY
  TXFILTER_LIB __VEC4_OPT MUPENPLUSAPI NDEBUG)

if(WIN32)
  # OpenGL de escritorio (perfil de compatibilidad, como el Makefile para "win").
  list(APPEND M64_SRC ${M64}/GLideN64/src/osal/osal_files_win32.c
       ${M64}/libretro-common/glsym/glsym_gl.c)
  # libco con "fibers" de Windows ata el núcleo al hilo que cargó el juego, y
  # el motor lo ejecuta en otro hilo (se colgaba al primer fotograma). La
  # versión amd64 cambia de pila por su cuenta y vale para cualquier hilo,
  # como en Android e iPhone.
  list(REMOVE_ITEM M64_SRC ${M64}/libretro-common/libco/libco.c)
  list(APPEND M64_SRC ${M64}/libretro-common/libco/amd64.c)
  list(APPEND M64_DEFS OS_WINDOWS UNICODE HAVE_OPENGL NOMINMAX PATH_MAX=4096 NO_ASM)
elseif(ANDROID)
  list(APPEND M64_SRC ${M64}/GLideN64/src/osal/osal_files_unix.c
       ${M64}/libretro-common/glsym/glsym_es3.c
       ${M64}/GLideN64/src/Graphics/OpenGLContext/GraphicBuffer/GraphicBufferWrapper.cpp
       ${M64}/GLideN64/src/Graphics/OpenGLContext/GraphicBuffer/PublicApi/android_hardware_buffer_compat.cpp)
  list(APPEND M64_DEFS OS_ANDROID ANDROID EGL_EGLEXT_PROTOTYPES HAVE_POSIX_MEMALIGN=1 NO_ASM
       EGL HAVE_OPENGLES HAVE_OPENGLES3 GLES3)
elseif(RS_IOS)
  list(APPEND M64_SRC ${M64}/GLideN64/src/osal/osal_files_unix.c
       ${M64}/libretro-common/glsym/glsym_es3.c ${M64}/custom/ios/compat.c)
  list(APPEND M64_DEFS IOS OS_IOS HAVE_POSIX_MEMALIGN NO_ASM GLES_SILENCE_DEPRECATION
       HAVE_OPENGLES HAVE_OPENGLES3 GLES3)
else()
  list(APPEND M64_SRC ${M64}/GLideN64/src/osal/osal_files_unix.c
       ${M64}/libretro-common/glsym/glsym_gl.c)
  list(APPEND M64_DEFS OS_LINUX HAVE_OPENGL CORE NO_ASM)
endif()

# El núcleo guarda el hilo de libretro (retro_thread) solo al cargar el juego y
# vuelve a él al acabar cada fotograma. El motor carga en un hilo y ejecuta en
# otro, así que se usa una copia de libretro.c que lo actualiza antes de cada
# cambio al hilo del juego (sin esto se cuelga en el primer fotograma).
file(READ ${M64}/libretro/libretro.c M64_LIBRETRO_C)
string(REPLACE "co_switch(game_thread);" "{ retro_thread = co_active(); co_switch(game_thread); }"
  M64_LIBRETRO_C "${M64_LIBRETRO_C}")
file(WRITE ${CMAKE_BINARY_DIR}/mupen64plus/libretro.c "${M64_LIBRETRO_C}")
list(REMOVE_ITEM M64_SRC ${M64}/libretro/libretro.c)
list(APPEND M64_SRC ${CMAKE_BINARY_DIR}/mupen64plus/libretro.c)

add_library(mupen64plus_next_libretro SHARED ${M64_SRC})
target_include_directories(mupen64plus_next_libretro PRIVATE ${M64_INC})
target_compile_definitions(mupen64plus_next_libretro PRIVATE ${M64_DEFS})
target_compile_options(mupen64plus_next_libretro PRIVATE -w -O2 -fsigned-char -ffast-math
  -fno-strict-aliasing -fcommon
  $<$<COMPILE_LANGUAGE:C>:-std=gnu11>)
set_target_properties(mupen64plus_next_libretro PROPERTIES PREFIX "lib" CXX_STANDARD 17)
if(APPLE)
  # libpng busca <fp.h> (Mac clásico) si TARGET_OS_MAC está definido; con
  # <math.h> ya incluido usa el estándar.
  target_compile_options(mupen64plus_next_libretro PRIVATE "SHELL:-include math.h")
  # Por lo mismo, zlib sustituye fdopen() por NULL salvo que ya sea una macro.
  target_compile_definitions(mupen64plus_next_libretro PRIVATE fdopen=fdopen)
endif()
if(WIN32)
  target_include_directories(mupen64plus_next_libretro PRIVATE ${RS_WIN_COMPAT})
  target_link_libraries(mupen64plus_next_libretro opengl32)
  # GLideN64 (C++) declara estas variables de C sin extern "C": con el ABI de
  # MSVC su nombre va decorado. El enlazador las resuelve con el nombre de C.
  target_link_options(mupen64plus_next_libretro PRIVATE
    "LINKER:/alternatename:?rdram_size@@3_KA=rdram_size"
    "LINKER:/alternatename:?log_cb@@3P6AXW4retro_log_level@@PEBDZZEA=log_cb")
elseif(ANDROID)
  target_link_libraries(mupen64plus_next_libretro GLESv3 EGL log android)
elseif(APPLE)
  target_link_libraries(mupen64plus_next_libretro "-framework OpenGLES" "-framework Foundation")
endif()
rs_version_script(mupen64plus_next_libretro ${M64}/libretro/link.T)
