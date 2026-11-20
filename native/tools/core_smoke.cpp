// Prueba rápida de un núcleo con el motor de RetroStation (sin la interfaz):
//   core_smoke <núcleo> <rom> [segundos]
// Carga el juego, lo ejecuta y muestra los FPS. Sirve para ver en Windows (o
// en el teléfono con adb) si un núcleo arranca antes de probarlo en la app.
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>

#include "rs_frontend.h"

#ifdef _WIN32
#include <windows.h>
#include <shellapi.h>
#include <vector>
// Como la app: las rutas llegan al motor en UTF-8 (no en la página de códigos).
static std::vector<std::string> utf8_args() {
  int n = 0;
  wchar_t** w = CommandLineToArgvW(GetCommandLineW(), &n);
  std::vector<std::string> out;
  for (int i = 0; i < n; ++i) {
    int len = WideCharToMultiByte(CP_UTF8, 0, w[i], -1, nullptr, 0, nullptr, nullptr);
    std::string s(len > 0 ? len - 1 : 0, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w[i], -1, s.data(), len, nullptr, nullptr);
    out.push_back(s);
  }
  LocalFree(w);
  return out;
}
#endif

int main(int argc, char** argv) {
  if (argc < 3) {
    fprintf(stderr, "uso: %s núcleo rom [segundos]\n", argv[0]);
    return 2;
  }
  const int seconds = argc > 3 ? atoi(argv[3]) : 5;
#ifdef _WIN32
  static std::vector<std::string> args = utf8_args();
  static std::vector<char*> ptrs;
  for (auto& a : args) ptrs.push_back(a.data());
  argv = ptrs.data();
#endif
  std::string dir = getenv("RS_SAVES") ? getenv("RS_SAVES") : ".";
  const char* sys_dir = getenv("RS_SYSTEM") ? getenv("RS_SYSTEM") : dir.c_str();
  std::string sram = dir + "/smoke.srm";
  // RS_OPT="clave=valor,clave=valor": opciones del núcleo.
  if (const char* opts = getenv("RS_OPT")) {
    std::string all = opts;
    size_t pos = 0;
    while (pos < all.size()) {
      size_t end = all.find(',', pos);
      std::string kv = all.substr(pos, end == std::string::npos ? std::string::npos : end - pos);
      size_t eq = kv.find('=');
      if (eq != std::string::npos) rs_set_core_option(kv.substr(0, eq).c_str(), kv.substr(eq + 1).c_str());
      if (end == std::string::npos) break;
      pos = end + 1;
    }
  }
  printf("cargando %s\n", argv[2]);
  fflush(stdout);
  if (rs_load(argv[1], argv[2], sys_dir, dir.c_str(), sram.c_str()) != RS_OK) {
    printf("rs_load: %s\n", rs_last_error());
    return 1;
  }
  rs_av_info av{};
  rs_get_av_info(&av);
  printf("cargado: %dx%d a %.2f fps\n", av.base_width, av.base_height, av.fps);
  fflush(stdout);
  rs_start();
  for (int i = 0; i < seconds; ++i) {
    std::this_thread::sleep_for(std::chrono::seconds(1));
    printf("t=%ds fps=%.1f fotogramas=%llu\n", i + 1, rs_get_fps(),
           static_cast<unsigned long long>(rs_get_frame_count()));
    fflush(stdout);
  }
  // RS_SHOT=archivo.bmp: guarda el último fotograma (para ver que no sale negro).
  if (const char* shot = getenv("RS_SHOT")) {
    int32_t w = 0, h = 0;
    int32_t need = rs_copy_frame(nullptr, 0, &w, &h);
    if (need > 0) {
      std::string px(static_cast<size_t>(need), '\0');
      rs_copy_frame(reinterpret_cast<uint8_t*>(px.data()), need, &w, &h);
      if (FILE* f = fopen(shot, "wb")) {
        const uint32_t row = static_cast<uint32_t>(w) * 4, size = 54 + row * h;
        uint8_t hdr[54] = {'B', 'M'};
        auto put = [&](int at, uint32_t v) {
          for (int i = 0; i < 4; ++i) hdr[at + i] = (v >> (8 * i)) & 0xFF;
        };
        put(2, size);
        put(10, 54);
        put(14, 40);
        put(18, w);
        put(22, static_cast<uint32_t>(-h));  // de arriba abajo
        hdr[26] = 1;
        hdr[28] = 32;
        fwrite(hdr, 1, 54, f);
        long lit = 0;
        for (size_t i = 0; i < px.size(); i += 4) {
          std::swap(px[i], px[i + 2]);  // RGBA -> BGRA
          if ((uint8_t)px[i] + (uint8_t)px[i + 1] + (uint8_t)px[i + 2] > 30) ++lit;
        }
        fwrite(px.data(), 1, px.size(), f);
        fclose(f);
        printf("captura %dx%d en %s (%ld%% de pixeles con color)\n", w, h, shot, lit * 100 / (w * h));
      }
    }
  }
  rs_unload();
  printf("ok\n");
  return 0;
}
