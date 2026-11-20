/* Funciones de POSIX que algunos núcleos usan y Windows llama de otra forma.
 * Se incluye a la fuerza (-include) al compilar esos núcleos en Windows. */
#pragma once
#ifdef _WIN32
#include <string.h>
#include <time.h>
#ifndef strcasecmp
#define strcasecmp _stricmp
#endif
#ifndef strncasecmp
#define strncasecmp _strnicmp
#endif
static inline struct tm* localtime_r(const time_t* t, struct tm* out) {
  return localtime_s(out, t) == 0 ? out : 0;
}
static inline struct tm* gmtime_r(const time_t* t, struct tm* out) {
  return gmtime_s(out, t) == 0 ? out : 0;
}
#endif
