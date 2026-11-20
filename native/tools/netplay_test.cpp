// Prueba del multijugador sin la app: ejecuta el frontend en un proceso de
// línea de comandos (adb shell). Se lanzan dos procesos, anfitrión e invitado,
// que se conectan por 127.0.0.1 (o por la Wi-Fi entre dos teléfonos) y pulsan
// botones al azar, cada uno con su semilla. Si los dos juegos se desincronizan,
// la comprobación de huellas lo detecta y el resultado muestra resyncs > 0.
//
//   rs_netplay_test host <núcleo.so> <rom> <fotogramas> [modo] [opción=valor...]
//   rs_netplay_test join <núcleo.so> <rom> <fotogramas> <ip> [modo] [opción=valor...]
#include <unistd.h>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <string>
#include <sys/stat.h>
#include <thread>

#include "rs_frontend.h"

int main(int argc, char** argv) {
  if (argc < 5) {
    fprintf(stderr, "uso: %s host|join núcleo rom fotogramas [ip] [modo] [clave=valor...]\n", argv[0]);
    return 2;
  }
  const bool host = strcmp(argv[1], "host") == 0;
  const char* core = argv[2];
  const char* rom = argv[3];
  const int frames = atoi(argv[4]);
  int arg = 5;
  std::string ip = "127.0.0.1";
  if (!host && argc > arg) ip = argv[arg++];
  int mode = 0;
  if (argc > arg && strchr(argv[arg], '=') == nullptr) mode = atoi(argv[arg++]);
  for (; arg < argc; ++arg) {
    std::string kv = argv[arg];
    auto eq = kv.find('=');
    if (eq != std::string::npos) rs_set_core_option(kv.substr(0, eq).c_str(), kv.substr(eq + 1).c_str());
  }

  std::string base = std::string("/data/local/tmp/rsnet/") + (host ? "host" : "guest");
  mkdir("/data/local/tmp/rsnet", 0755);
  mkdir(base.c_str(), 0755);
  std::string sram = base + "/game.srm";
  if (rs_load(core, rom, base.c_str(), base.c_str(), sram.c_str()) != RS_OK) {
    fprintf(stderr, "rs_load: %s\n", rs_last_error());
    return 1;
  }
  // RS_TOKEN / RS_KEY: para jugar contra la app (token de la sala y SHA-1 del juego).
  const char* token = getenv("RS_TOKEN") ? getenv("RS_TOKEN") : "prueba";
  const char* key = getenv("RS_KEY") ? getenv("RS_KEY") : "juego";
  // El modo 2 (GBA Link, sin estado inicial) se inicia antes de arrancar el hilo.
  if (mode == 2 && rs_netplay_start(host ? 1 : 0, mode, ip.c_str(), 55435, 3, token, key) != RS_OK) {
    fprintf(stderr, "rs_netplay_start: %s\n", rs_last_error());
    return 1;
  }
  rs_start();
  if (mode != 2 && rs_netplay_start(host ? 1 : 0, mode, ip.c_str(), 55435, 3, token, key) != RS_OK) {
    fprintf(stderr, "rs_netplay_start: %s\n", rs_last_error());
    return 1;
  }

  std::mt19937 rng(host ? 1234 : 98765);
  auto t0 = std::chrono::steady_clock::now();
  auto last_print = t0;
  uint32_t mask = 0;
  rs_netplay_info info{};
  int exit_code = 0;
  for (;;) {
    // Cada ~100 ms cambian los botones pulsados (incluye Start de vez en cuando).
    if (rng() % 6 == 0) mask = rng() & 0x0FFF;
    rs_set_buttons(mask);
    std::this_thread::sleep_for(std::chrono::milliseconds(16));
    rs_netplay_status(&info);
    auto now = std::chrono::steady_clock::now();
    if (now - last_print > std::chrono::seconds(2)) {
      last_print = now;
      printf("[%s] fase=%d fotograma=%d fps=%.1f rtt=%dms resyncs=%d espera=%d\n", host ? "host" : "join",
             info.phase, info.frame, rs_get_fps(), info.rtt_ms, info.resyncs, info.stalled);
      fflush(stdout);
    }
    if (info.phase == 4 || info.phase == 5) {
      printf("[%s] fin: %s\n", host ? "host" : "join", rs_netplay_message());
      exit_code = info.frame >= frames ? 0 : 3;
      break;
    }
    if (info.frame >= frames) break;
    if (now - t0 > std::chrono::minutes(10)) {
      exit_code = 4;
      break;
    }
  }
  printf("[%s] RESULTADO fotogramas=%d resyncs=%d\n", host ? "host" : "join", info.frame, info.resyncs);
  fflush(stdout);
  // Deja que el otro llegue también al final antes de cortar la conexión.
  std::this_thread::sleep_for(std::chrono::seconds(2));
  rs_unload();
  return exit_code;
}
