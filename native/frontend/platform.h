// Diferencias entre sistemas que necesita el frontend: cargar el núcleo
// (dlopen en Android, LoadLibrary en Windows) y el id del hilo.
#pragma once

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <string>

namespace rs::platform {

inline void* lib_open(const char* path) {
  // Rutas UTF-8 (las carpetas del usuario pueden tener tildes).
  int n = MultiByteToWideChar(CP_UTF8, 0, path, -1, nullptr, 0);
  std::wstring w(n > 0 ? n : 0, L'\0');
  if (n > 0) MultiByteToWideChar(CP_UTF8, 0, path, -1, w.data(), n);
  // Busca las dependencias del núcleo junto a él, no en el directorio actual.
  return LoadLibraryExW(w.c_str(), nullptr, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
}
inline void* lib_sym(void* lib, const char* name) {
  return reinterpret_cast<void*>(GetProcAddress(static_cast<HMODULE>(lib), name));
}
inline void lib_close(void* lib) { FreeLibrary(static_cast<HMODULE>(lib)); }
inline const char* lib_error() {
  static char buf[64];
  snprintf(buf, sizeof(buf), "error de Windows %lu", GetLastError());
  return buf;
}

}  // namespace rs::platform

#else
#include <dlfcn.h>
#include <unistd.h>

namespace rs::platform {

inline void* lib_open(const char* path) { return dlopen(path, RTLD_NOW | RTLD_LOCAL); }
inline void* lib_sym(void* lib, const char* name) { return dlsym(lib, name); }
inline void lib_close(void* lib) { dlclose(lib); }
inline const char* lib_error() { return dlerror(); }

}  // namespace rs::platform
#endif
