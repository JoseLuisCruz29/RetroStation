// Multijugador por red local (Wi-Fi) entre dos teléfonos con RetroStation.
//
// Dos modos, ambos con una instancia del juego en cada teléfono y cada
// jugador controlando la suya:
//
// - Lockstep (juego compartido: NES, SNES, PS1...). Los dos teléfonos ejecutan
//   el MISMO juego, fotograma a fotograma, y solo se envían las pulsaciones.
//   El anfitrión es el jugador 1 y el invitado el jugador 2. Al empezar, el
//   anfitrión envía su estado (save state) para partir del mismo punto; cada
//   pocos segundos se compara una huella del estado y, si los dos teléfonos se
//   han desincronizado, el anfitrión vuelve a enviar su estado.
//   Las pulsaciones se aplican con unos fotogramas de retraso (`delay`) para
//   que lleguen a tiempo; viajan por UDP, repetidas en cada paquete, de modo
//   que un paquete perdido en la Wi-Fi no detiene el juego.
//
// - Paquetes (cable link / adaptador inalámbrico de GBA con gpSP). Cada
//   jugador tiene SU juego y SU partida guardada; el núcleo intercambia sus
//   propios mensajes a través de RETRO_ENVIRONMENT_SET_NETPACKET_INTERFACE y
//   este módulo solo los transporta (TCP, fiable y en orden).
//
// La conexión de control (handshake, estados, paquetes) es TCP; las pulsaciones
// del modo lockstep, UDP.
#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <string>
#include <vector>

#include "libretro.h"

// El libretro.h de mGBA es anterior a la interfaz netpacket (libretro.h actual).
#ifndef RETRO_ENVIRONMENT_SET_NETPACKET_INTERFACE
#define RETRO_ENVIRONMENT_SET_NETPACKET_INTERFACE 78
#define RETRO_NETPACKET_UNRELIABLE 0
#define RETRO_NETPACKET_RELIABLE (1 << 0)
#define RETRO_NETPACKET_UNSEQUENCED (1 << 1)
#define RETRO_NETPACKET_FLUSH_HINT (1 << 2)
#define RETRO_NETPACKET_BROADCAST 0xFFFF
typedef void (*retro_netpacket_send_t)(int flags, const void* buf, size_t len, uint16_t client_id);
typedef void (*retro_netpacket_poll_receive_t)();
typedef void (*retro_netpacket_start_t)(uint16_t client_id, retro_netpacket_send_t send_fn,
                                        retro_netpacket_poll_receive_t poll_receive_fn);
typedef void (*retro_netpacket_receive_t)(const void* buf, size_t len, uint16_t client_id);
typedef void (*retro_netpacket_stop_t)(void);
typedef void (*retro_netpacket_poll_t)(void);
typedef bool (*retro_netpacket_connected_t)(uint16_t client_id);
typedef void (*retro_netpacket_disconnected_t)(uint16_t client_id);
struct retro_netpacket_callback {
  retro_netpacket_start_t start;
  retro_netpacket_receive_t receive;
  retro_netpacket_stop_t stop;
  retro_netpacket_poll_t poll;
  retro_netpacket_connected_t connected;
  retro_netpacket_disconnected_t disconnected;
  const char* protocol_version;
};
#endif

namespace rs::net {

// Mando de un jugador en un fotograma (lo que viaja por la red).
struct PadInput {
  uint16_t buttons = 0;     // bits RETRO_DEVICE_ID_JOYPAD_*
  int16_t analog[4] = {};   // stick izq. x/y, stick der. x/y
};

enum Phase : int32_t {
  kOff = 0,
  kConnecting = 1,    // anfitrión esperando al invitado / invitado conectando
  kSyncing = 2,       // enviando o recibiendo el estado inicial
  kPlaying = 3,
  kDisconnected = 4,  // el otro jugador salió o se perdió la conexión
  kFailed = 5,        // no se pudo conectar (ver message())
};

enum Mode : int32_t { kLockstep = 0, kPacket = 1 };

struct Config {
  bool host = false;
  Mode mode = kLockstep;
  std::string address;  // invitado: IP del anfitrión
  int port = 55435;
  int delay = 3;        // fotogramas de retraso de entrada (lockstep)
  // Lockstep sin estado inicial: los dos dispositivos arrancan el juego desde
  // cero a la vez (núcleo GBA Link, que no guarda estados).
  bool fresh = false;
  std::string token;    // lo acuerdan las dos apps en la sala (evita intrusos)
  std::string game_key; // huella del juego (SHA-1): debe coincidir (lockstep)
  std::string core_id;  // "nombre versión" del núcleo: debe coincidir
};

// Funciones del frontend que el modo lockstep necesita (save states).
struct Hooks {
  std::function<bool(std::vector<uint8_t>&)> save;
  std::function<bool(const std::vector<uint8_t>&)> load;
};

struct Status {
  int32_t phase;
  int32_t mode;
  int32_t player;         // 0 = jugador 1 (anfitrión), 1 = jugador 2
  int32_t rtt_ms;         // ida y vuelta medido con pings
  int32_t remote_paused;  // el otro jugador tiene el juego en pausa
  int32_t stalled;        // esperando sus pulsaciones (> 250 ms)
  int32_t resyncs;        // resincronizaciones hechas
  int32_t frame;          // fotograma de red actual
};

int32_t start(const Config& config);  // RS_OK o un error RS_ERR_*
void stop();
Phase phase();
Mode mode();
// El modo lockstep controla el bucle de emulación (conectando, sincronizando o jugando).
bool lockstep_active();
Status status();
std::string message();
void set_local_paused(bool paused);

// --- Lockstep (hilo de emulación) ---
enum class Step { kRun, kWait };
// Envía la entrada local y devuelve kRun con las entradas de los dos jugadores
// para el fotograma actual, o kWait si aún falta la del otro (espera ~4 ms).
// `behind` = el otro teléfono va adelantado: no hay que dormir hasta alcanzarlo.
Step begin_frame(const PadInput& local, const Hooks& hooks, PadInput out[2], bool* behind);
void end_frame(const Hooks& hooks);

// --- Paquetes (hilo de emulación) ---
void set_packet_interface(const retro_netpacket_callback* iface);
bool packet_interface_available();
// Antes de cada retro_run: arranca la sesión del núcleo, entrega los paquetes
// recibidos y avisa de conexiones y desconexiones.
void packet_frame();
// Al descargar el juego (con el hilo de emulación ya detenido).
void packet_shutdown();

}  // namespace rs::net
