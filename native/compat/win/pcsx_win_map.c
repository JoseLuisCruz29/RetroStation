/* PCSX ReARMed en Windows: memoria de la PlayStation donde Windows la dé.
 *
 * El reparto por defecto (psxMapDefault) pide direcciones fijas (0x80000000,
 * 0x77000000...) y, si ya están ocupadas en el proceso (en la app de Flutter
 * casi siempre), el núcleo no arranca: "mapping main RAM failed". En Windows
 * se usa el intérprete, que no necesita direcciones fijas, así que basta con
 * memoria normal en cualquier sitio, como hace el propio núcleo en PS Vita.
 * Se instala al cargar la DLL, antes de que el núcleo reserve nada. */
#include <windows.h>

#include "psxmem_map.h"

static void* win_map(unsigned long addr, size_t size, enum psxMapTag tag, int* can_retry_addr) {
  (void)addr;
  (void)tag;
  *can_retry_addr = 0;
  void* p = VirtualAlloc(NULL, size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
  return p ? p : (void*)-1; /* MAP_FAILED */
}

static void win_unmap(void* ptr, size_t size, enum psxMapTag tag) {
  (void)size;
  (void)tag;
  if (ptr && ptr != (void*)-1) VirtualFree(ptr, 0, MEM_RELEASE);
}

__attribute__((constructor)) static void rs_install_win_map(void) {
  psxMapHook = win_map;
  psxUnmapHook = win_unmap;
}
