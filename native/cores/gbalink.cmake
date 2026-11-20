# ---------------------------------------------------------------------------
# GBA Link (RetroStation, MPL-2.0 por mGBA): cable link de GBA para cualquier
# juego en el multijugador por red -> libgbalink_libretro.so / .dll
# Ver native/gbalink/gbalink_core.cpp.
#
# Usa mGBA como biblioteca (su API de C, no libretro), compilada aparte con
# LIBMGBA_ONLY para no tocar el núcleo libretro de mGBA que ya usa la app.
# ---------------------------------------------------------------------------
include(ExternalProject)

set(GBALINK_MGBA_BIN ${CMAKE_BINARY_DIR}/mgba-static)
if(WIN32)
  set(GBALINK_MGBA_LIB ${GBALINK_MGBA_BIN}/mgba.lib)
else()
  set(GBALINK_MGBA_LIB ${GBALINK_MGBA_BIN}/libmgba.a)
endif()

set(GBALINK_MGBA_ARGS
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
  -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
  -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  -DLIBMGBA_ONLY=ON -DBUILD_STATIC=ON -DBUILD_SHARED=OFF -DDISABLE_DEPS=ON
  -DM_CORE_GBA=ON -DM_CORE_GB=OFF
  -DUSE_ZLIB=OFF -DUSE_PNG=OFF -DUSE_LIBZIP=OFF -DUSE_MINIZIP=OFF -DUSE_SQLITE3=OFF
  -DUSE_ELF=OFF -DUSE_LUA=OFF -DUSE_LZMA=OFF -DUSE_EDITLINE=OFF -DUSE_GDB_STUB=OFF
  -DUSE_DEBUGGERS=OFF -DUSE_FFMPEG=OFF -DUSE_EPOXY=OFF -DENABLE_SCRIPTING=OFF
  "-DCMAKE_C_FLAGS=-fwrapv")
if(ANDROID)
  list(APPEND GBALINK_MGBA_ARGS
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}
    -DANDROID_ABI=${ANDROID_ABI}
    -DANDROID_PLATFORM=${ANDROID_PLATFORM})
elseif(RS_IOS)
  list(APPEND GBALINK_MGBA_ARGS
    -DCMAKE_SYSTEM_NAME=iOS
    -DCMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES}
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}
    -DCMAKE_OSX_SYSROOT=${CMAKE_OSX_SYSROOT}
    # CMake 4 (Xcode reciente) rechaza el cmake_minimum_required(3.1) de mGBA.
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5)
endif()

ExternalProject_Add(gbalink_mgba
  SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/mgba
  BINARY_DIR ${GBALINK_MGBA_BIN}
  CMAKE_GENERATOR ${CMAKE_GENERATOR}
  CMAKE_ARGS ${GBALINK_MGBA_ARGS}
  BUILD_BYPRODUCTS ${GBALINK_MGBA_LIB}
  INSTALL_COMMAND ""
  # El código fuente es local: no hay descarga ni actualización.
  UPDATE_COMMAND ""
)

add_library(gbalink_libretro SHARED gbalink/gbalink_core.cpp)
add_dependencies(gbalink_libretro gbalink_mgba)
target_include_directories(gbalink_libretro PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/third_party/mgba/include
  ${CMAKE_CURRENT_SOURCE_DIR}/third_party/mgba/src
  ${GBALINK_MGBA_BIN}/include
  ${CMAKE_CURRENT_SOURCE_DIR}/third_party/mgba/src/platform/libretro)
target_compile_definitions(gbalink_libretro PRIVATE BUILD_STATIC)
target_link_libraries(gbalink_libretro ${GBALINK_MGBA_LIB})
set_target_properties(gbalink_libretro PROPERTIES PREFIX "lib" CXX_STANDARD 17)
if(ANDROID)
  target_link_libraries(gbalink_libretro m log)
elseif(WIN32)
  # La biblioteca de mGBA usa el runtime de C dinámico (el mismo que Flutter).
  set_target_properties(gbalink_libretro PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreadedDLL")
  target_link_libraries(gbalink_libretro ws2_32 shlwapi)
endif()
