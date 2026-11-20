/* sys/time.h mínimo para Windows: struct timeval y gettimeofday. */
#pragma once
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h> /* struct timeval */
#include <stdint.h>
static inline int gettimeofday(struct timeval* tv, void* tz) {
  FILETIME ft;
  uint64_t t;
  (void)tz;
  GetSystemTimeAsFileTime(&ft);
  t = (((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime) - 116444736000000000ULL;
  tv->tv_sec = (long)(t / 10000000ULL);
  tv->tv_usec = (long)((t % 10000000ULL) / 10);
  return 0;
}
