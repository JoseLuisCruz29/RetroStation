// Frontend libretro de RetroStation.
//
// - Carga un núcleo libretro con dlopen (en Android viene empaquetado en el APK).
// - Ejecuta retro_run() en un hilo propio a la frecuencia original del sistema.
// - Convierte cada fotograma a RGBA8888 y lo publica en un ANativeWindow que
//   Flutter muestra como textura (sin copiar píxeles a Dart).
// - Guarda la SRAM de forma atómica (archivo temporal + rename) al pausar,
//   al descargar y periódicamente si ha cambiado.

#include "rs_frontend.h"


#include <algorithm>
#include <atomic>
#if defined(__APPLE__)
#include <pthread.h>
#endif
#include <chrono>
#include <condition_variable>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <deque>
#include <functional>
#include <future>
#include <fstream>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#include "audio_output.h"
#include "hw_render.h"
#include "libretro.h"
#include "net_socket.h"
#include "netplay.h"
#include "platform.h"

#ifdef __ANDROID__
#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <jni.h>
#define RS_LOG(prio, ...) __android_log_print(prio, "RetroStation", __VA_ARGS__)
#define RS_INFO ANDROID_LOG_INFO
#define RS_WARN ANDROID_LOG_WARN
#define RS_ERROR ANDROID_LOG_ERROR
#else
#define RS_LOG(prio, ...) (fprintf(stderr, __VA_ARGS__), fputc('\n', stderr))
#define RS_INFO 0
#define RS_WARN 1
#define RS_ERROR 2
#endif

namespace {

using Clock = std::chrono::steady_clock;

struct CoreApi {
  void* handle = nullptr;
  void (*set_environment)(retro_environment_t) = nullptr;
  void (*set_video_refresh)(retro_video_refresh_t) = nullptr;
  void (*set_audio_sample)(retro_audio_sample_t) = nullptr;
  void (*set_audio_sample_batch)(retro_audio_sample_batch_t) = nullptr;
  void (*set_input_poll)(retro_input_poll_t) = nullptr;
  void (*set_input_state)(retro_input_state_t) = nullptr;
  void (*init)(void) = nullptr;
  void (*deinit)(void) = nullptr;
  void (*get_system_info)(retro_system_info*) = nullptr;
  void (*get_system_av_info)(retro_system_av_info*) = nullptr;
  void (*reset)(void) = nullptr;
  void (*run)(void) = nullptr;
  bool (*load_game)(const retro_game_info*) = nullptr;
  void (*unload_game)(void) = nullptr;
  void* (*get_memory_data)(unsigned) = nullptr;
  size_t (*get_memory_size)(unsigned) = nullptr;
};

struct Frontend {
  CoreApi core;
  bool loaded = false;
  std::string system_dir;
  std::string save_dir;
  std::string sram_path;
  std::vector<uint8_t> rom;
  std::vector<uint8_t> sram_snapshot;  // última SRAM escrita en disco
  retro_pixel_format pixel_format = RETRO_PIXEL_FORMAT_0RGB1555;
  retro_system_av_info av{};

  std::mutex core_mutex;  // serializa todas las llamadas al núcleo
  std::thread thread;
  std::atomic<bool> running{false};
  std::atomic<bool> paused{false};
  std::mutex pause_mutex;
  std::condition_variable pause_cv;

  std::atomic<uint32_t> buttons{0};
  // Pulsaciones nuevas retenidas hasta que el núcleo ejecute un fotograma
  // completo: un toque más corto que un fotograma (16,7 ms) no se pierde.
  std::atomic<uint32_t> latched{0};

  // Pantalla táctil (Nintendo DS): coordenadas libretro [-0x7FFF, 0x7FFF]
  // sobre la imagen completa que entrega el núcleo.
  std::atomic<int32_t> pointer_x{0};
  std::atomic<int32_t> pointer_y{0};
  std::atomic<bool> pointer_pressed{false};
  // Joysticks analógicos (PSP): [stick][eje], de -0x7FFF a 0x7FFF.
  std::atomic<int16_t> analog[2][2] = {};
  std::atomic<double> fps{0.0};
  std::atomic<uint64_t> frame_count{0};

  // Multijugador lockstep: entradas de los dos jugadores para el fotograma
  // que se está ejecutando (solo las usa el hilo de emulación).
  bool net_frame = false;
  rs::net::PadInput net_input[2];
  rs::net::Hooks net_hooks;

  rs::AudioOutput audio;
  std::atomic<float> speed{1.0f};

  // Último fotograma en RGBA (miniaturas de save states).
  std::mutex frame_mutex;
  std::vector<uint32_t> last_frame;
  unsigned last_w = 0;
  unsigned last_h = 0;

  // Rebobinado: instantáneas periódicas en memoria (requiere core_mutex).
  std::atomic<bool> rewind_enabled{false};
  std::atomic<bool> rewinding{false};
  std::deque<std::vector<uint8_t>> rewind_states;
  size_t rewind_capacity = 0;
  uint32_t rewind_interval = 10;  // fotogramas entre instantáneas

  // Funciones opcionales de save state.
  size_t (*serialize_size)(void) = nullptr;
  bool (*serialize)(void*, size_t) = nullptr;
  bool (*unserialize)(const void*, size_t) = nullptr;

  // Presentación en un hilo propio: ANativeWindow_lock() se bloquea hasta que
  // la pantalla libera un búfer (al ritmo del refresco). Si lo hiciera el hilo
  // de emulación, un fotograma que tarda algo más de 16 ms esperaría al
  // siguiente refresco y la velocidad caería de golpe a 30 FPS.
  std::thread present_thread;
  std::mutex present_mutex;
  std::condition_variable present_cv;
  bool present_pending = false;
  bool present_stop = false;

  // Tareas que deben ejecutarse en el hilo de emulación entre fotogramas
  // (save states de núcleos con GPU: ver run_on_emulation_thread).
  std::mutex task_mutex;
  std::deque<std::function<void()>> tasks;

  std::mutex window_mutex;
#ifdef __ANDROID__
  ANativeWindow* window = nullptr;
  int32_t window_w = 0;
  int32_t window_h = 0;
#endif

  // Opciones del núcleo elegidas por el usuario (clave libretro -> valor).
  std::mutex options_mutex;
  std::unordered_map<std::string, std::string> options;
  // Valores por defecto que declara el propio núcleo (SET_VARIABLES).
  std::unordered_map<std::string, std::string> option_defaults;
  std::atomic<bool> options_dirty{false};

  std::string last_error;
  std::string core_id;  // "nombre versión" (debe coincidir en el multijugador)
  std::string net_message;
};

Frontend g;

// Escritorio: aviso de fotograma nuevo (lo registra la ventana de Flutter).
std::atomic<void (*)(void*)> g_frame_cb{nullptr};
std::atomic<void*> g_frame_cb_user{nullptr};

void set_error(const char* fmt, ...) {
  char buf[512];
  va_list args;
  va_start(args, fmt);
  vsnprintf(buf, sizeof(buf), fmt, args);
  va_end(args);
  g.last_error = buf;
  RS_LOG(RS_ERROR, "%s", buf);
}

// --- Callbacks libretro -----------------------------------------------------

void log_cb(enum retro_log_level level, const char* fmt, ...) {
  char buf[1024];
  va_list args;
  va_start(args, fmt);
  vsnprintf(buf, sizeof(buf), fmt, args);
  va_end(args);
  int prio = level >= RETRO_LOG_ERROR  ? RS_ERROR
             : level >= RETRO_LOG_WARN ? RS_WARN
                                       : RS_INFO;
  RS_LOG(prio, "[core] %s", buf);
}

bool environment_cb(unsigned cmd, void* data) {
  switch (cmd) {
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
      *static_cast<const char**>(data) = g.system_dir.c_str();
      return true;
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
      *static_cast<const char**>(data) = g.save_dir.c_str();
      return true;
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
      auto fmt = *static_cast<const retro_pixel_format*>(data);
      if (fmt == RETRO_PIXEL_FORMAT_RGB565 || fmt == RETRO_PIXEL_FORMAT_XRGB8888 ||
          fmt == RETRO_PIXEL_FORMAT_0RGB1555) {
        g.pixel_format = fmt;
        return true;
      }
      return false;
    }
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
      static_cast<retro_log_callback*>(data)->log = log_cb;
      return true;
    case RETRO_ENVIRONMENT_GET_CAN_DUPE:
      *static_cast<bool*>(data) = true;
      return true;
    case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
      return true;
    case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
      // true una vez tras cambiar opciones: el núcleo vuelve a leerlas.
      *static_cast<bool*>(data) = g.options_dirty.exchange(false);
      return true;
    case RETRO_ENVIRONMENT_GET_VARIABLE: {
      auto* var = static_cast<retro_variable*>(data);
      if (!var->key) return false;
      std::lock_guard<std::mutex> lock(g.options_mutex);
      // 1) elección del usuario/app; 2) valor por defecto declarado por el núcleo.
      auto it = g.options.find(var->key);
      if (it == g.options.end()) {
        it = g.option_defaults.find(var->key);
        if (it == g.option_defaults.end()) {
          var->value = nullptr;
          return false;
        }
      }
      var->value = it->second.c_str();  // estable mientras no se modifique esa clave
      return true;
    }
    case RETRO_ENVIRONMENT_GET_USERNAME: {
      // Nombre del jugador (lo pone la app como opción "rs_username"). PPSSPP
      // lo usa como apodo de la PSP en el multijugador ad hoc.
      std::lock_guard<std::mutex> lock(g.options_mutex);
      auto it = g.options.find("rs_username");
      if (it == g.options.end() || it->second.empty()) return false;
      *static_cast<const char**>(data) = it->second.c_str();
      return true;
    }
    case RETRO_ENVIRONMENT_SET_VARIABLES: {
      // Formato: {"clave", "Descripción; valor1|valor2|..."}; el primero es el
      // valor por defecto. Ignorarlo deja al núcleo con los valores internos de
      // su código, que pueden no coincidir (melonDS no arrancaba los juegos).
      std::lock_guard<std::mutex> lock(g.options_mutex);
      for (auto* v = static_cast<const retro_variable*>(data); v && v->key; ++v) {
        if (!v->value) continue;
        std::string spec(v->value);
        auto semi = spec.find(';');
        if (semi == std::string::npos) continue;
        auto first = spec.find_first_not_of(' ', semi + 1);
        if (first == std::string::npos) continue;
        auto bar = spec.find('|', first);
        g.option_defaults[v->key] = spec.substr(first, bar == std::string::npos ? std::string::npos : bar - first);
      }
      return true;
    }
    case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
      *static_cast<unsigned*>(data) = 0;
      return true;
    case RETRO_ENVIRONMENT_SET_HW_RENDER:
      // Núcleos que dibujan con la GPU (PPSSPP): OpenGL ES en un FBO propio.
      return rs::hw::request(static_cast<retro_hw_render_callback*>(data));
    case RETRO_ENVIRONMENT_GET_PREFERRED_HW_RENDER:
      *static_cast<unsigned*>(data) = rs::hw::preferred();
      return true;
    case RETRO_ENVIRONMENT_GET_LANGUAGE:
      *static_cast<unsigned*>(data) = RETRO_LANGUAGE_SPANISH;
      return true;
    case RETRO_ENVIRONMENT_SET_NETPACKET_INTERFACE:
      // Núcleos con link por red (gpSP: cable link y adaptador inalámbrico).
      rs::net::set_packet_interface(static_cast<const retro_netpacket_callback*>(data));
      return true;
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
    case RETRO_ENVIRONMENT_SET_MEMORY_MAPS:
    case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
    case RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO:
    case RETRO_ENVIRONMENT_SET_SUPPORT_ACHIEVEMENTS:
    case RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS:
      return true;
    default:
      return false;
  }
}

inline uint32_t rgba(uint32_t r, uint32_t g8, uint32_t b) {
  // ANativeWindow RGBA_8888 en memoria little-endian: R, G, B, A.
  return r | (g8 << 8) | (b << 16) | 0xFF000000u;
}

void convert_row(const void* src, uint32_t* dst, unsigned width) {
  switch (g.pixel_format) {
    case RETRO_PIXEL_FORMAT_RGB565: {
      auto* s = static_cast<const uint16_t*>(src);
      for (unsigned x = 0; x < width; ++x) {
        uint32_t p = s[x];
        uint32_t r = (p >> 11) & 0x1F, gg = (p >> 5) & 0x3F, b = p & 0x1F;
        dst[x] = rgba((r << 3) | (r >> 2), (gg << 2) | (gg >> 4), (b << 3) | (b >> 2));
      }
      break;
    }
    case RETRO_PIXEL_FORMAT_0RGB1555: {
      auto* s = static_cast<const uint16_t*>(src);
      for (unsigned x = 0; x < width; ++x) {
        uint32_t p = s[x];
        uint32_t r = (p >> 10) & 0x1F, gg = (p >> 5) & 0x1F, b = p & 0x1F;
        dst[x] = rgba((r << 3) | (r >> 2), (gg << 3) | (gg >> 2), (b << 3) | (b >> 2));
      }
      break;
    }
    case RETRO_PIXEL_FORMAT_XRGB8888: {
      auto* s = static_cast<const uint32_t*>(src);
      for (unsigned x = 0; x < width; ++x) {
        uint32_t p = s[x];
        dst[x] = rgba((p >> 16) & 0xFF, (p >> 8) & 0xFF, p & 0xFF);
      }
      break;
    }
    default:
      break;
  }
}

void video_refresh_cb(const void* data, unsigned width, unsigned height, size_t pitch) {
  if (data == RETRO_HW_FRAME_BUFFER_VALID) {
    // El núcleo ya dibujó en el FBO: se presenta en este mismo hilo, que es
    // el dueño del contexto OpenGL.
    {
      std::lock_guard<std::mutex> frame_lock(g.frame_mutex);
      g.last_w = width;
      g.last_h = height;
#if defined(_WIN32) || defined(__APPLE__)
      // Sin superficie nativa (Windows, iPhone): se lee el FBO y se entrega
      // como un fotograma normal a Flutter (rs_copy_frame).
      unsigned w = width, h = height;
      rs::hw::capture(g.last_frame, w, h);
#endif
    }
#if defined(_WIN32) || defined(__APPLE__)
    if (auto cb = g_frame_cb.load()) cb(g_frame_cb_user.load());
#endif
    rs::hw::present(width, height);
    return;
  }
  if (!data) return;  // fotograma duplicado: la ventana conserva el anterior
  {
    std::lock_guard<std::mutex> frame_lock(g.frame_mutex);
    g.last_frame.resize(static_cast<size_t>(width) * height);
    g.last_w = width;
    g.last_h = height;
    for (unsigned y = 0; y < height; ++y) {
      convert_row(static_cast<const uint8_t*>(data) + y * pitch, &g.last_frame[y * width], width);
    }
  }
#ifndef __ANDROID__
  // Escritorio: la ventana de Flutter copia el fotograma con rs_copy_frame
  // cuando se le avisa de que hay uno nuevo.
  if (auto cb = g_frame_cb.load()) cb(g_frame_cb_user.load());
  return;
#endif
  // Solo avisa al hilo de presentación; si aún está enviando el anterior,
  // enviará el más reciente cuando termine (los intermedios se descartan).
  {
    std::lock_guard<std::mutex> lock(g.present_mutex);
    g.present_pending = true;
  }
  g.present_cv.notify_one();
}

#ifdef __ANDROID__
void present_to_window(const uint32_t* pixels, unsigned width, unsigned height) {
  std::lock_guard<std::mutex> lock(g.window_mutex);
  if (!g.window) return;
  if (g.window_w != static_cast<int32_t>(width) || g.window_h != static_cast<int32_t>(height)) {
    ANativeWindow_setBuffersGeometry(g.window, width, height, WINDOW_FORMAT_RGBA_8888);
    g.window_w = width;
    g.window_h = height;
  }
  ANativeWindow_Buffer buffer;
  if (ANativeWindow_lock(g.window, &buffer, nullptr) != 0) return;
  unsigned rows = std::min<unsigned>(height, buffer.height);
  unsigned cols = std::min<unsigned>(width, buffer.width);
  for (unsigned y = 0; y < rows; ++y) {
    auto* dst = static_cast<uint32_t*>(buffer.bits) + y * buffer.stride;
    std::memcpy(dst, pixels + static_cast<size_t>(y) * width, cols * sizeof(uint32_t));
  }
  ANativeWindow_unlockAndPost(g.window);
}
#endif

void present_loop() {
  std::vector<uint32_t> pixels;
  for (;;) {
    {
      std::unique_lock<std::mutex> lock(g.present_mutex);
      g.present_cv.wait(lock, [] { return g.present_pending || g.present_stop; });
      if (g.present_stop) return;
      g.present_pending = false;
    }
    unsigned w, h;
    {
      std::lock_guard<std::mutex> frame_lock(g.frame_mutex);
      pixels.assign(g.last_frame.begin(), g.last_frame.end());  // reutiliza la memoria
      w = g.last_w;
      h = g.last_h;
    }
    if (pixels.empty() || pixels.size() < static_cast<size_t>(w) * h) continue;
#ifdef __ANDROID__
    present_to_window(pixels.data(), w, h);
#endif
  }
}

void start_presenter() {
  {
    std::lock_guard<std::mutex> lock(g.present_mutex);
    g.present_stop = false;
    g.present_pending = false;
  }
  g.present_thread = std::thread(present_loop);
}

void stop_presenter() {
  {
    std::lock_guard<std::mutex> lock(g.present_mutex);
    g.present_stop = true;
  }
  g.present_cv.notify_all();
  if (g.present_thread.joinable()) g.present_thread.join();
}

bool audio_enabled_for_frame() {
  // Con avance rápido o rebobinado el audio se silencia (sonaría acelerado).
  return g.speed.load() <= 1.0f && !g.rewinding.load();
}

void audio_sample_cb(int16_t left, int16_t right) {
  if (!audio_enabled_for_frame()) return;
  int16_t frame[2] = {left, right};
  g.audio.push(frame, 1);
}

size_t audio_sample_batch_cb(const int16_t* data, size_t frames) {
  if (audio_enabled_for_frame()) g.audio.push(data, frames);
  return frames;
}

void input_poll_cb() {}

int16_t input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id) {
  if (g.net_frame) {
    // Lockstep: jugador 1 = anfitrión, jugador 2 = invitado, en los dos teléfonos.
    if (port > 1) return 0;
    const auto& in = g.net_input[port];
    unsigned base = device & RETRO_DEVICE_MASK;
    if (base == RETRO_DEVICE_ANALOG && index < 2 && id < 2) return in.analog[index * 2 + id];
    if (base != RETRO_DEVICE_JOYPAD) return 0;
    if (id == RETRO_DEVICE_ID_JOYPAD_MASK) return static_cast<int16_t>(in.buttons);
    if (id < 16) return (in.buttons >> id) & 1;
    return 0;
  }
  if (port == 0 && device == RETRO_DEVICE_POINTER && index == 0) {
    switch (id) {
      case RETRO_DEVICE_ID_POINTER_X: return static_cast<int16_t>(g.pointer_x.load());
      case RETRO_DEVICE_ID_POINTER_Y: return static_cast<int16_t>(g.pointer_y.load());
      case RETRO_DEVICE_ID_POINTER_PRESSED: return g.pointer_pressed.load() ? 1 : 0;
      default: return 0;
    }
  }
  if (port == 0 && device == RETRO_DEVICE_ANALOG && index < 2 && id < 2) {
    return g.analog[index][id].load(std::memory_order_relaxed);
  }
  if (port != 0 || device != RETRO_DEVICE_JOYPAD) return 0;
  uint32_t mask = g.buttons.load(std::memory_order_relaxed) | g.latched.load(std::memory_order_relaxed);
  if (id == RETRO_DEVICE_ID_JOYPAD_MASK) return static_cast<int16_t>(mask & 0xFFFF);
  if (id < 16) return (mask >> id) & 1;
  return 0;
}

// --- Utilidades -------------------------------------------------------------

template <typename T>
bool load_symbol(T& fn, const char* name) {
  fn = reinterpret_cast<T>(rs::platform::lib_sym(g.core.handle, name));
  if (!fn) set_error("El núcleo no exporta %s", name);
  return fn != nullptr;
}

bool read_file(const std::string& path, std::vector<uint8_t>& out) {
  std::ifstream in(path, std::ios::binary | std::ios::ate);
  if (!in) return false;
  auto size = in.tellg();
  if (size <= 0) return false;
  out.resize(static_cast<size_t>(size));
  in.seekg(0);
  return static_cast<bool>(in.read(reinterpret_cast<char*>(out.data()), size));
}

bool write_file_atomic(const std::string& path, const uint8_t* data, size_t size) {
  std::string tmp = path + ".tmp";
  {
    std::ofstream out(tmp, std::ios::binary | std::ios::trunc);
    if (!out) return false;
    out.write(reinterpret_cast<const char*>(data), static_cast<std::streamsize>(size));
    out.flush();
    if (!out) return false;
  }
  return std::rename(tmp.c_str(), path.c_str()) == 0;
}

// Requiere core_mutex.
int32_t save_sram_locked() {
  if (!g.loaded || g.sram_path.empty()) return RS_ERR_NOT_LOADED;
  size_t size = g.core.get_memory_size(RETRO_MEMORY_SAVE_RAM);
  auto* data = static_cast<const uint8_t*>(g.core.get_memory_data(RETRO_MEMORY_SAVE_RAM));
  if (!data || size == 0) return RS_OK;  // el juego no usa guardado interno
  if (g.sram_snapshot.size() == size && std::memcmp(g.sram_snapshot.data(), data, size) == 0) {
    return RS_OK;  // sin cambios
  }
  if (!write_file_atomic(g.sram_path, data, size)) {
    set_error("No se pudo escribir la partida en %s", g.sram_path.c_str());
    return RS_ERR_IO;
  }
  g.sram_snapshot.assign(data, data + size);
  RS_LOG(RS_INFO, "SRAM guardada (%zu bytes)", size);
  return RS_OK;
}

void restore_sram_locked() {
  size_t size = g.core.get_memory_size(RETRO_MEMORY_SAVE_RAM);
  auto* data = static_cast<uint8_t*>(g.core.get_memory_data(RETRO_MEMORY_SAVE_RAM));
  if (!data || size == 0 || g.sram_path.empty()) return;
  std::vector<uint8_t> file;
  if (!read_file(g.sram_path, file)) return;
  size_t n = std::min(size, file.size());
  std::memcpy(data, file.data(), n);
  g.sram_snapshot.assign(data, data + size);
  RS_LOG(RS_INFO, "SRAM restaurada (%zu bytes)", n);
}

// Requiere core_mutex. Guarda una instantánea para el rebobinado.
void push_rewind_state_locked() {
  if (!g.serialize || g.rewind_capacity == 0) return;
  size_t size = g.serialize_size();
  if (size == 0) return;
  // Presupuesto de memoria fijo: en DS o PS1 cada instantánea ocupa varios MB y
  // 20 s de historial superarían 1 GB. Se acorta el historial, nunca la RAM.
  constexpr size_t kRewindBudget = 96u * 1024 * 1024;
  size_t max_states = std::max<size_t>(1, kRewindBudget / size);
  while (g.rewind_states.size() > std::min(g.rewind_capacity, max_states)) {
    g.rewind_states.pop_front();
  }
  if (g.rewind_states.size() >= max_states && g.rewind_states.size() < g.rewind_capacity) {
    // Historial lleno por memoria: se recicla la instantánea más antigua.
    std::vector<uint8_t> state = std::move(g.rewind_states.front());
    g.rewind_states.pop_front();
    state.resize(size);
    if (g.serialize(state.data(), size)) g.rewind_states.push_back(std::move(state));
    return;
  }
  std::vector<uint8_t> state;
  if (g.rewind_states.size() >= g.rewind_capacity) {
    state = std::move(g.rewind_states.front());  // reutiliza la memoria más antigua
    g.rewind_states.pop_front();
  }
  state.resize(size);
  if (g.serialize(state.data(), size)) g.rewind_states.push_back(std::move(state));
}

// Requiere core_mutex. Retrocede una instantánea; false si no quedan.
bool pop_rewind_state_locked() {
  if (g.rewind_states.empty() || !g.unserialize) return false;
  auto& state = g.rewind_states.back();
  bool ok = g.unserialize(state.data(), state.size());
  g.rewind_states.pop_back();
  return ok;
}

bool tasks_pending() {
  std::lock_guard<std::mutex> lock(g.task_mutex);
  return !g.tasks.empty();
}

void run_pending_tasks() {
  for (;;) {
    std::function<void()> task;
    {
      std::lock_guard<std::mutex> lock(g.task_mutex);
      if (g.tasks.empty()) return;
      task = std::move(g.tasks.front());
      g.tasks.pop_front();
    }
    task();
  }
}

// Ejecuta [fn] en el hilo de emulación entre dos fotogramas y espera a que
// termine. Los núcleos con GPU (PPSSPP) tienen su propio hilo interno que
// espera al de retro_run: un save state desde otro hilo los bloquearía.
// Así lo hace también RetroArch. Sin hilo de emulación, se ejecuta aquí.
int32_t run_on_emulation_thread(std::function<int32_t()> fn) {
  if (!g.running.load()) return fn();
  auto task = std::make_shared<std::packaged_task<int32_t()>>(std::move(fn));
  auto result = task->get_future();
  {
    std::lock_guard<std::mutex> lock(g.task_mutex);
    g.tasks.emplace_back([task] { (*task)(); });
  }
  g.pause_cv.notify_all();  // por si el juego está en pausa
  return result.get();
}

#ifdef __ANDROID__
// Performance Hint (Android 13+): se le dice al sistema cuánto debe tardar
// cada fotograma y cuánto tardó de verdad, y él ajusta la frecuencia de la
// CPU. Sin esto, el regulador de energía de algunos móviles (p. ej. Samsung)
// deja los núcleos a media velocidad y la emulación no llega a 60 FPS.
// Se carga con dlsym para seguir funcionando en Android 7-12.
class PerformanceHint {
 public:
  void open(int64_t target_ns) {
    void* lib = dlopen("libandroid.so", RTLD_NOW);
    if (!lib) return;
    auto get_manager = reinterpret_cast<void* (*)()>(dlsym(lib, "APerformanceHint_getManager"));
    auto create = reinterpret_cast<void* (*)(void*, const int32_t*, size_t, int64_t)>(
        dlsym(lib, "APerformanceHint_createSession"));
    report_ = reinterpret_cast<int (*)(void*, int64_t)>(
        dlsym(lib, "APerformanceHint_reportActualWorkDuration"));
    update_ = reinterpret_cast<int (*)(void*, int64_t)>(
        dlsym(lib, "APerformanceHint_updateTargetWorkDuration"));
    close_ = reinterpret_cast<void (*)(void*)>(dlsym(lib, "APerformanceHint_closeSession"));
    if (!get_manager || !create || !report_ || !close_) return;
    void* manager = get_manager();
    if (!manager) return;
    const int32_t tid = static_cast<int32_t>(gettid());
    session_ = create(manager, &tid, 1, target_ns);
    target_ns_ = target_ns;
    RS_LOG(RS_INFO, "Performance Hint %s", session_ ? "activo" : "no disponible");
  }
  void report(int64_t actual_ns, int64_t target_ns) {
    if (!session_) return;
    if (update_ && target_ns != target_ns_) {
      update_(session_, target_ns);  // avance rápido: fotogramas más cortos
      target_ns_ = target_ns;
    }
    report_(session_, actual_ns > 0 ? actual_ns : 1);
  }
  ~PerformanceHint() {
    if (session_) close_(session_);
  }

 private:
  void* session_ = nullptr;
  int64_t target_ns_ = 0;
  int (*report_)(void*, int64_t) = nullptr;
  int (*update_)(void*, int64_t) = nullptr;
  void (*close_)(void*) = nullptr;
};
#endif

// Entrada local de este fotograma para el multijugador (y suelta las
// pulsaciones retenidas que ya se han tenido en cuenta).
rs::net::PadInput sample_local_input() {
  rs::net::PadInput in;
  uint32_t seen = g.latched.load(std::memory_order_relaxed);
  in.buttons = static_cast<uint16_t>((g.buttons.load(std::memory_order_relaxed) | seen) & 0xFFFF);
  g.latched.fetch_and(~seen, std::memory_order_relaxed);
  for (int s = 0; s < 2; ++s) {
    for (int a = 0; a < 2; ++a) in.analog[s * 2 + a] = g.analog[s][a].load(std::memory_order_relaxed);
  }
  return in;
}

void emulation_loop() {
  const double target_fps = g.av.timing.fps > 0 ? g.av.timing.fps : 60.0;
  constexpr uint64_t kAutosaveFrames = 60 * 10;  // ~10 s
  uint64_t frames_since_snapshot = 0;

  auto next = Clock::now();
  auto window_start = next;
  uint64_t window_frames = 0;
#ifdef __ANDROID__
  PerformanceHint hint;
  hint.open(static_cast<int64_t>(1e9 / target_fps));
#endif

  // Núcleos con GPU: el contexto se crea en este hilo, que es el que llama a
  // retro_run (lo exige libretro).
  const bool hw = rs::hw::active();
  // Sin contexto de GPU el núcleo no puede dibujar: llamar a retro_run así
  // cierra la app (PPSSPP). Se espera sin ejecutar hasta que se salga.
  const bool hw_failed =
      hw && !rs::hw::start(g.av.geometry.max_width, g.av.geometry.max_height);
  if (hw_failed) {
    set_error("No se pudo iniciar OpenGL ES para este núcleo");
  }

  while (g.running.load()) {
    if (hw_failed) {
      run_pending_tasks();
      std::this_thread::sleep_for(std::chrono::milliseconds(50));
      continue;
    }
    if (g.paused.load()) {
      g.fps.store(0.0);
      if (hw) {
        // Miniatura para los save states que se hagan con el juego en pausa.
        std::lock_guard<std::mutex> core_lock(g.core_mutex);
        std::lock_guard<std::mutex> frame_lock(g.frame_mutex);
        unsigned w = g.last_w, h = g.last_h;
        rs::hw::capture(g.last_frame, w, h);
      }
      std::unique_lock<std::mutex> lock(g.pause_mutex);
      while (g.paused.load() && g.running.load()) {
        g.pause_cv.wait(lock, [] {
          return !g.paused.load() || !g.running.load() || rs::hw::window_change_pending() ||
                 tasks_pending();
        });
        if (rs::hw::window_change_pending()) rs::hw::poll_window();  // superficie nueva en pausa
        if (tasks_pending()) {
          lock.unlock();
          run_pending_tasks();  // save states con el juego en pausa
          lock.lock();
        }
      }
      next = Clock::now();
      window_start = next;
      window_frames = 0;
      continue;
    }

    run_pending_tasks();

    // Multijugador lockstep: el fotograma solo avanza cuando están las
    // pulsaciones de los dos jugadores.
    const bool lockstep = rs::net::lockstep_active();
    bool net_behind = false;
    if (lockstep) {
      rs::net::PadInput inputs[2];
      if (rs::net::begin_frame(sample_local_input(), g.net_hooks, inputs, &net_behind) ==
          rs::net::Step::kWait) {
        auto now = Clock::now();
        if (now - window_start >= std::chrono::seconds(1)) {
          g.fps.store(window_frames / std::chrono::duration<double>(now - window_start).count());
          window_start = now;
          window_frames = 0;
        }
        next = now;
        continue;
      }
      g.net_input[0] = inputs[0];
      g.net_input[1] = inputs[1];
    }

    const auto work_start = Clock::now();
    {
      std::lock_guard<std::mutex> lock(g.core_mutex);
      if (lockstep) {
        // Sin rebobinado ni avance rápido: los dos teléfonos deben ejecutar
        // exactamente los mismos fotogramas.
        g.net_frame = true;
        g.core.run();
        g.net_frame = false;
        uint64_t frames = g.frame_count.fetch_add(1) + 1;
        if (frames % kAutosaveFrames == 0) save_sram_locked();
        frames_since_snapshot = 0;
      } else if (g.rewinding.load()) {
        // Rebobinar: restaura una instantánea cada 3 iteraciones (20 por
        // segundo = ~3x la velocidad normal) y muestra un fotograma de cada una.
        static uint32_t rewind_tick = 0;
        if (++rewind_tick % 3 == 0 && pop_rewind_state_locked()) g.core.run();
        frames_since_snapshot = 0;
      } else {
        // Las pulsaciones retenidas antes de este fotograma ya se han visto.
        uint32_t seen = g.latched.load(std::memory_order_relaxed);
        rs::net::packet_frame();  // link de GBA: paquetes recibidos y conexiones
        g.core.run();
        g.latched.fetch_and(~seen, std::memory_order_relaxed);
        uint64_t frames = g.frame_count.fetch_add(1) + 1;
        if (frames % kAutosaveFrames == 0) save_sram_locked();
        if (g.rewind_enabled.load() && ++frames_since_snapshot >= g.rewind_interval) {
          push_rewind_state_locked();
          frames_since_snapshot = 0;
        }
      }
    }
    if (lockstep) rs::net::end_frame(g.net_hooks);
    ++window_frames;
    const float speed = lockstep ? 1.0f : g.speed.load();
#ifdef __ANDROID__
    hint.report(
        std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now() - work_start).count(),
        static_cast<int64_t>(1e9 / (target_fps * speed)));
#endif

    // La velocidad puede cambiar en cualquier momento (avance rápido).
    const auto period = std::chrono::duration_cast<Clock::duration>(
        std::chrono::duration<double>(1.0 / (target_fps * speed)));

    auto now = Clock::now();
    if (now - window_start >= std::chrono::seconds(1)) {
      double secs = std::chrono::duration<double>(now - window_start).count();
      g.fps.store(window_frames / secs);
      // Diagnóstico de rendimiento (adb logcat -s RetroStation).
      static int fps_log_tick = 0;
      if (++fps_log_tick % 5 == 0) RS_LOG(RS_INFO, "FPS: %.1f", window_frames / secs);
      window_start = now;
      window_frames = 0;
    }

    next += period;
    if (net_behind) next = now;  // el otro teléfono va por delante: alcanzarlo
    if (now - next > std::chrono::milliseconds(100)) {
      next = now;  // demasiado retraso (p. ej. el sistema suspendió el hilo): resincronizar
    }
    std::this_thread::sleep_until(next);
  }
  run_pending_tasks();  // nadie se queda esperando una tarea al salir
  if (hw) rs::hw::stop();
}

bool write_state_file(const std::string& path) {
  if (!g.serialize) return false;
  size_t size = g.serialize_size();
  if (size == 0) return false;
  std::vector<uint8_t> buf(size);
  if (!g.serialize(buf.data(), size)) return false;
  return write_file_atomic(path, buf.data(), size);
}

#if defined(__APPLE__)
// En iPhone los hilos secundarios solo tienen 512 KB de pila (en Android y
// Windows, 1 MB o más). PPSSPP arranca el juego y compila los shaders de
// OpenGL ES dentro de retro_run, y con esa pila la app se cerraba al abrir un
// juego de PSP. El hilo de emulación se crea con 16 MB, como el principal de
// RetroArch.
pthread_t g_emu_pthread{};
bool g_emu_pthread_started = false;

void* emulation_entry(void*) {
  pthread_setname_np("RetroStation emu");
  emulation_loop();
  return nullptr;
}

bool start_emulation_thread() {
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setstacksize(&attr, 16 * 1024 * 1024);
  const bool ok = pthread_create(&g_emu_pthread, &attr, emulation_entry, nullptr) == 0;
  pthread_attr_destroy(&attr);
  g_emu_pthread_started = ok;
  return ok;
}

void join_emulation_thread() {
  if (!g_emu_pthread_started) return;
  pthread_join(g_emu_pthread, nullptr);
  g_emu_pthread_started = false;
}
#else
bool start_emulation_thread() {
  g.thread = std::thread(emulation_loop);
  return true;
}

void join_emulation_thread() {
  if (g.thread.joinable()) g.thread.join();
}
#endif

void stop_thread() {
  if (!g.running.exchange(false)) return;
  {
    std::lock_guard<std::mutex> lock(g.pause_mutex);
    g.paused.store(false);
  }
  g.pause_cv.notify_all();
  join_emulation_thread();
  stop_presenter();
}

int32_t save_state_impl(const char* path) {
  std::lock_guard<std::mutex> lock(g.core_mutex);
  if (!g.loaded) return RS_ERR_NOT_LOADED;
  if (!g.serialize) {
    set_error("Este núcleo no admite save states");
    return RS_ERR_UNSUPPORTED;
  }
  if (!write_state_file(path)) {
    set_error("No se pudo guardar el estado en %s", path);
    return RS_ERR_IO;
  }
  return RS_OK;
}

int32_t load_state_impl(const char* path) {
  std::vector<uint8_t> buf;
  if (!read_file(path, buf)) {
    set_error("No se pudo leer el estado %s", path);
    return RS_ERR_IO;
  }
  std::lock_guard<std::mutex> lock(g.core_mutex);
  if (!g.loaded) return RS_ERR_NOT_LOADED;
  if (!g.unserialize) {
    set_error("Este núcleo no admite save states");
    return RS_ERR_UNSUPPORTED;
  }
  if (!g.unserialize(buf.data(), buf.size())) {
    set_error("El estado no es compatible con este juego o versión del núcleo");
    return RS_ERR_STATE_INVALID;
  }
  g.rewind_states.clear();  // el historial anterior ya no corresponde
  return RS_OK;
}

}  // namespace

// --- API C ------------------------------------------------------------------

extern "C" {

RS_API int32_t rs_load(const char* core_path, const char* rom_path, const char* system_dir,
                       const char* save_dir, const char* sram_path) {
  if (g.loaded) {
    set_error("Ya hay un juego cargado");
    return RS_ERR_ALREADY_LOADED;
  }
  g.last_error.clear();
  // Red de Windows lista antes de cargar el núcleo: PPSSPP abre sockets por su
  // cuenta (multijugador ad hoc) y en Windows fallan sin WSAStartup (10093).
  rs::net::sock::init();
  g.system_dir = system_dir ? system_dir : "";
  g.save_dir = save_dir ? save_dir : "";
  g.sram_path = sram_path ? sram_path : "";
  g.pixel_format = RETRO_PIXEL_FORMAT_0RGB1555;
  g.sram_snapshot.clear();
  g.frame_count.store(0);
  g.fps.store(0.0);
  g.buttons.store(0);
  g.latched.store(0);

  {
    std::lock_guard<std::mutex> lock(g.options_mutex);
    g.option_defaults.clear();  // cada núcleo declara los suyos
  }
  rs::net::set_packet_interface(nullptr);
  g.core = CoreApi{};
  g.core.handle = rs::platform::lib_open(core_path);
  if (!g.core.handle) {
    set_error("No se pudo abrir el núcleo %s: %s", core_path, rs::platform::lib_error());
    return RS_ERR_CORE_OPEN;
  }

  bool ok = load_symbol(g.core.set_environment, "retro_set_environment") &&
            load_symbol(g.core.set_video_refresh, "retro_set_video_refresh") &&
            load_symbol(g.core.set_audio_sample, "retro_set_audio_sample") &&
            load_symbol(g.core.set_audio_sample_batch, "retro_set_audio_sample_batch") &&
            load_symbol(g.core.set_input_poll, "retro_set_input_poll") &&
            load_symbol(g.core.set_input_state, "retro_set_input_state") &&
            load_symbol(g.core.init, "retro_init") &&
            load_symbol(g.core.deinit, "retro_deinit") &&
            load_symbol(g.core.get_system_info, "retro_get_system_info") &&
            load_symbol(g.core.get_system_av_info, "retro_get_system_av_info") &&
            load_symbol(g.core.reset, "retro_reset") &&
            load_symbol(g.core.run, "retro_run") &&
            load_symbol(g.core.load_game, "retro_load_game") &&
            load_symbol(g.core.unload_game, "retro_unload_game") &&
            load_symbol(g.core.get_memory_data, "retro_get_memory_data") &&
            load_symbol(g.core.get_memory_size, "retro_get_memory_size");
  if (!ok) {
    rs::platform::lib_close(g.core.handle);
    g.core = CoreApi{};
    return RS_ERR_CORE_SYMBOLS;
  }

  // Los núcleos que leen el juego desde su ruta (need_fullpath: DeSmuME,
  // PPSSPP...) no necesitan una copia en memoria. Con ISO de PSP de 1-2 GB esa
  // copia ni siquiera cabría en un proceso de 32 bits.
  retro_system_info pre{};
  g.core.get_system_info(&pre);
  g.rom.clear();
  g.rom.shrink_to_fit();
  if (!pre.need_fullpath && !read_file(rom_path, g.rom)) {
    set_error("No se pudo leer el ROM %s", rom_path);
    rs::platform::lib_close(g.core.handle);
    g.core = CoreApi{};
    return RS_ERR_ROM_READ;
  }

  std::lock_guard<std::mutex> lock(g.core_mutex);
  g.core.set_environment(environment_cb);
  g.core.set_video_refresh(video_refresh_cb);
  g.core.set_audio_sample(audio_sample_cb);
  g.core.set_audio_sample_batch(audio_sample_batch_cb);
  g.core.set_input_poll(input_poll_cb);
  g.core.set_input_state(input_state_cb);
  g.core.init();

  retro_system_info sys{};
  g.core.get_system_info(&sys);
  RS_LOG(RS_INFO, "Núcleo %s %s", sys.library_name ? sys.library_name : "?",
         sys.library_version ? sys.library_version : "?");
  g.core_id = std::string(sys.library_name ? sys.library_name : "?") + " " +
              (sys.library_version ? sys.library_version : "?");

  retro_game_info game{};
  game.path = rom_path;
  game.data = g.rom.empty() ? nullptr : g.rom.data();
  game.size = g.rom.size();
  if (!g.core.load_game(&game)) {
    set_error("El núcleo rechazó el ROM (¿archivo dañado o de otra consola?)");
    g.core.deinit();
    rs::platform::lib_close(g.core.handle);
    g.core = CoreApi{};
    g.rom.clear();
    return RS_ERR_LOAD_GAME;
  }

  g.core.get_system_av_info(&g.av);
  restore_sram_locked();

  // Save states: opcionales en libretro (no todos los núcleos los soportan).
  g.serialize_size = reinterpret_cast<size_t (*)(void)>(
      rs::platform::lib_sym(g.core.handle, "retro_serialize_size"));
  g.serialize = reinterpret_cast<bool (*)(void*, size_t)>(
      rs::platform::lib_sym(g.core.handle, "retro_serialize"));
  g.unserialize = reinterpret_cast<bool (*)(const void*, size_t)>(
      rs::platform::lib_sym(g.core.handle, "retro_unserialize"));
  if (!g.serialize_size || !g.serialize || !g.unserialize) {
    g.serialize_size = nullptr;
    g.serialize = nullptr;
    g.unserialize = nullptr;
  }
  g.rewind_states.clear();
  g.speed.store(1.0f);
  g.rewinding.store(false);
  g.loaded = true;
  RS_LOG(RS_INFO, "Juego cargado: %ux%u a %.4f fps", g.av.geometry.base_width,
         g.av.geometry.base_height, g.av.timing.fps);
  return RS_OK;
}

RS_API int32_t rs_get_av_info(rs_av_info* out) {
  if (!g.loaded || !out) return RS_ERR_NOT_LOADED;
  out->base_width = static_cast<int32_t>(g.av.geometry.base_width);
  out->base_height = static_cast<int32_t>(g.av.geometry.base_height);
  out->aspect_ratio = g.av.geometry.aspect_ratio > 0
                          ? g.av.geometry.aspect_ratio
                          : static_cast<float>(g.av.geometry.base_width) /
                                static_cast<float>(g.av.geometry.base_height);
  out->fps = g.av.timing.fps;
  out->sample_rate = g.av.timing.sample_rate;
  return RS_OK;
}

RS_API int32_t rs_start(void) {
  if (!g.loaded) return RS_ERR_NOT_LOADED;
  if (g.running.exchange(true)) return RS_OK;
  g.paused.store(false);
  if (!g.audio.open(g.av.timing.sample_rate > 0 ? g.av.timing.sample_rate : 32768.0)) {
    RS_LOG(RS_WARN, "Sin salida de audio; el juego continúa en silencio");
  }
  start_presenter();
  if (!start_emulation_thread()) {
    g.running.store(false);
    stop_presenter();
    set_error("No se pudo crear el hilo de emulación");
    return RS_ERR_LOAD_GAME;
  }
  return RS_OK;
}

RS_API void rs_set_paused(int32_t paused) {
  if (!g.loaded) return;
  if (paused) {
    g.paused.store(true);
    g.audio.set_paused(true);
    rs::net::set_local_paused(true);
    std::lock_guard<std::mutex> lock(g.core_mutex);
    save_sram_locked();  // al pausar (p. ej. la app pasa a segundo plano)
  } else {
    {
      std::lock_guard<std::mutex> lock(g.pause_mutex);
      g.paused.store(false);
    }
    g.audio.set_paused(false);
    rs::net::set_local_paused(false);
    g.pause_cv.notify_all();
  }
}

RS_API void rs_set_core_option(const char* key, const char* value) {
  if (!key) return;
  {
    std::lock_guard<std::mutex> lock(g.options_mutex);
    if (value) {
      g.options[key] = value;
      RS_LOG(RS_INFO, "Opción %s = %s", key, value);
    } else {
      g.options.erase(key);
    }
  }
  g.options_dirty.store(true);
}

RS_API void rs_clear_core_options(void) {
  std::lock_guard<std::mutex> lock(g.options_mutex);
  g.options.clear();
}

RS_API void rs_set_analog(int32_t stick, int32_t x, int32_t y) {
  if (stick < 0 || stick > 1) return;
  g.analog[stick][0].store(static_cast<int16_t>(std::clamp(x, -0x7FFF, 0x7FFF)));
  g.analog[stick][1].store(static_cast<int16_t>(std::clamp(y, -0x7FFF, 0x7FFF)));
}

RS_API void rs_set_volume(float volume) {
  g.audio.set_volume(std::clamp(volume, 0.0f, 1.0f));
}

RS_API void rs_set_speed(float speed) { g.speed.store(std::clamp(speed, 0.25f, 8.0f)); }

RS_API int32_t rs_supports_states(void) { return g.loaded && g.serialize ? 1 : 0; }

RS_API int32_t rs_save_state(const char* path) {
  if (!rs::hw::active()) return save_state_impl(path);
  const std::string p = path ? path : "";
  return run_on_emulation_thread([p] { return save_state_impl(p.c_str()); });
}

RS_API int32_t rs_load_state(const char* path) {
  if (rs::net::lockstep_active()) {
    set_error("No se pueden cargar estados durante una partida multijugador");
    return RS_ERR_UNSUPPORTED;
  }
  if (!rs::hw::active()) return load_state_impl(path);
  const std::string p = path ? path : "";
  return run_on_emulation_thread([p] { return load_state_impl(p.c_str()); });
}

RS_API int32_t rs_copy_frame(uint8_t* out, int32_t capacity, int32_t* width, int32_t* height) {
  std::lock_guard<std::mutex> lock(g.frame_mutex);
  if (g.last_frame.empty()) return RS_ERR_NOT_LOADED;
  size_t bytes = g.last_frame.size() * sizeof(uint32_t);
  *width = static_cast<int32_t>(g.last_w);
  *height = static_cast<int32_t>(g.last_h);
  if (!out || capacity < static_cast<int32_t>(bytes)) return static_cast<int32_t>(bytes);
  std::memcpy(out, g.last_frame.data(), bytes);
  return RS_OK;
}

RS_API void rs_set_rewind_enabled(int32_t enabled, int32_t seconds) {
  std::lock_guard<std::mutex> lock(g.core_mutex);
  g.rewind_enabled.store(enabled != 0 && g.serialize != nullptr);
  double fps = g.av.timing.fps > 0 ? g.av.timing.fps : 60.0;
  g.rewind_capacity = enabled ? static_cast<size_t>(seconds * fps / g.rewind_interval) : 0;
  while (g.rewind_states.size() > g.rewind_capacity) g.rewind_states.pop_front();
  RS_LOG(RS_INFO, "Rebobinado %s: capacidad %zu instantáneas", g.rewind_enabled.load() ? "activo" : "inactivo",
         g.rewind_capacity);
}

RS_API void rs_set_rewinding(int32_t rewinding) {
  bool was = g.rewinding.exchange(rewinding != 0);
  if (was != (rewinding != 0)) {
    RS_LOG(RS_INFO, "Rebobinado %s (%zu instantáneas)", rewinding ? "ON" : "OFF",
           g.rewind_states.size());
  }
}

RS_API int32_t rs_rewind_available(void) {
  std::lock_guard<std::mutex> lock(g.core_mutex);
  return static_cast<int32_t>(g.rewind_states.size());
}

RS_API void rs_set_buttons(uint32_t mask) {
  uint32_t old = g.buttons.exchange(mask, std::memory_order_relaxed);
  g.latched.fetch_or(mask & ~old, std::memory_order_relaxed);  // solo las nuevas
  if (old != mask) RS_LOG(RS_INFO, "Botones: 0x%03x", mask);
}

RS_API void rs_set_pointer(int32_t x, int32_t y, int32_t pressed) {
  g.pointer_x.store(std::clamp(x, -0x7FFF, 0x7FFF));
  g.pointer_y.store(std::clamp(y, -0x7FFF, 0x7FFF));
  g.pointer_pressed.store(pressed != 0);
}

RS_API void rs_reset(void) {
  if (!g.loaded || rs::net::lockstep_active()) return;
  auto reset = [] {
    std::lock_guard<std::mutex> lock(g.core_mutex);
    g.core.reset();
    return RS_OK;
  };
  if (rs::hw::active()) {
    run_on_emulation_thread(reset);
  } else {
    reset();
  }
}

RS_API int32_t rs_save_sram(void) {
  std::lock_guard<std::mutex> lock(g.core_mutex);
  return save_sram_locked();
}

RS_API double rs_get_fps(void) { return g.fps.load(); }

RS_API uint64_t rs_get_frame_count(void) { return g.frame_count.load(); }

RS_API void rs_unload(void) {
  if (!g.loaded) return;
  stop_thread();
  rs::net::packet_shutdown();
  rs::net::stop();
  rs::net::set_packet_interface(nullptr);
  g.audio.close();
  std::lock_guard<std::mutex> lock(g.core_mutex);
  save_sram_locked();
  g.rewind_states.clear();
  g.rewind_states.shrink_to_fit();
  g.serialize_size = nullptr;
  g.serialize = nullptr;
  g.unserialize = nullptr;
  {
    std::lock_guard<std::mutex> frame_lock(g.frame_mutex);
    g.last_frame.clear();
  }
  g.core.unload_game();
  rs::hw::reset();
  g.core.deinit();
  rs::platform::lib_close(g.core.handle);
  g.core = CoreApi{};
  g.rom.clear();
  g.rom.shrink_to_fit();
  g.loaded = false;
  RS_LOG(RS_INFO, "Juego descargado");
}

RS_API const char* rs_last_error(void) { return g.last_error.c_str(); }

RS_API void rs_set_frame_callback(void (*callback)(void*), void* user) {
  g_frame_cb_user.store(user);
  g_frame_cb.store(callback);
}

RS_API int32_t rs_netplay_start(int32_t host, int32_t mode, const char* address, int32_t port,
                                int32_t delay, const char* token, const char* game_key) {
  if (!g.loaded) return RS_ERR_NOT_LOADED;
  const bool fresh = mode == 2;  // lockstep sin estado inicial (GBA Link)
  if (mode == rs::net::kLockstep && (!g.serialize || rs::hw::active())) {
    set_error("Este juego no admite multijugador compartido (el núcleo no guarda estados)");
    return RS_ERR_UNSUPPORTED;
  }
  if (mode == rs::net::kPacket && !rs::net::packet_interface_available()) {
    set_error("Este núcleo no tiene cable link por red");
    return RS_ERR_UNSUPPORTED;
  }
  g.net_hooks.save = [](std::vector<uint8_t>& out) {
    std::lock_guard<std::mutex> lock(g.core_mutex);
    if (!g.serialize) return false;
    size_t size = g.serialize_size();
    if (size == 0) return false;
    out.resize(size);
    return g.serialize(out.data(), size);
  };
  g.net_hooks.load = [](const std::vector<uint8_t>& in) {
    std::lock_guard<std::mutex> lock(g.core_mutex);
    if (!g.unserialize || !g.unserialize(in.data(), in.size())) return false;
    g.rewind_states.clear();
    return true;
  };
  rs::net::Config c;
  c.host = host != 0;
  c.mode = mode == rs::net::kPacket ? rs::net::kPacket : rs::net::kLockstep;
  c.fresh = fresh;
  c.address = address ? address : "";
  c.port = port > 0 ? port : 55435;
  c.delay = delay;
  c.token = token ? token : "";
  c.game_key = game_key ? game_key : "";
  c.core_id = g.core_id;
  g.rewinding.store(false);
  g.speed.store(1.0f);
  int32_t rc = rs::net::start(c);
  if (rc != RS_OK) set_error("%s", rs::net::message().c_str());
  return rc;
}

RS_API void rs_netplay_stop(void) {
  // El núcleo solo puede recibir avisos de su sesión de link desde el hilo de
  // emulación o con él detenido: packet_frame() la cierra al ver la desconexión.
  run_on_emulation_thread([] {
    rs::net::packet_shutdown();
    rs::net::stop();
    return RS_OK;
  });
}

RS_API int32_t rs_netplay_status(rs_netplay_info* out) {
  if (!out) return RS_ERR_NOT_LOADED;
  auto s = rs::net::status();
  out->phase = s.phase;
  out->mode = s.mode;
  out->player = s.player;
  out->rtt_ms = s.rtt_ms;
  out->remote_paused = s.remote_paused;
  out->stalled = s.stalled;
  out->resyncs = s.resyncs;
  out->frame = s.frame;
  return RS_OK;
}

RS_API const char* rs_netplay_message(void) {
  g.net_message = rs::net::message();
  return g.net_message.c_str();
}

}  // extern "C"

// --- Puente JNI con la superficie de Flutter (Android) ----------------------

#ifdef __ANDROID__
extern "C" JNIEXPORT void JNICALL
Java_com_moran_retrostation_NativeVideo_setSurface(JNIEnv* env, jobject, jobject surface) {
  ANativeWindow* hw_window = nullptr;
  {
    std::lock_guard<std::mutex> lock(g.window_mutex);
    if (g.window) {
      ANativeWindow_release(g.window);
      g.window = nullptr;
    }
    g.window_w = 0;
    g.window_h = 0;
    if (surface) g.window = ANativeWindow_fromSurface(env, surface);
    hw_window = g.window;
    if (hw_window) ANativeWindow_acquire(hw_window);  // válida aunque cambie otra vez
  }
  // Con renderizado por GPU, la superficie la usa EGL en el hilo de emulación:
  // se le pasa y se espera a que suelte la anterior.
  if (rs::hw::active()) {
    rs::hw::set_window(hw_window, g.running.load(), [] { g.pause_cv.notify_all(); });
  }
  if (hw_window) ANativeWindow_release(hw_window);
}
#endif
