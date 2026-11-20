/* PCSX ReARMed en iPhone: memoria de la PlayStation donde iOS la dé.
 *
 * Igual que en Windows (native/compat/win/pcsx_win_map.c): el reparto por
 * defecto pide direcciones fijas, que iOS no garantiza. Con el intérprete
 * (sin JIT, que iOS no permite) basta memoria normal en cualquier sitio.
 * Se instala al cargar la biblioteca, antes de que el núcleo reserve nada. */
#include <stddef.h>
#include <sys/mman.h>

#include "psxmem_map.h"

static void* ios_map(unsigned long addr, size_t size, enum psxMapTag tag, int* can_retry_addr) {
  (void)addr;
  (void)tag;
  *can_retry_addr = 0;
  return mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
}

static void ios_unmap(void* ptr, size_t size, enum psxMapTag tag) {
  (void)tag;
  if (ptr && ptr != MAP_FAILED) munmap(ptr, size);
}

__attribute__((constructor)) static void rs_install_ios_map(void) {
  psxMapHook = ios_map;
  psxUnmapHook = ios_unmap;
}
