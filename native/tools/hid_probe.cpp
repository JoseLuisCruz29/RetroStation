// Prueba del lector HID del Pro Controller (windows/runner/nintendo_hid.h):
//   hid_probe [segundos]
#include <cstdio>
#include <cstdlib>

#include "../../windows/runner/nintendo_hid.h"

int main(int argc, char** argv) {
  const int seconds = argc > 1 ? atoi(argv[1]) : 5;
  auto paths = NintendoHid::Enumerate();
  printf("Pro Controller encontrados: %zu\n", paths.size());
  if (paths.empty()) return 1;
  NintendoHid pad;
  if (!pad.Open(paths[0])) {
    printf("no se pudo abrir (error %lu)\n", GetLastError());
    return 1;
  }
  printf("informe de entrada %u bytes, salida %u bytes\n", pad.input_length(), pad.output_length());
  NintendoState s, last;
  last.buttons = 0xFFFFFFFF;
  for (int t = 0; t < seconds * 250; ++t) {
    if (!pad.Poll(s)) {
      printf("desconectado\n");
      return 1;
    }
    if (!(s == last)) {
      printf("t=%.2fs botones=0x%04x pov=%d lx=%.2f ly=%.2f\n", t / 250.0, s.buttons, s.pov, s.lx, s.ly);
      fflush(stdout);
      last = s;
    }
    if (t % 250 == 0) {
      printf("  [%ds] informes=%d ultimo=0x%02x\n", t / 250, pad.reports, pad.last_id & 0xff);
      fflush(stdout);
    }
    Sleep(4);
  }
  printf("total informes=%d\n", pad.reports);
  return 0;
}
