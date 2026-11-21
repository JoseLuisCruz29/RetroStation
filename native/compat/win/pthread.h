/* pthread mínimo para Windows (Clang con el ABI de MSVC no trae pthreads).
 *
 * Lo justo para Mupen64Plus-Next: un hilo (pthread_create/join) y mutex de
 * los estados de guardado. Hilos de Windows y SRWLOCK por debajo. */
#ifndef RS_COMPAT_PTHREAD_H
#define RS_COMPAT_PTHREAD_H

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <process.h>
#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef HANDLE pthread_t;
typedef void pthread_attr_t;
typedef SRWLOCK pthread_mutex_t;
typedef void pthread_mutexattr_t;
#define PTHREAD_MUTEX_INITIALIZER SRWLOCK_INIT

struct rs_pthread_start {
  void* (*fn)(void*);
  void* arg;
};

static unsigned __stdcall rs_pthread_trampoline(void* p) {
  struct rs_pthread_start s = *(struct rs_pthread_start*)p;
  free(p);
  s.fn(s.arg);
  return 0;
}

static __inline int pthread_create(pthread_t* t, const pthread_attr_t* attr, void* (*fn)(void*), void* arg) {
  (void)attr;
  struct rs_pthread_start* s = (struct rs_pthread_start*)malloc(sizeof(*s));
  if (!s) return -1;
  s->fn = fn;
  s->arg = arg;
  uintptr_t h = _beginthreadex(NULL, 0, rs_pthread_trampoline, s, 0, NULL);
  if (!h) {
    free(s);
    return -1;
  }
  *t = (HANDLE)h;
  return 0;
}

static __inline int pthread_join(pthread_t t, void** ret) {
  if (ret) *ret = NULL;
  WaitForSingleObject(t, INFINITE);
  CloseHandle(t);
  return 0;
}

static __inline int pthread_mutex_init(pthread_mutex_t* m, const pthread_mutexattr_t* a) {
  (void)a;
  InitializeSRWLock(m);
  return 0;
}
static __inline int pthread_mutex_destroy(pthread_mutex_t* m) {
  (void)m;
  return 0;
}
static __inline int pthread_mutex_lock(pthread_mutex_t* m) {
  AcquireSRWLockExclusive(m);
  return 0;
}
static __inline int pthread_mutex_unlock(pthread_mutex_t* m) {
  ReleaseSRWLockExclusive(m);
  return 0;
}

#ifdef __cplusplus
}
#endif

#endif
