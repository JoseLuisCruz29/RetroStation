// Prueba del cable link de GBA: dos GBA (mGBA) conectadas por el cable dentro
// del mismo proceso, ejecutadas por turnos en un solo hilo y siempre en el
// mismo orden. Así el resultado no depende de la velocidad de cada hilo: dos
// dispositivos con las mismas pulsaciones calcularían exactamente lo mismo
// (requisito para llevarlo después al multijugador por red).
//
//   gba_link_test ventana  <rom1> [rom2]      ventana con las dos pantallas
//   gba_link_test medir    <rom1> [rom2] N    N fotogramas sin límite de velocidad
//   gba_link_test repetir  <rom1> [rom2] N    dos ejecuciones con las mismas
//                                             pulsaciones: deben acabar iguales
//
// En la ventana: Tab cambia de GBA (1 o 2). Flechas = cruceta, X = A, Z = B,
// A/S = L/R, Intro = Start, Retroceso = Select. F1 = 2 jugadores a la vez
// (GBA 2 con I/J/K/L, N = A, B = B, U/O = L/R, 1 = Start, 2 = Select).

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#endif

#include <cstdarg>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <string>
#include <thread>
#include <vector>

extern "C" {
#include <mgba/core/core.h>
#include <mgba/core/log.h>
#include <mgba/core/timing.h>
#include <mgba/gba/core.h>
#include <mgba/internal/gba/gba.h>
#include <mgba/internal/gba/io.h>
#include <mgba/internal/gba/sio.h>
#include <mgba/internal/gba/sio/lockstep.h>
}

namespace {

constexpr int kW = 240;
constexpr int kH = 160;

struct Player {
  mCore* core = nullptr;
  GBASIOLockstepNode node{};
  std::vector<color_t> video = std::vector<color_t>(kW * kH);
  int awake = 1;  // > 0 corriendo, <= 0 esperando al otro
  unsigned waitMask = 0;
  int32_t cyclesPosted = 0;
  uint32_t keys = 0;
  GBA* gba() const { return static_cast<GBA*>(core->board); }
  // Posición en tiempo emulado: fotograma y línea de pantalla (228 por fotograma).
  uint64_t time() const {
    return static_cast<uint64_t>(gba()->video.frameCounter) * 228 + gba()->memory.io[REG_VCOUNT >> 1];
  }
};

struct Link {
  GBASIOLockstep lockstep{};
  Player p[2];
};

Link g;

// Mismo protocolo que el multijugador de la versión de PC de mGBA
// (MultiplayerController.cpp), pero "esperar" solo marca al jugador como
// parado: el bucle de turnos deja de ejecutarlo hasta que el otro lo despierta.
void setup_lockstep() {
  GBASIOLockstepInit(&g.lockstep);
  mLockstep& l = g.lockstep.d;
  l.context = &g;
  l.signal = [](mLockstep*, unsigned mask) {
    Player& m = g.p[0];
    m.waitMask &= ~mask;
    if (!m.waitMask && m.awake < 1) {
      m.awake = 1;
      return true;
    }
    return false;
  };
  l.wait = [](mLockstep*, unsigned mask) {
    Player& m = g.p[0];
    m.waitMask |= mask;
    if (m.awake > 0) {
      m.awake = 0;
      return true;
    }
    return false;
  };
  l.addCycles = [](mLockstep*, int id, int32_t cycles) {
    if (id == 0) {
      Player& s = g.p[1];
      if (s.gba()->sio.mode > SIO_MULTI) return;  // modo normal: va por su cuenta
      s.cyclesPosted += cycles;
      if (s.awake < 1) s.node.nextEvent += s.cyclesPosted;
      s.awake = 1;
    } else {
      g.p[id].cyclesPosted += cycles;
    }
  };
  l.useCycles = [](mLockstep*, int id, int32_t cycles) {
    Player& pl = g.p[id];
    pl.cyclesPosted -= cycles;
    if (pl.cyclesPosted <= 0) pl.awake = 0;
    return pl.cyclesPosted;
  };
  l.unusedCycles = [](mLockstep*, int id) { return g.p[id].cyclesPosted; };
  l.unload = [](mLockstep* lock, int id) {
    if (id) {
      g.p[id].cyclesPosted = 0;
      Player& m = g.p[0];
      m.waitMask &= ~(1u << id);
      if (!m.waitMask && m.awake < 1) m.awake = 1;
    } else {
      Player& s = g.p[1];
      s.cyclesPosted += reinterpret_cast<GBASIOLockstep*>(lock)->players[0]->eventDiff;
      if (s.awake < 1) s.node.nextEvent += s.cyclesPosted;
      s.awake = 1;
    }
  };
}

bool load_player(Player& pl, const char* rom) {
  pl.core = GBACoreCreate();
  if (!pl.core || !pl.core->init(pl.core)) return false;
  mCoreInitConfig(pl.core, nullptr);
  pl.core->setVideoBuffer(pl.core, pl.video.data(), kW);
  if (!mCoreLoadFile(pl.core, rom)) {
    fprintf(stderr, "No se pudo cargar %s\n", rom);
    return false;
  }
  pl.core->reset(pl.core);
  if (getenv("GBA_NO_LINK")) {  // diagnóstico: sin cable
    pl.awake = 1;
    return true;
  }
  GBASIOLockstepNodeCreate(&pl.node);
  GBASIOLockstepAttachNode(&g.lockstep, &pl.node);
  GBASIOSetDriver(&pl.gba()->sio, &pl.node.d, SIO_MULTI);
  GBASIOSetDriver(&pl.gba()->sio, &pl.node.d, SIO_NORMAL_32);
  return true;
}

// Un fotograma de la GBA 1. La GBA 2 la sigue en tiempo emulado; mientras
// una espera a la otra (transferencia del cable), solo corre la otra.
void run_frame() {
  Player& a = g.p[0];
  Player& b = g.p[1];
  a.core->setKeys(a.core, a.keys);
  b.core->setKeys(b.core, b.keys);
  const uint32_t start = a.core->frameCounter(a.core);
  int stuck = 0;
  while (a.core->frameCounter(a.core) == start) {
    bool ran = false;
    if (a.awake > 0) {
      a.core->runLoop(a.core);
      ran = true;
    }
    int guard = 0;
    while (b.awake > 0 && (b.time() < a.time() || a.awake <= 0) && guard++ < 100000) {
      b.core->runLoop(b.core);
      ran = true;
    }
    if (!ran) {
      // Ninguna puede avanzar (no debería pasar): se despiertan las dos.
      a.awake = b.awake = 1;
      if (++stuck == 1) fprintf(stderr, "aviso: las dos GBA esperaban a la vez\n");
    }
  }
}

uint32_t state_crc(Player& pl) {
  std::vector<uint8_t> s(pl.core->stateSize(pl.core));
  pl.core->saveState(pl.core, s.data());
  uint32_t h = 2166136261u;  // FNV-1a
  for (uint8_t c : s) h = (h ^ c) * 16777619u;
  return h;
}

void scripted_keys(std::mt19937& rng, int frame) {
  // Cambia los botones cada ~6 fotogramas; Start de vez en cuando.
  if (frame % 6 == 0) {
    g.p[0].keys = rng() & 0x3FF;
    g.p[1].keys = rng() & 0x3FF;
  }
}

int g_cur_frame = 0;
bool g_log_sio = false;
void quiet_log(mLogger*, int category, enum mLogLevel level, const char* fmt, va_list args) {
  if (g_log_sio && strstr(mLogCategoryName(category), "Serial")) {
    fprintf(stderr, "f%d ", g_cur_frame);
    vfprintf(stderr, fmt, args);
    fputc(10, stderr);
    return;
  }
  if (level & (mLOG_ERROR | mLOG_FATAL)) {
    vfprintf(stderr, fmt, args);
    fputc('\n', stderr);
  }
}
mLogger g_logger{quiet_log, nullptr};

void report(const char* tag) {
  for (int i = 0; i < 2; ++i) {
    Player& pl = g.p[i];
    fprintf(stderr, "[%s] GBA%d fotograma=%u t=%llu modo=%d despierta=%d ciclos=%d evento=%d\n", tag, i + 1,
            pl.core->frameCounter(pl.core), (unsigned long long)pl.time(), pl.gba()->sio.mode, pl.awake, pl.cyclesPosted, pl.node.nextEvent);
  }
}

int start(const char* rom1, const char* rom2) {
  mLogSetDefaultLogger(&g_logger);
  setup_lockstep();
  if (!load_player(g.p[0], rom1) || !load_player(g.p[1], rom2)) return 1;
  return 0;
}

#ifdef _WIN32
// --- Ventana --------------------------------------------------------------------
int g_active = 0;
bool g_both = false;
std::vector<uint32_t> g_screen(kW * 2 * kH);

uint32_t key_bit(WPARAM k, bool second) {
  if (!second) {
    switch (k) {
      case 'X': return 1 << 0;        // A
      case 'Z': return 1 << 1;        // B
      case VK_BACK: return 1 << 2;    // Select
      case VK_RETURN: return 1 << 3;  // Start
      case VK_RIGHT: return 1 << 4;
      case VK_LEFT: return 1 << 5;
      case VK_UP: return 1 << 6;
      case VK_DOWN: return 1 << 7;
      case 'S': return 1 << 8;        // R
      case 'A': return 1 << 9;        // L
    }
  } else {
    switch (k) {
      case 'N': return 1 << 0;
      case 'B': return 1 << 1;
      case '2': return 1 << 2;
      case '1': return 1 << 3;
      case 'L': return 1 << 4;
      case 'J': return 1 << 5;
      case 'I': return 1 << 6;
      case 'K': return 1 << 7;
      case 'O': return 1 << 8;
      case 'U': return 1 << 9;
    }
  }
  return 0;
}

LRESULT CALLBACK wndproc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
  switch (msg) {
    case WM_KEYDOWN:
    case WM_KEYUP: {
      bool down = msg == WM_KEYDOWN;
      if (down && wp == VK_TAB) {
        g_active ^= 1;
        g.p[0].keys = g.p[1].keys = 0;
        return 0;
      }
      if (down && wp == VK_F1) {
        g_both = !g_both;
        g.p[0].keys = g.p[1].keys = 0;
        return 0;
      }
      if (g_both) {
        for (int s = 0; s < 2; ++s) {
          uint32_t bit = key_bit(wp, s == 1);
          if (bit) g.p[s].keys = down ? (g.p[s].keys | bit) : (g.p[s].keys & ~bit);
        }
      } else {
        uint32_t bit = key_bit(wp, false);
        Player& pl = g.p[g_active];
        if (bit) pl.keys = down ? (pl.keys | bit) : (pl.keys & ~bit);
      }
      return 0;
    }
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC dc = BeginPaint(h, &ps);
      RECT r;
      GetClientRect(h, &r);
      BITMAPINFO bi{};
      bi.bmiHeader.biSize = sizeof(bi.bmiHeader);
      bi.bmiHeader.biWidth = kW * 2;
      bi.bmiHeader.biHeight = -kH;
      bi.bmiHeader.biPlanes = 1;
      bi.bmiHeader.biBitCount = 32;
      SetStretchBltMode(dc, COLORONCOLOR);
      StretchDIBits(dc, 0, 0, r.right, r.bottom, 0, 0, kW * 2, kH, g_screen.data(), &bi, DIB_RGB_COLORS, SRCCOPY);
      EndPaint(h, &ps);
      return 0;
    }
    case WM_DESTROY:
      PostQuitMessage(0);
      return 0;
  }
  return DefWindowProcW(h, msg, wp, lp);
}

void compose() {
  for (int s = 0; s < 2; ++s) {
    for (int y = 0; y < kH; ++y) {
      for (int x = 0; x < kW; ++x) {
        uint32_t c = g.p[s].video[y * kW + x];  // R en el byte bajo
        g_screen[y * kW * 2 + s * kW + x] = ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF);
      }
    }
  }
}

// Órdenes desde un archivo (para pruebas automáticas sin depender del foco):
//   p <1|2> <A|B|SELECT|START|RIGHT|LEFT|UP|DOWN|R|L> <fotogramas>
//   shot <archivo.bmp>
std::string g_ctl_path;
int g_hold[2][10] = {};
void save_bmp(const std::string& path) {
  FILE* f = fopen(path.c_str(), "wb");
  if (!f) return;
  const int w = kW * 2, h = kH;
  BITMAPFILEHEADER fh{};
  BITMAPINFOHEADER ih{};
  fh.bfType = 0x4D42;
  fh.bfOffBits = sizeof(fh) + sizeof(ih);
  fh.bfSize = fh.bfOffBits + w * h * 4;
  ih.biSize = sizeof(ih);
  ih.biWidth = w;
  ih.biHeight = -h;
  ih.biPlanes = 1;
  ih.biBitCount = 32;
  fwrite(&fh, sizeof(fh), 1, f);
  fwrite(&ih, sizeof(ih), 1, f);
  fwrite(g_screen.data(), 4, w * h, f);
  fclose(f);
}
void poll_control() {
  static const char* names[10] = {"A", "B", "SELECT", "START", "RIGHT", "LEFT", "UP", "DOWN", "R", "L"};
  if (!g_ctl_path.empty()) {
    FILE* f = fopen(g_ctl_path.c_str(), "r");
    if (f) {
      char line[512];
      while (fgets(line, sizeof(line), f)) {
        char cmd[16] = {}, arg[400] = {};
        int player = 0, frames = 0;
        if (sscanf(line, "p %d %15s %d", &player, cmd, &frames) == 3 && player >= 1 && player <= 2) {
          for (int k = 0; k < 10; ++k) {
            if (_stricmp(cmd, names[k]) == 0) g_hold[player - 1][k] = frames;
          }
        } else if (sscanf(line, "shot %399s", arg) == 1) {
          compose();
          save_bmp(arg);
        }
      }
      fclose(f);
      remove(g_ctl_path.c_str());
    }
  }
  for (int s = 0; s < 2; ++s) {
    uint32_t scripted = 0;
    for (int k = 0; k < 10; ++k) {
      if (g_hold[s][k] > 0) {
        scripted |= 1u << k;
        --g_hold[s][k];
      }
    }
    static uint32_t last[2] = {0, 0};
    // Solo toca las teclas que controla el guion (el teclado sigue funcionando).
    g.p[s].keys = (g.p[s].keys & ~last[s]) | scripted;
    last[s] = scripted;
  }
}

int window_mode() {
  WNDCLASSW wc{};
  wc.lpfnWndProc = wndproc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = L"GbaLinkTest";
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClassW(&wc);
  RECT r{0, 0, kW * 2 * 3, kH * 3};
  AdjustWindowRect(&r, WS_OVERLAPPEDWINDOW, FALSE);
  HWND h = CreateWindowW(wc.lpszClassName, L"Cable link GBA", WS_OVERLAPPEDWINDOW | WS_VISIBLE, 80, 80,
                         r.right - r.left, r.bottom - r.top, nullptr, nullptr, wc.hInstance, nullptr);
  using Clock = std::chrono::steady_clock;
  auto next = Clock::now();
  auto window_start = next;
  int frames = 0;
  for (;;) {
    MSG msg;
    while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
      if (msg.message == WM_QUIT) return 0;
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
    }
    poll_control();
    run_frame();
    compose();
    InvalidateRect(h, nullptr, FALSE);
    ++frames;
    auto now = Clock::now();
    if (now - window_start >= std::chrono::seconds(1)) {
      wchar_t title[160];
      swprintf(title, 160, L"Cable link GBA - %d FPS - controlas: %ls  (Tab cambia, F1 dos jugadores)", frames,
               g_both ? L"las dos" : (g_active ? L"GBA 2" : L"GBA 1"));
      SetWindowTextW(h, title);
      frames = 0;
      window_start = now;
    }
    next += std::chrono::microseconds(16743);  // 59,73 Hz
    if (now - next > std::chrono::milliseconds(100)) next = now;
    std::this_thread::sleep_until(next);
  }
}
#endif

}  // namespace

int main(int argc, char** argv) {
  if (argc < 3) {
    fprintf(stderr, "uso: %s ventana|medir|repetir rom1 [rom2] [fotogramas]\n", argv[0]);
    return 2;
  }
  std::string mode = argv[1];
  const char* rom1 = argv[2];
  const char* rom2 = argc > 3 && strchr(argv[3], '.') ? argv[3] : rom1;
  int n = atoi(argv[argc - 1]);
  if (n <= 0) n = 3600;

  if (mode == "ventana") {
#ifdef _WIN32
    if (start(rom1, rom2)) return 1;
    if (const char* ctl = getenv("GBA_LINK_CTL")) g_ctl_path = ctl;
    return window_mode();
#else
    return 2;
#endif
  }
  if (mode == "medir") {
    if (start(rom1, rom2)) return 1;
    std::mt19937 rng(7);
    auto t0 = std::chrono::steady_clock::now();
    for (int f = 0; f < n; ++f) {
      scripted_keys(rng, f);
      run_frame();
      if (f < 12 || f % 600 == 0) report("medir");
    }
    double s = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    printf("%d fotogramas de las dos GBA en %.2f s = %.1f FPS (hacen falta 60)\n", n, s, n / s);
    return 0;
  }
  if (mode == "guion") {
    // GBA_SCRIPT="700:START,900:A,..." (las dos GBA a la vez); registra el cable.
    if (start(rom1, rom2)) return 1;
    g_log_sio = getenv("GBA_LOG_SIO") != nullptr;
    std::vector<std::pair<int, uint32_t>> steps;
    static const char* names[10] = {"A", "B", "SELECT", "START", "RIGHT", "LEFT", "UP", "DOWN", "R", "L"};
    std::string script = getenv("GBA_SCRIPT") ? getenv("GBA_SCRIPT") : "";
    size_t pos = 0;
    while (pos < script.size()) {
      size_t end = script.find(',', pos);
      std::string item = script.substr(pos, end == std::string::npos ? std::string::npos : end - pos);
      size_t colon = item.find(':');
      if (colon != std::string::npos) {
        int at = atoi(item.c_str());
        std::string key = item.substr(colon + 1);
        for (int k = 0; k < 10; ++k) if (key == names[k]) steps.push_back({at, 1u << k});
      }
      if (end == std::string::npos) break;
      pos = end + 1;
    }
    for (int f = 0; f < n; ++f) {
      g_cur_frame = f;
      uint32_t k = 0;
      for (auto& s : steps) if (f >= s.first && f < s.first + 6) k |= s.second;
      g.p[0].keys = g.p[1].keys = k;
      run_frame();
      if (g_log_sio && f % 100 == 0) {
        for (int i = 0; i < 2; ++i) {
          GBASIO& sio = g.p[i].gba()->sio;
          fprintf(stderr, "f%d GBA%d modo=%d rcnt=%04x siocnt=%04x\n", f, i + 1, sio.mode, sio.rcnt, sio.siocnt);
        }
      }
    }
#ifdef _WIN32
    if (getenv("GBA_SHOT")) {
      compose();
      save_bmp(getenv("GBA_SHOT"));
    }
#endif
    printf("huellas: GBA1=%08x GBA2=%08x\n", state_crc(g.p[0]), state_crc(g.p[1]));
    return 0;
  }
  if (mode == "pantalla") {
    // Diagnóstico: huella de la imagen cada segundo; Start en los fotogramas 300-305.
    if (start(rom1, rom2)) return 1;
    for (int f = 0; f < n; ++f) {
      const int at = getenv("GBA_START_AT") ? atoi(getenv("GBA_START_AT")) : 300;
      uint32_t k = (f >= at && f < at + 6) ? (1u << 3) : 0;
      g.p[0].keys = g.p[1].keys = k;
      run_frame();
      if (f % 60 == 0) {
        uint32_t h = 2166136261u;
        for (color_t c : g.p[0].video) h = (h ^ c) * 16777619u;
#ifdef _WIN32
        if (getenv("GBA_SHOT")) {
          compose();
          save_bmp(getenv("GBA_SHOT"));
        }
#endif
        printf("f=%d imagen=%08x pc=%08x frame=%u\n", f, h, g.p[0].gba()->cpu->gprs[15], g.p[0].core->frameCounter(g.p[0].core));
      }
    }
    return 0;
  }
  if (mode == "repetir") {
    // Dos ejecuciones completas (proceso nuevo cada vez, con el mismo guion).
    if (start(rom1, rom2)) return 1;
    std::mt19937 rng(7);
    for (int f = 0; f < n; ++f) {
      scripted_keys(rng, f);
      run_frame();
    }
    printf("huellas: GBA1=%08x GBA2=%08x fotograma GBA2=%u\n", state_crc(g.p[0]), state_crc(g.p[1]),
           g.p[1].core->frameCounter(g.p[1].core));
    return 0;
  }
  return 2;
}
