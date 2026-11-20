// API C del frontend libretro de RetroStation. Es la única superficie que
// Dart ve mediante FFI. Una sola sesión de emulación activa a la vez.
#ifndef RS_FRONTEND_H
#define RS_FRONTEND_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifdef _WIN32
#define RS_API __declspec(dllexport)
#else
#define RS_API __attribute__((visibility("default")))
#endif

// Códigos de resultado.
#define RS_OK 0
#define RS_ERR_ALREADY_LOADED -1
#define RS_ERR_CORE_OPEN -2
#define RS_ERR_CORE_SYMBOLS -3
#define RS_ERR_ROM_READ -4
#define RS_ERR_LOAD_GAME -5
#define RS_ERR_NOT_LOADED -6
#define RS_ERR_UNSUPPORTED -7
#define RS_ERR_IO -8
#define RS_ERR_STATE_INVALID -9

// Bits del mando (identificadores libretro RETRO_DEVICE_ID_JOYPAD_*).
#define RS_BTN_B 0
#define RS_BTN_SELECT 2
#define RS_BTN_START 3
#define RS_BTN_UP 4
#define RS_BTN_DOWN 5
#define RS_BTN_LEFT 6
#define RS_BTN_RIGHT 7
#define RS_BTN_A 8
#define RS_BTN_L 10
#define RS_BTN_R 11

typedef struct {
  int32_t base_width;
  int32_t base_height;
  float aspect_ratio;
  double fps;
  double sample_rate;
} rs_av_info;

// Carga el núcleo (nombre o ruta de la biblioteca), el ROM y la SRAM.
RS_API int32_t rs_load(const char* core_path, const char* rom_path,
                       const char* system_dir, const char* save_dir,
                       const char* sram_path);
RS_API int32_t rs_get_av_info(rs_av_info* out);
// Arranca el hilo de emulación a la velocidad original del sistema.
RS_API int32_t rs_start(void);
RS_API void rs_set_paused(int32_t paused);
RS_API void rs_set_buttons(uint32_t mask);
RS_API void rs_reset(void);
// Pantalla táctil: coordenadas libretro [-32767, 32767] sobre la imagen completa.
RS_API void rs_set_pointer(int32_t x, int32_t y, int32_t pressed);
// Escribe la SRAM en disco de forma atómica. Devuelve RS_OK o un error.
RS_API int32_t rs_save_sram(void);
// Opciones del núcleo (claves libretro, p. ej. "mgba_skip_bios"). Se pueden
// fijar antes de rs_load (opciones que requieren reinicio) o durante el juego.
// value NULL elimina la opción (vuelve al valor por defecto del núcleo).
RS_API void rs_set_core_option(const char* key, const char* value);
RS_API void rs_clear_core_options(void);

// Audio: volumen 0..1. Velocidad: 1 = normal, >1 avance rápido (audio silenciado).
// Joystick analógico: stick 0 = izquierdo, 1 = derecho; x/y de -32767 a 32767
// (y positivo hacia abajo, como en libretro).
RS_API void rs_set_analog(int32_t stick, int32_t x, int32_t y);

RS_API void rs_set_volume(float volume);
RS_API void rs_set_speed(float speed);

// Save states (archivo escrito de forma atómica).
RS_API int32_t rs_supports_states(void);
RS_API int32_t rs_save_state(const char* path);
RS_API int32_t rs_load_state(const char* path);

// Copia el último fotograma en RGBA8888. Si `out` es NULL o `capacity` es
// insuficiente, devuelve los bytes necesarios (> 0); RS_OK si copió.
RS_API int32_t rs_copy_frame(uint8_t* out, int32_t capacity, int32_t* width, int32_t* height);

// Rebobinado: guarda instantáneas en memoria de los últimos `seconds` segundos.
RS_API void rs_set_rewind_enabled(int32_t enabled, int32_t seconds);
RS_API void rs_set_rewinding(int32_t rewinding);
RS_API int32_t rs_rewind_available(void);

// FPS medidos en el último segundo y total de fotogramas emulados.
RS_API double rs_get_fps(void);
RS_API uint64_t rs_get_frame_count(void);
// Detiene el hilo, guarda la SRAM y descarga el núcleo.
RS_API void rs_unload(void);
RS_API const char* rs_last_error(void);

// Escritorio (Windows): `callback(user)` se llama desde el hilo de emulación
// cada vez que hay un fotograma nuevo listo para rs_copy_frame. NULL lo quita.
RS_API void rs_set_frame_callback(void (*callback)(void*), void* user);

// --- Multijugador por red local (ver netplay.h) ---
// mode: 0 = juego compartido (lockstep), 1 = cable link del núcleo (gpSP),
// 2 = lockstep sin estado inicial (núcleo GBA Link: se llama antes de rs_start
// para que los dos dispositivos empiecen exactamente en el fotograma 0).
// Anfitrión (host = 1): escucha en `port` (TCP y UDP). Invitado: se conecta a
// `address`. `token` lo acuerdan las dos apps; `game_key` es la huella del juego.
// Se llama con el juego ya cargado y en marcha.
typedef struct {
  int32_t phase;  // 0 apagado, 1 conectando, 2 sincronizando, 3 jugando, 4 desconectado, 5 error
  int32_t mode;
  int32_t player;  // 0 = jugador 1, 1 = jugador 2
  int32_t rtt_ms;
  int32_t remote_paused;
  int32_t stalled;
  int32_t resyncs;
  int32_t frame;
} rs_netplay_info;

RS_API int32_t rs_netplay_start(int32_t host, int32_t mode, const char* address, int32_t port,
                                int32_t delay, const char* token, const char* game_key);
RS_API void rs_netplay_stop(void);
RS_API int32_t rs_netplay_status(rs_netplay_info* out);
RS_API const char* rs_netplay_message(void);

#ifdef __cplusplus
}
#endif

#endif
