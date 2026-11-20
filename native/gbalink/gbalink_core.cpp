// "GBA Link": núcleo libretro de RetroStation para el cable link de GBA en el
// multijugador por red, con cualquier juego que use el cable.
//
// Cada dispositivo emula LAS DOS GBA (mGBA) unidas por el cable, por turnos en
// un solo hilo y siempre en el mismo orden, así que con las mismas pulsaciones
// los dos dispositivos calculan exactamente lo mismo (comprobado en PC x64 y
// ARM de 32 bits). Por la red solo viajan los botones (netplay lockstep del
// frontend: puerto 0 = jugador 1, puerto 1 = jugador 2).
//
// Cada dispositivo muestra y hace sonar SU GBA ("gbalink_local" = 1 o 2) y
// devuelve como partida guardada solo la suya. Las dos partidas llegan antes de
// empezar: la propia y la del otro jugador (opciones gbalink_save1/gbalink_save2).
//
// El cable sigue el mismo protocolo que el multijugador de la versión de PC de
// mGBA (src/platform/qt/MultiplayerController.cpp); ver tools/gba_link_test.cpp.

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

extern "C" {
#include <mgba-util/vfs.h>
#include <mgba/core/blip_buf.h>
#include <mgba/core/core.h>
#include <mgba/core/log.h>
#include <mgba/gba/core.h>
#include <mgba/internal/gba/gba.h>
#include <mgba/internal/gba/io.h>
#include <mgba/internal/gba/savedata.h>
#include <mgba/internal/gba/sio.h>
#include <mgba/internal/gba/sio/lockstep.h>
}

#include "libretro.h"

namespace {

constexpr int kW = 240;
constexpr int kH = 160;
constexpr int kSampleRate = 32768;
constexpr size_t kSaveSize = 0x20000;  // SIZE_CART_FLASH1M: la mayor partida de GBA

retro_environment_t env_cb;
retro_video_refresh_t video_cb;
retro_audio_sample_batch_t audio_batch_cb;
retro_input_poll_t input_poll_cb;
retro_input_state_t input_state_cb;

struct Player {
  mCore* core = nullptr;
  GBASIOLockstepNode node{};
  std::vector<color_t> video = std::vector<color_t>(kW * kH);
  std::vector<uint8_t> save = std::vector<uint8_t>(kSaveSize, 0xFF);
  int awake = 1;  // > 0 corriendo; <= 0 esperando al otro
  unsigned waitMask = 0;
  int32_t cyclesPosted = 0;
  GBA* gba() const { return static_cast<GBA*>(core->board); }
  // Tiempo emulado: fotograma y línea de pantalla (228 por fotograma).
  uint64_t time() const {
    return static_cast<uint64_t>(gba()->video.frameCounter) * 228 + gba()->memory.io[REG_VCOUNT >> 1];
  }
};

struct Link {
  GBASIOLockstep lockstep{};
  Player p[2];
  int local = 0;  // GBA que se ve y se oye en este dispositivo
  bool loaded = false;
};

Link g;
std::vector<uint32_t> g_frame(kW * kH);
std::vector<int16_t> g_audio;

void quiet_log(mLogger*, int, enum mLogLevel, const char*, va_list) {}
mLogger g_logger{quiet_log, nullptr};

const char* option(const char* key) {
  retro_variable var{key, nullptr};
  if (env_cb && env_cb(RETRO_ENVIRONMENT_GET_VARIABLE, &var) && var.value) return var.value;
  return nullptr;
}

void read_file(const char* path, std::vector<uint8_t>& out) {
  if (!path || !*path) return;
  FILE* f = fopen(path, "rb");
  if (!f) return;
  size_t n = fread(out.data(), 1, out.size(), f);
  (void)n;
  fclose(f);
}

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
      if (s.gba()->sio.mode > SIO_MULTI) return;  // sin cable activo: va por su cuenta
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

bool load_player(Player& pl, const char* rom, const char* save_path) {
  pl.core = GBACoreCreate();
  if (!pl.core || !pl.core->init(pl.core)) return false;
  mCoreInitConfig(pl.core, nullptr);
  pl.core->setVideoBuffer(pl.core, pl.video.data(), kW);
  pl.core->setAudioBufferSize(pl.core, 2048);
  blip_set_rates(pl.core->getAudioChannel(pl.core, 0), pl.core->frequency(pl.core), kSampleRate);
  blip_set_rates(pl.core->getAudioChannel(pl.core, 1), pl.core->frequency(pl.core), kSampleRate);
  if (!mCoreLoadFile(pl.core, rom)) return false;
  // Partida guardada en memoria (como el libretro de mGBA): 128 KB, el
  // frontend escribe y lee la del jugador local a través de SAVE_RAM.
  read_file(save_path, pl.save);
  VFile* vf = VFileFromMemory(pl.save.data(), kSaveSize);
  if (!pl.core->loadSave(pl.core, vf)) vf->close(vf);
  pl.core->reset(pl.core);
  // La GBA del otro jugador no se ve en este dispositivo: no se dibuja (ahorra
  // casi un tercio del trabajo). Solo afecta a la imagen, no a la emulación,
  // y no entra en los estados, así que los dos dispositivos siguen iguales.
  if (&pl != &g.p[g.local]) pl.gba()->video.frameskip = 1 << 30;
  GBASIOLockstepNodeCreate(&pl.node);
  GBASIOLockstepAttachNode(&g.lockstep, &pl.node);
  GBASIOSetDriver(&pl.gba()->sio, &pl.node.d, SIO_MULTI);
  GBASIOSetDriver(&pl.gba()->sio, &pl.node.d, SIO_NORMAL_32);
  return true;
}

void unload_all() {
  for (auto& pl : g.p) {
    if (!pl.core) continue;
    GBASIOSetDriver(&pl.gba()->sio, nullptr, SIO_MULTI);
    GBASIOSetDriver(&pl.gba()->sio, nullptr, SIO_NORMAL_32);
    GBASIOLockstepDetachNode(&g.lockstep, &pl.node);
    pl.core->deinit(pl.core);
    pl.core = nullptr;
    pl.awake = 1;
    pl.waitMask = 0;
    pl.cyclesPosted = 0;
  }
  g.loaded = false;
}

// Un fotograma de la GBA 1; la GBA 2 la sigue en tiempo emulado. Mientras una
// espera a la otra (transferencia del cable) solo corre la otra.
void run_frame() {
  Player& a = g.p[0];
  Player& b = g.p[1];
  const uint32_t start = a.core->frameCounter(a.core);
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
    if (!ran) a.awake = b.awake = 1;  // no debería pasar: se despiertan las dos
  }
}

uint32_t gba_keys(unsigned port) {
  // Bits de GBA: A B Select Start Derecha Izquierda Arriba Abajo R L.
  static const unsigned map[10] = {RETRO_DEVICE_ID_JOYPAD_A,     RETRO_DEVICE_ID_JOYPAD_B,
                                   RETRO_DEVICE_ID_JOYPAD_SELECT, RETRO_DEVICE_ID_JOYPAD_START,
                                   RETRO_DEVICE_ID_JOYPAD_RIGHT,  RETRO_DEVICE_ID_JOYPAD_LEFT,
                                   RETRO_DEVICE_ID_JOYPAD_UP,     RETRO_DEVICE_ID_JOYPAD_DOWN,
                                   RETRO_DEVICE_ID_JOYPAD_R,      RETRO_DEVICE_ID_JOYPAD_L};
  uint32_t keys = 0;
  for (int k = 0; k < 10; ++k) {
    if (input_state_cb(port, RETRO_DEVICE_JOYPAD, 0, map[k])) keys |= 1u << k;
  }
  return keys;
}

}  // namespace

extern "C" {

RETRO_API void retro_set_environment(retro_environment_t cb) {
  env_cb = cb;
  static const retro_variable vars[] = {
      {"gbalink_local", "GBA de este dispositivo; 1|2"},
      {nullptr, nullptr},
  };
  cb(RETRO_ENVIRONMENT_SET_VARIABLES, const_cast<retro_variable*>(vars));
}
RETRO_API void retro_set_video_refresh(retro_video_refresh_t cb) { video_cb = cb; }
RETRO_API void retro_set_audio_sample(retro_audio_sample_t) {}
RETRO_API void retro_set_audio_sample_batch(retro_audio_sample_batch_t cb) { audio_batch_cb = cb; }
RETRO_API void retro_set_input_poll(retro_input_poll_t cb) { input_poll_cb = cb; }
RETRO_API void retro_set_input_state(retro_input_state_t cb) { input_state_cb = cb; }

RETRO_API void retro_init(void) { mLogSetDefaultLogger(&g_logger); }
RETRO_API void retro_deinit(void) { unload_all(); }
RETRO_API unsigned retro_api_version(void) { return RETRO_API_VERSION; }

RETRO_API void retro_get_system_info(retro_system_info* info) {
  std::memset(info, 0, sizeof(*info));
  info->library_name = "RetroStation GBA Link";
  info->library_version = "1.0 (mGBA 0.10.5)";
  info->valid_extensions = "gba";
  info->need_fullpath = true;
}

RETRO_API void retro_get_system_av_info(retro_system_av_info* info) {
  std::memset(info, 0, sizeof(*info));
  info->geometry.base_width = kW;
  info->geometry.base_height = kH;
  info->geometry.max_width = kW;
  info->geometry.max_height = kH;
  info->geometry.aspect_ratio = 3.0f / 2.0f;
  info->timing.fps = 16777216.0 / 280896.0;  // 59,7275 Hz
  info->timing.sample_rate = kSampleRate;
}

RETRO_API void retro_set_controller_port_device(unsigned, unsigned) {}
RETRO_API void retro_reset(void) {}

RETRO_API bool retro_load_game(const retro_game_info* game) {
  if (!game || !game->path) return false;
  retro_pixel_format fmt = RETRO_PIXEL_FORMAT_XRGB8888;
  env_cb(RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, &fmt);
  const char* local = option("gbalink_local");
  g.local = local && local[0] == '2' ? 1 : 0;
  std::string save1 = option("gbalink_save1") ? option("gbalink_save1") : "";
  std::string save2 = option("gbalink_save2") ? option("gbalink_save2") : "";
  setup_lockstep();
  if (!load_player(g.p[0], game->path, save1.c_str()) || !load_player(g.p[1], game->path, save2.c_str())) {
    unload_all();
    return false;
  }
  g.loaded = true;
  return true;
}

RETRO_API bool retro_load_game_special(unsigned, const retro_game_info*, size_t) { return false; }
RETRO_API void retro_unload_game(void) { unload_all(); }
RETRO_API unsigned retro_get_region(void) { return RETRO_REGION_NTSC; }

RETRO_API void retro_run(void) {
  if (!g.loaded) return;
  input_poll_cb();
  g.p[0].core->setKeys(g.p[0].core, gba_keys(0));
  g.p[1].core->setKeys(g.p[1].core, gba_keys(1));
  run_frame();

  // Diagnóstico (pruebas): huella de las dos GBA cada 600 fotogramas, para
  // comprobar que dos dispositivos calculan lo mismo.
  static const bool hash_log = getenv("GBALINK_HASH") != nullptr;
  if (hash_log) {
    uint32_t frame = g.p[0].core->frameCounter(g.p[0].core);
    if (frame % 600 == 0) {
      uint32_t h[2];
      for (int i = 0; i < 2; ++i) {
        std::vector<uint8_t> s(g.p[i].core->stateSize(g.p[i].core));
        g.p[i].core->saveState(g.p[i].core, s.data());
        h[i] = 2166136261u;
        for (uint8_t c : s) h[i] = (h[i] ^ c) * 16777619u;
      }
      fprintf(stderr, "[gbalink] fotograma %u huellas %08x %08x\n", frame, h[0], h[1]);
    }
  }

  // Imagen de la GBA local (mGBA: R en el byte bajo; libretro XRGB8888).
  const auto& v = g.p[g.local].video;
  for (size_t i = 0; i < g_frame.size(); ++i) {
    uint32_t c = v[i];
    g_frame[i] = ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF);
  }
  video_cb(g_frame.data(), kW, kH, kW * sizeof(uint32_t));

  // Sonido de la GBA local; el de la otra se descarta.
  for (int i = 0; i < 2; ++i) {
    blip_t* left = g.p[i].core->getAudioChannel(g.p[i].core, 0);
    blip_t* right = g.p[i].core->getAudioChannel(g.p[i].core, 1);
    int avail = blip_samples_avail(left);
    if (avail <= 0) continue;
    if (i != g.local) {
      blip_clear(left);
      blip_clear(right);
      continue;
    }
    g_audio.resize(static_cast<size_t>(avail) * 2);
    int produced = blip_read_samples(left, g_audio.data(), avail, true);
    blip_read_samples(right, g_audio.data() + 1, avail, true);
    if (produced > 0 && audio_batch_cb) audio_batch_cb(g_audio.data(), static_cast<size_t>(produced));
  }
}

// Sin estados: las dos GBA empiezan a la vez desde el encendido en los dos
// dispositivos (con las mismas partidas), así que no hace falta enviar ninguno.
RETRO_API size_t retro_serialize_size(void) { return 0; }
RETRO_API bool retro_serialize(void*, size_t) { return false; }
RETRO_API bool retro_unserialize(const void*, size_t) { return false; }
RETRO_API void retro_cheat_reset(void) {}
RETRO_API void retro_cheat_set(unsigned, bool, const char*) {}

RETRO_API void* retro_get_memory_data(unsigned id) {
  if (id != RETRO_MEMORY_SAVE_RAM || !g.loaded) return nullptr;
  return g.p[g.local].save.data();
}

RETRO_API size_t retro_get_memory_size(unsigned id) {
  if (id != RETRO_MEMORY_SAVE_RAM || !g.loaded) return 0;
  GBA* gba = g.p[g.local].gba();
  // Igual que el libretro de mGBA, para que el archivo .srm sirva en los dos.
  if (gba->memory.savedata.type == SAVEDATA_AUTODETECT) return kSaveSize;
  return GBASavedataSize(&gba->memory.savedata);
}

}  // extern "C"
