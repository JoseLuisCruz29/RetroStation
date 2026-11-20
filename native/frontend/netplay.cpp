// Multijugador por red local. Ver netplay.h.

#include "netplay.h"

#include <zlib.h>

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <map>
#include <mutex>
#include <thread>

#include "net_socket.h"
#include "rs_frontend.h"

#ifdef __ANDROID__
#include <android/log.h>
#define NET_LOG(...) __android_log_print(ANDROID_LOG_INFO, "RetroStation", "[net] " __VA_ARGS__)
#else
#include <cstdio>
#define NET_LOG(...) (fprintf(stderr, "[net] " __VA_ARGS__), fputc('\n', stderr))
#endif

namespace rs::net {
namespace {

using Clock = std::chrono::steady_clock;
using sock::sock_t;
using sock::valid;

constexpr uint32_t kMagic = 0x504E5352;     // "RSNP"
constexpr uint32_t kUdpMagic = 0x494E5352;  // "RSNI"
constexpr uint16_t kProtocol = 1;
constexpr size_t kRing = 512;               // fotogramas de entradas guardados
constexpr uint32_t kCheckInterval = 300;    // huella del estado cada ~5 s
constexpr size_t kMaxMessage = 96u * 1024 * 1024;
constexpr auto kTimeout = std::chrono::seconds(15);

enum MsgType : uint8_t {
  kHello = 1,
  kWelcome = 2,
  kState = 3,
  kStateAck = 4,
  kCheck = 5,
  kPacketMsg = 6,
  kBye = 7,
  kPing = 8,
  kPong = 9,
  kPause = 10,
};

// --- Serialización little-endian ---------------------------------------------

struct Writer {
  std::vector<uint8_t> b;
  void u8(uint8_t v) { b.push_back(v); }
  void u16(uint16_t v) { u8(v & 0xFF); u8(v >> 8); }
  void u32(uint32_t v) { u16(v & 0xFFFF); u16(v >> 16); }
  void u64(uint64_t v) { u32(static_cast<uint32_t>(v)); u32(static_cast<uint32_t>(v >> 32)); }
  void str(const std::string& s) {
    u16(static_cast<uint16_t>(std::min<size_t>(s.size(), 0xFFFF)));
    b.insert(b.end(), s.begin(), s.begin() + std::min<size_t>(s.size(), 0xFFFF));
  }
  void bytes(const void* p, size_t n) {
    auto* c = static_cast<const uint8_t*>(p);
    b.insert(b.end(), c, c + n);
  }
};

struct Reader {
  const uint8_t* p;
  size_t n;
  size_t i = 0;
  bool ok = true;
  Reader(const uint8_t* data, size_t size) : p(data), n(size) {}
  bool need(size_t k) {
    if (i + k > n) ok = false;
    return ok;
  }
  uint8_t u8() { return need(1) ? p[i++] : 0; }
  uint16_t u16() { uint16_t lo = u8(); return static_cast<uint16_t>(lo | (u8() << 8)); }
  uint32_t u32() { uint32_t lo = u16(); return lo | (static_cast<uint32_t>(u16()) << 16); }
  uint64_t u64() { uint64_t lo = u32(); return lo | (static_cast<uint64_t>(u32()) << 32); }
  std::string str() {
    uint16_t len = u16();
    if (!need(len)) return {};
    std::string s(reinterpret_cast<const char*>(p + i), len);
    i += len;
    return s;
  }
  const uint8_t* rest(size_t* size) {
    *size = n - i;
    return p + i;
  }
};

// --- Estado ------------------------------------------------------------------

struct RingSlot {
  int64_t frame = -1;
  PadInput in;
};

struct ReceivedState {
  uint32_t epoch = 0;
  uint32_t frame = 0;
  std::vector<uint8_t> data;  // sin comprimir
};

struct Net {
  Config cfg;
  std::atomic<int32_t> phase{kOff};
  std::thread thread;
  std::atomic<bool> stop{false};
  sock_t wake[2] = {sock::kNone, sock::kNone};
  sock_t listen_fd = sock::kNone;
  sock_t tcp = sock::kNone;
  sock_t udp = sock::kNone;
  sockaddr_in peer_udp{};
  bool peer_udp_known = false;
  std::mutex send_mutex;  // escrituras TCP desde varios hilos

  std::mutex m;  // protege todo lo de abajo
  std::condition_variable cv;
  std::string message;
  uint32_t session = 0;
  int delay = 3;

  // Lockstep
  RingSlot local[kRing];
  RingSlot remote[kRing];
  int64_t local_last = -1;     // última entrada local decidida
  int64_t remote_contig = -1;  // entradas del otro recibidas sin huecos hasta aquí
  int64_t remote_latest = -1;
  int64_t peer_needs = 0;      // primer fotograma nuestro que al otro le falta
  int64_t frame = 0;           // siguiente fotograma a ejecutar
  uint32_t epoch = 0;          // cambia con cada estado enviado
  bool state_sent = false;
  bool waiting_ack = false;
  bool resync_wanted = false;
  bool have_pending_state = false;
  ReceivedState pending_state;
  std::map<uint32_t, uint32_t> host_crc;    // fotograma -> huella (anfitrión)
  std::map<uint32_t, uint32_t> client_crc;  // fotograma -> huella del invitado
  int32_t resyncs = 0;
  int32_t mismatch_streak = 0;
  bool checks_enabled = true;
  Clock::time_point stall_since{};
  bool stalling = false;
  Clock::time_point last_input_send{};

  // Paquetes
  const retro_netpacket_callback* iface = nullptr;
  bool packet_started = false;
  bool packet_peer_connected = false;
  std::deque<std::pair<uint16_t, std::vector<uint8_t>>> packets;

  std::atomic<int32_t> rtt_ms{-1};
  std::atomic<bool> remote_paused{false};
  std::atomic<bool> local_paused{false};
  Clock::time_point last_rx{};
};

Net n;

bool is_host() { return n.cfg.host; }
// Tipo de partida en el saludo: 0 lockstep, 1 paquetes, 2 lockstep sin estado.
uint8_t wire_mode() { return n.cfg.fresh ? 2 : static_cast<uint8_t>(n.cfg.mode); }
int local_player() { return is_host() ? 0 : 1; }

uint64_t now_ns() {
  return static_cast<uint64_t>(
      std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now().time_since_epoch()).count());
}

void set_phase(Phase p) {
  n.phase.store(p);
  n.cv.notify_all();
}

void fail(Phase p, const std::string& why) {
  {
    std::lock_guard<std::mutex> lock(n.m);
    if (n.message.empty() || p == kFailed) n.message = why;
  }
  NET_LOG("%s", why.c_str());
  set_phase(p);
}

void close_fd(sock_t& fd) {
  if (valid(fd)) sock::close_socket(fd);
  fd = sock::kNone;
}

bool send_all(sock_t fd, const uint8_t* data, size_t size) {
  while (size > 0) {
    sock::io_t w = sock::send_bytes(fd, data, size);
    if (w < 0) {
      if (sock::last_error() == sock::kErrIntr) continue;
      return false;
    }
    data += w;
    size -= static_cast<size_t>(w);
  }
  return true;
}

bool send_msg(MsgType type, const Writer& body) {
  std::lock_guard<std::mutex> lock(n.send_mutex);
  if (!valid(n.tcp)) return false;
  Writer h;
  h.u32(static_cast<uint32_t>(body.b.size() + 1));
  h.u8(type);
  return send_all(n.tcp, h.b.data(), h.b.size()) &&
         (body.b.empty() || send_all(n.tcp, body.b.data(), body.b.size()));
}

uint32_t crc_of(const std::vector<uint8_t>& data) {
  return static_cast<uint32_t>(crc32(0L, data.data(), static_cast<uInt>(data.size())));
}

bool send_state(uint32_t epoch, uint32_t frame, const std::vector<uint8_t>& raw) {
  uLongf cap = compressBound(static_cast<uLong>(raw.size()));
  std::vector<uint8_t> z(cap);
  if (compress2(z.data(), &cap, raw.data(), static_cast<uLong>(raw.size()), 1) != Z_OK) return false;
  Writer w;
  w.u32(epoch);
  w.u32(frame);
  w.u32(static_cast<uint32_t>(raw.size()));
  w.bytes(z.data(), cap);
  NET_LOG("Enviando estado (época %u, fotograma %u): %zu -> %lu bytes", epoch, frame, raw.size(),
          static_cast<unsigned long>(cap));
  return send_msg(kState, w);
}

// --- Entradas (lockstep) -----------------------------------------------------

void write_input(Writer& w, const PadInput& in) {
  w.u16(in.buttons);
  for (int16_t a : in.analog) w.u16(static_cast<uint16_t>(a));
}

PadInput read_input(Reader& r) {
  PadInput in;
  in.buttons = r.u16();
  for (auto& a : in.analog) a = static_cast<int16_t>(r.u16());
  return in;
}

// Requiere n.m. Envía por UDP las entradas locales que al otro aún le faltan.
void send_inputs_locked() {
  if (!valid(n.udp) || !n.peer_udp_known) return;
  int64_t first = std::max<int64_t>(n.peer_needs, n.local_last - 63);
  first = std::max<int64_t>(first, 0);
  int64_t count = n.local_last - first + 1;
  if (count < 0) count = 0;
  Writer w;
  w.u32(kUdpMagic);
  w.u32(n.session);
  w.u32(static_cast<uint32_t>(n.remote_contig + 1));  // lo que necesitamos de él
  w.u32(static_cast<uint32_t>(first));
  w.u16(static_cast<uint16_t>(count));
  for (int64_t f = first; f < first + count; ++f) write_input(w, n.local[f % kRing].in);
  sock::send_to(n.udp, w.b.data(), w.b.size(), n.peer_udp);
  n.last_input_send = Clock::now();
}

void handle_udp(const uint8_t* data, size_t size) {
  Reader r(data, size);
  if (r.u32() != kUdpMagic) return;
  std::lock_guard<std::mutex> lock(n.m);
  if (r.u32() != n.session) return;
  int64_t needs = r.u32();
  int64_t first = r.u32();
  uint16_t count = r.u16();
  if (!r.ok) return;
  n.peer_needs = std::max(n.peer_needs, needs);
  for (uint16_t k = 0; k < count; ++k) {
    PadInput in = read_input(r);
    if (!r.ok) break;
    int64_t f = first + k;
    if (f <= n.remote_contig) continue;  // ya la teníamos
    auto& slot = n.remote[f % kRing];
    slot.frame = f;
    slot.in = in;
    n.remote_latest = std::max(n.remote_latest, f);
  }
  while (n.remote[(n.remote_contig + 1) % kRing].frame == n.remote_contig + 1) ++n.remote_contig;
  n.last_rx = Clock::now();
  n.cv.notify_all();
}

// Requiere n.m. Reinicia las entradas al empezar: los primeros `delay`
// fotogramas no tienen pulsaciones de nadie.
void reset_inputs_locked() {
  for (auto& s : n.local) s = RingSlot{};
  for (auto& s : n.remote) s = RingSlot{};
  for (int f = 0; f < n.delay; ++f) {
    n.local[f].frame = f;
    n.remote[f].frame = f;
  }
  n.local_last = n.delay - 1;
  n.remote_contig = n.delay - 1;
  n.remote_latest = n.delay - 1;
  n.peer_needs = 0;
  n.frame = 0;
  n.host_crc.clear();
  n.client_crc.clear();
}

// Requiere n.m (anfitrión). Compara huellas del mismo fotograma.
void compare_checks_locked() {
  for (auto it = n.client_crc.begin(); it != n.client_crc.end();) {
    auto h = n.host_crc.find(it->first);
    if (h == n.host_crc.end()) {
      ++it;
      continue;
    }
    if (h->second != it->second) {
      NET_LOG("Desincronización en el fotograma %u (%08x != %08x)", it->first, h->second, it->second);
      if (++n.mismatch_streak > 3) {
        // El estado del núcleo incluye datos que nunca coinciden: no tiene
        // sentido resincronizar sin fin.
        NET_LOG("Comprobación de huellas desactivada para este núcleo");
        n.checks_enabled = false;
      } else {
        n.resync_wanted = true;
      }
    } else {
      n.mismatch_streak = 0;
      NET_LOG("Huella del fotograma %u correcta", it->first);
    }
    n.host_crc.erase(h);
    it = n.client_crc.erase(it);
  }
  // Limpieza de huellas antiguas sin pareja.
  while (n.host_crc.size() > 16) n.host_crc.erase(n.host_crc.begin());
  while (n.client_crc.size() > 16) n.client_crc.erase(n.client_crc.begin());
}

// --- Mensajes TCP --------------------------------------------------------------

void handle_message(uint8_t type, const uint8_t* data, size_t size) {
  Reader r(data, size);
  n.last_rx = Clock::now();
  switch (type) {
    case kState: {
      ReceivedState st;
      st.epoch = r.u32();
      st.frame = r.u32();
      uint32_t raw = r.u32();
      size_t zsize;
      const uint8_t* z = r.rest(&zsize);
      if (!r.ok || raw == 0 || raw > kMaxMessage) return;
      st.data.resize(raw);
      uLongf out = raw;
      if (uncompress(st.data.data(), &out, z, static_cast<uLong>(zsize)) != Z_OK || out != raw) {
        NET_LOG("Estado recibido dañado");
        return;
      }
      NET_LOG("Estado recibido (época %u, fotograma %u, %u bytes)", st.epoch, st.frame, raw);
      std::lock_guard<std::mutex> lock(n.m);
      n.pending_state = std::move(st);
      n.have_pending_state = true;
      n.cv.notify_all();
      break;
    }
    case kStateAck: {
      uint32_t epoch = r.u32();
      std::lock_guard<std::mutex> lock(n.m);
      if (n.waiting_ack && epoch == n.epoch) {
        n.waiting_ack = false;
        if (n.phase.load() == kSyncing) n.phase.store(kPlaying);
        NET_LOG("El invitado cargó el estado (época %u)", epoch);
      }
      n.cv.notify_all();
      break;
    }
    case kCheck: {
      uint32_t epoch = r.u32();
      uint32_t frame = r.u32();
      uint32_t crc = r.u32();
      std::lock_guard<std::mutex> lock(n.m);
      if (!r.ok || epoch != n.epoch || !n.checks_enabled) return;  // de antes de una resincronización
      n.client_crc[frame] = crc;
      compare_checks_locked();
      break;
    }
    case kPacketMsg: {
      uint16_t from = r.u16();
      size_t len;
      const uint8_t* p = r.rest(&len);
      std::lock_guard<std::mutex> lock(n.m);
      n.packets.emplace_back(from, std::vector<uint8_t>(p, p + len));
      break;
    }
    case kPing: {
      Writer w;
      w.u64(r.u64());
      send_msg(kPong, w);
      break;
    }
    case kPong: {
      uint64_t t = r.u64();
      if (r.ok) n.rtt_ms.store(static_cast<int32_t>((now_ns() - t) / 1000000));
      break;
    }
    case kPause:
      n.remote_paused.store(r.u8() != 0);
      {
        std::lock_guard<std::mutex> lock(n.m);
        n.cv.notify_all();
      }
      break;
    case kBye: {
      std::string why = r.str();
      fail(kDisconnected, why.empty() ? "Tu amigo salió de la partida" : why);
      break;
    }
    default:
      break;
  }
}

// Lee del socket TCP y procesa los mensajes completos. false = conexión cerrada.
bool pump_tcp(std::vector<uint8_t>& rx) {
  uint8_t buf[65536];
  sock::io_t got = sock::recv_bytes(n.tcp, buf, sizeof(buf));
  if (got == 0) return false;
  if (got < 0) {
    int err = sock::last_error();
    return err == sock::kErrIntr || err == sock::kErrAgain;
  }
  rx.insert(rx.end(), buf, buf + got);
  size_t pos = 0;
  while (rx.size() - pos >= 5) {
    Reader h(rx.data() + pos, 4);
    uint32_t len = h.u32();
    if (len == 0 || len > kMaxMessage) return false;
    if (rx.size() - pos - 4 < len) break;
    handle_message(rx[pos + 4], rx.data() + pos + 5, len - 1);
    pos += 4 + len;
  }
  rx.erase(rx.begin(), rx.begin() + static_cast<std::ptrdiff_t>(pos));
  return true;
}

// Espera un mensaje concreto durante el handshake (bloqueante, con plazo).
bool wait_message(uint8_t want, std::vector<uint8_t>& body, int timeout_ms) {
  std::vector<uint8_t> rx;
  auto deadline = Clock::now() + std::chrono::milliseconds(timeout_ms);
  while (!n.stop.load()) {
    while (rx.size() >= 5) {
      Reader h(rx.data(), 4);
      uint32_t len = h.u32();
      if (len == 0 || len > 65536) return false;
      if (rx.size() - 4 < len) break;
      uint8_t type = rx[4];
      if (type == want) {
        body.assign(rx.begin() + 5, rx.begin() + 4 + len);
        return true;
      }
      if (type == kPing) {
        // El anfitrión mide la latencia durante el saludo: se responde al momento.
        Writer pong;
        pong.bytes(rx.data() + 5, len - 1);
        send_msg(kPong, pong);
      }
      rx.erase(rx.begin(), rx.begin() + 4 + len);
    }
    int left = static_cast<int>(
        std::chrono::duration_cast<std::chrono::milliseconds>(deadline - Clock::now()).count());
    if (left <= 0) return false;
    pollfd p{n.tcp, POLLIN, 0};
    if (sock::poll_fds(&p, 1, std::min(left, 200)) <= 0) continue;
    uint8_t buf[4096];
    sock::io_t got = sock::recv_bytes(n.tcp, buf, sizeof(buf));
    if (got <= 0) return false;
    rx.insert(rx.end(), buf, buf + got);
  }
  return false;
}

void configure_tcp(sock_t fd) {
  sock::set_int(fd, IPPROTO_TCP, TCP_NODELAY, 1);
  sock::set_int(fd, SOL_SOCKET, SO_SNDBUF, 1 << 20);
  sock::set_int(fd, SOL_SOCKET, SO_RCVBUF, 1 << 20);
}

sock_t open_udp(int port) {
  sock_t fd = socket(AF_INET, SOCK_DGRAM, 0);
  if (!valid(fd)) return sock::kNone;
  sock::set_int(fd, SOL_SOCKET, SO_REUSEADDR, 1);
  sock::set_nonblocking(fd, true);  // se lee hasta vaciarlo
  sockaddr_in a{};
  a.sin_family = AF_INET;
  a.sin_addr.s_addr = htonl(INADDR_ANY);
  a.sin_port = htons(static_cast<uint16_t>(port));
  if (bind(fd, reinterpret_cast<sockaddr*>(&a), sizeof(a)) != 0) {
    sock::close_socket(fd);
    return sock::kNone;
  }
  return fd;
}

int udp_port_of(sock_t fd) {
  sockaddr_in a{};
  socklen_t len = sizeof(a);
  if (getsockname(fd, reinterpret_cast<sockaddr*>(&a), &len) != 0) return 0;
  return ntohs(a.sin_port);
}

// --- Handshake -------------------------------------------------------------------

bool host_handshake() {
  // Espera al invitado.
  while (!n.stop.load()) {
    pollfd p[2] = {{n.listen_fd, POLLIN, 0}, {n.wake[0], POLLIN, 0}};
    if (sock::poll_fds(p, 2, 500) <= 0) continue;
    if (p[1].revents) return false;
    sockaddr_in from{};
    socklen_t len = sizeof(from);
    sock_t fd = accept(n.listen_fd, reinterpret_cast<sockaddr*>(&from), &len);
    if (!valid(fd)) continue;
    configure_tcp(fd);
    {
      std::lock_guard<std::mutex> lock(n.send_mutex);
      n.tcp = fd;
    }
    std::vector<uint8_t> body;
    if (!wait_message(kHello, body, 5000)) {
      NET_LOG("Conexión sin saludo válido; se descarta");
      std::lock_guard<std::mutex> lock(n.send_mutex);
      close_fd(n.tcp);
      continue;
    }
    Reader r(body.data(), body.size());
    uint32_t magic = r.u32();
    uint16_t proto = r.u16();
    uint8_t mode = r.u8();
    std::string token = r.str();
    std::string game = r.str();
    std::string core = r.str();
    uint16_t udp_port = r.u16();
    std::string reject;
    if (!r.ok || magic != kMagic) reject = "Conexión no válida";
    else if (proto != kProtocol) reject = "Las dos apps tienen versiones distintas de RetroStation";
    else if (!n.cfg.token.empty() && token != n.cfg.token) reject = "Esta partida es privada";
    else if (mode != wire_mode()) reject = "El tipo de partida no coincide";
    else if (core != n.cfg.core_id) reject = "El emulador no coincide (" + core + " / " + n.cfg.core_id + ")";
    else if (n.cfg.mode == kLockstep && game != n.cfg.game_key) reject = "Los juegos no coinciden";
    if (reject.empty() && n.cfg.mode == kLockstep) {
      // Margen de entrada según la red: cada pulsación debe llegar antes de
      // que el otro la necesite. Con la peor latencia de 5 medidas:
      // fotogramas = latencia / 16,7 ms + 1, entre el valor pedido y 8.
      int worst = 0;
      for (int i = 0; i < 5; ++i) {
        Writer ping;
        const uint64_t t0 = now_ns();
        ping.u64(t0);
        send_msg(kPing, ping);
        std::vector<uint8_t> pong;
        if (!wait_message(kPong, pong, 1000)) {
          worst = 1000;
          break;
        }
        worst = std::max(worst, static_cast<int>((now_ns() - t0) / 1000000));
      }
      int delay = std::clamp(worst * 60 / 1000 + 1 + (worst * 60 % 1000 ? 1 : 0), n.cfg.delay, 8);
      {
        std::lock_guard<std::mutex> lock(n.m);
        n.delay = delay;
      }
      n.rtt_ms.store(worst);
      NET_LOG("Latencia en el saludo: %d ms -> retraso de %d fotogramas", worst, delay);
    }
    Writer w;
    w.u8(reject.empty() ? 1 : 0);
    w.str(reject);
    w.u8(static_cast<uint8_t>(n.delay));
    w.u32(n.session);
    send_msg(kWelcome, w);
    if (!reject.empty()) {
      NET_LOG("Invitado rechazado: %s", reject.c_str());
      std::lock_guard<std::mutex> lock(n.send_mutex);
      close_fd(n.tcp);
      continue;
    }
    n.peer_udp = from;
    n.peer_udp.sin_port = htons(udp_port);
    n.peer_udp_known = true;
    char ip[INET_ADDRSTRLEN] = "?";
    inet_ntop(AF_INET, &from.sin_addr, ip, sizeof(ip));
    NET_LOG("Invitado conectado desde %s", ip);
    close_fd(n.listen_fd);  // solo un invitado
    return true;
  }
  return false;
}

bool client_handshake() {
  addrinfo hints{};
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  addrinfo* res = nullptr;
  std::string port = std::to_string(n.cfg.port);
  if (getaddrinfo(n.cfg.address.c_str(), port.c_str(), &hints, &res) != 0 || !res) {
    fail(kFailed, "Dirección no válida: " + n.cfg.address);
    return false;
  }
  sockaddr_in addr = *reinterpret_cast<sockaddr_in*>(res->ai_addr);
  freeaddrinfo(res);

  // El anfitrión puede estar aún cargando su juego: se reintenta un rato.
  sock_t fd = sock::kNone;
  const auto give_up = Clock::now() + std::chrono::seconds(20);
  for (;;) {
    fd = socket(AF_INET, SOCK_STREAM, 0);
    sock::set_nonblocking(fd, true);
    int rc = connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr));
    if (rc != 0 && sock::last_error() == sock::kErrInProgress) {
      pollfd p{fd, POLLOUT, 0};
      rc = sock::poll_fds(&p, 1, 3000) == 1 ? 0 : -1;
      if (rc == 0 && sock::get_int(fd, SOL_SOCKET, SO_ERROR) != 0) rc = -1;
    }
    if (rc == 0) break;
    sock::close_socket(fd);
    fd = sock::kNone;
    if (n.stop.load()) return false;
    if (Clock::now() > give_up) {
      fail(kFailed, "No se pudo conectar con " + n.cfg.address + ". ¿Estáis en la misma Wi-Fi?");
      return false;
    }
    pollfd w{n.wake[0], POLLIN, 0};
    if (sock::poll_fds(&w, 1, 500) > 0) return false;  // cancelado
  }
  sock::set_nonblocking(fd, false);
  configure_tcp(fd);
  {
    std::lock_guard<std::mutex> lock(n.send_mutex);
    n.tcp = fd;
  }
  Writer w;
  w.u32(kMagic);
  w.u16(kProtocol);
  w.u8(wire_mode());
  w.str(n.cfg.token);
  w.str(n.cfg.game_key);
  w.str(n.cfg.core_id);
  w.u16(static_cast<uint16_t>(valid(n.udp) ? udp_port_of(n.udp) : 0));
  send_msg(kHello, w);
  std::vector<uint8_t> body;
  if (!wait_message(kWelcome, body, 6000)) {
    fail(kFailed, "El anfitrión no respondió");
    return false;
  }
  Reader r(body.data(), body.size());
  bool ok = r.u8() != 0;
  std::string reason = r.str();
  uint8_t delay = r.u8();
  uint32_t session = r.u32();
  if (!r.ok || !ok) {
    fail(kFailed, reason.empty() ? "El anfitrión rechazó la conexión" : reason);
    return false;
  }
  {
    std::lock_guard<std::mutex> lock(n.m);
    n.delay = std::clamp<int>(delay, 1, 10);
    n.session = session;
  }
  n.peer_udp = addr;  // mismo puerto para UDP en el anfitrión
  n.peer_udp_known = true;
  NET_LOG("Conectado al anfitrión %s (retraso %d)", n.cfg.address.c_str(), n.delay);
  return true;
}

// --- Hilo de red -------------------------------------------------------------------

void net_thread() {
  bool ok = is_host() ? host_handshake() : client_handshake();
  if (!ok) {
    if (n.phase.load() == kConnecting) fail(kFailed, "Partida cancelada");
    return;
  }
  {
    std::lock_guard<std::mutex> lock(n.m);
    reset_inputs_locked();
    n.last_rx = Clock::now();
  }
  // Sin estado inicial (GBA Link) se juega directamente desde el fotograma 0.
  set_phase(n.cfg.mode == kLockstep && !n.cfg.fresh ? kSyncing : kPlaying);

  std::vector<uint8_t> rx;
  auto last_ping = Clock::time_point{};
  while (!n.stop.load()) {
    // Sin UDP (modo paquetes) solo se vigilan TCP y el aviso de parada.
    pollfd p[3] = {{n.tcp, POLLIN, 0}, {n.wake[0], POLLIN, 0}, {n.udp, POLLIN, 0}};
    const size_t count = valid(n.udp) ? 3 : 2;
    int rc = sock::poll_fds(p, count, 100);
    if (rc < 0 && sock::last_error() != sock::kErrIntr) break;
    if (p[0].revents & (POLLIN | POLLHUP | POLLERR)) {
      if (!pump_tcp(rx)) {
        if (n.phase.load() != kDisconnected) fail(kDisconnected, "Se perdió la conexión con tu amigo");
        break;
      }
    }
    if (valid(n.udp) && (p[2].revents & POLLIN)) {
      uint8_t buf[2048];
      for (;;) {
        sock::io_t got = sock::recv_bytes(n.udp, buf, sizeof(buf));
        if (got <= 0) break;
        handle_udp(buf, static_cast<size_t>(got));
      }
    }
    auto now = Clock::now();
    if (now - last_ping > std::chrono::seconds(1)) {
      Writer w;
      w.u64(now_ns());
      send_msg(kPing, w);
      last_ping = now;
    }
    if (now - n.last_rx > kTimeout) {
      fail(kDisconnected, "Tu amigo dejó de responder");
      break;
    }
  }
}

}  // namespace

// --- API ---------------------------------------------------------------------------

int32_t start(const Config& config) {
  stop();
  n.cfg = config;
  n.stop.store(false);
  {
    std::lock_guard<std::mutex> lock(n.m);
    n.message.clear();
    n.delay = std::clamp(config.delay, 1, 10);
    n.session = static_cast<uint32_t>(now_ns() ^ (now_ns() >> 29));
    n.epoch = 0;
    n.state_sent = false;
    n.waiting_ack = false;
    n.resync_wanted = false;
    n.have_pending_state = false;
    n.resyncs = 0;
    n.mismatch_streak = 0;
    n.checks_enabled = true;
    n.stalling = false;
    n.packets.clear();
    n.packet_peer_connected = false;
    reset_inputs_locked();
  }
  n.rtt_ms.store(-1);
  n.remote_paused.store(false);
  n.peer_udp_known = false;
  if (!sock::init() || !sock::wake_open(n.wake)) return RS_ERR_IO;

  if (config.mode == kLockstep) {
    n.udp = open_udp(config.host ? config.port : 0);
    if (!valid(n.udp)) {
      fail(kFailed, "No se pudo abrir el puerto UDP " + std::to_string(config.port));
      return RS_ERR_IO;
    }
  }
  if (config.host) {
    n.listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    sock::set_int(n.listen_fd, SOL_SOCKET, SO_REUSEADDR, 1);
    sockaddr_in a{};
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_ANY);
    a.sin_port = htons(static_cast<uint16_t>(config.port));
    if (bind(n.listen_fd, reinterpret_cast<sockaddr*>(&a), sizeof(a)) != 0 ||
        listen(n.listen_fd, 1) != 0) {
      close_fd(n.listen_fd);
      close_fd(n.udp);
      fail(kFailed, "El puerto " + std::to_string(config.port) + " está ocupado");
      return RS_ERR_IO;
    }
  }
  set_phase(kConnecting);
  NET_LOG("%s partida (%s, puerto %d)", config.host ? "Creando" : "Uniéndose a",
          config.mode == kLockstep ? "juego compartido" : "link", config.port);
  n.thread = std::thread(net_thread);
  return RS_OK;
}

void stop() {
  if (n.thread.joinable() || valid(n.tcp)) {
    if (n.phase.load() == kPlaying || n.phase.load() == kSyncing) {
      Writer w;
      w.str("Tu amigo salió de la partida");
      send_msg(kBye, w);
    }
    n.stop.store(true);
    sock::wake_signal(n.wake);
    {
      std::lock_guard<std::mutex> lock(n.send_mutex);
      if (valid(n.tcp)) shutdown(n.tcp, sock::kShutBoth);
    }
    if (n.thread.joinable()) n.thread.join();
  }
  {
    std::lock_guard<std::mutex> lock(n.send_mutex);
    close_fd(n.tcp);
  }
  close_fd(n.listen_fd);
  close_fd(n.udp);
  close_fd(n.wake[0]);
  close_fd(n.wake[1]);
  n.peer_udp_known = false;
  if (n.phase.load() != kOff) NET_LOG("Multijugador detenido");
  n.phase.store(kOff);
  n.cv.notify_all();
}

Phase phase() { return static_cast<Phase>(n.phase.load()); }
Mode mode() { return n.cfg.mode; }

bool lockstep_active() {
  int32_t p = n.phase.load();
  return n.cfg.mode == kLockstep && (p == kConnecting || p == kSyncing || p == kPlaying);
}

Status status() {
  Status s{};
  s.phase = n.phase.load();
  s.mode = n.cfg.mode;
  s.player = local_player();
  s.rtt_ms = n.rtt_ms.load();
  s.remote_paused = n.remote_paused.load() ? 1 : 0;
  std::lock_guard<std::mutex> lock(n.m);
  s.stalled = n.stalling && Clock::now() - n.stall_since > std::chrono::milliseconds(250) ? 1 : 0;
  s.resyncs = n.resyncs;
  s.frame = static_cast<int32_t>(n.frame);
  return s;
}

std::string message() {
  std::lock_guard<std::mutex> lock(n.m);
  return n.message;
}

void set_local_paused(bool paused) {
  if (n.local_paused.exchange(paused) == paused) return;
  int32_t p = n.phase.load();
  if (p == kPlaying || p == kSyncing) {
    Writer w;
    w.u8(paused ? 1 : 0);
    send_msg(kPause, w);
  }
}

// --- Lockstep ----------------------------------------------------------------------

Step begin_frame(const PadInput& local, const Hooks& hooks, PadInput out[2], bool* behind) {
  *behind = false;
  std::unique_lock<std::mutex> lock(n.m);
  const int32_t p = n.phase.load();
  if (p == kConnecting) {
    lock.unlock();
    std::this_thread::sleep_for(std::chrono::milliseconds(8));
    return Step::kWait;
  }

  // Estado inicial o resincronización.
  if (is_host()) {
    bool send = (p == kSyncing && !n.state_sent) || (p == kPlaying && n.resync_wanted && !n.waiting_ack);
    if (send) {
      uint32_t frame = static_cast<uint32_t>(n.frame);
      lock.unlock();
      std::vector<uint8_t> raw;
      bool ok = hooks.save(raw);
      lock.lock();
      if (!ok) {
        lock.unlock();
        fail(kDisconnected, "Este juego no se puede sincronizar (el núcleo no guarda estados)");
        return Step::kWait;
      }
      uint32_t epoch = ++n.epoch;
      n.state_sent = true;
      n.waiting_ack = true;
      if (p == kPlaying) ++n.resyncs;
      n.resync_wanted = false;
      n.host_crc.clear();
      n.client_crc.clear();
      lock.unlock();
      send_state(epoch, frame, raw);
      lock.lock();
    }
    if (n.waiting_ack) {
      send_inputs_locked();
      n.cv.wait_for(lock, std::chrono::milliseconds(5));
      return Step::kWait;
    }
  } else if (n.have_pending_state) {
    ReceivedState st = std::move(n.pending_state);
    n.have_pending_state = false;
    lock.unlock();
    bool ok = hooks.load(st.data);
    lock.lock();
    if (!ok) {
      lock.unlock();
      fail(kDisconnected, "No se pudo cargar el estado del anfitrión (¿versión del núcleo distinta?)");
      return Step::kWait;
    }
    n.frame = st.frame;
    n.epoch = st.epoch;
    n.client_crc.clear();
    if (n.phase.load() == kPlaying) ++n.resyncs;
    n.phase.store(kPlaying);
    Writer w;
    w.u32(st.epoch);
    lock.unlock();
    send_msg(kStateAck, w);
    lock.lock();
  }
  if (n.phase.load() != kPlaying) {
    n.cv.wait_for(lock, std::chrono::milliseconds(5));
    return Step::kWait;
  }

  // La entrada local se decide una sola vez por fotograma; los huecos (tras una
  // resincronización) se rellenan con la pulsación actual.
  const int64_t target = n.frame + n.delay;
  while (n.local_last < target) {
    ++n.local_last;
    auto& slot = n.local[n.local_last % kRing];
    slot.frame = n.local_last;
    slot.in = local;
  }
  send_inputs_locked();

  auto ready = [] {
    return n.remote[n.frame % kRing].frame == n.frame && n.local[n.frame % kRing].frame == n.frame;
  };
  if (!ready()) {
    // Esperar un poco; si no llega, el bucle vuelve a llamar (y reenvía).
    n.cv.wait_for(lock, std::chrono::milliseconds(4), ready);
    if (!ready()) {
      if (!n.stalling) {
        n.stalling = true;
        n.stall_since = Clock::now();
      }
      return Step::kWait;
    }
  }
  n.stalling = false;
  out[local_player()] = n.local[n.frame % kRing].in;
  out[1 - local_player()] = n.remote[n.frame % kRing].in;
  *behind = n.remote_latest > n.frame + n.delay + 1;
  return Step::kRun;
}

void end_frame(const Hooks& hooks) {
  std::unique_lock<std::mutex> lock(n.m);
  ++n.frame;
  if (n.frame % kCheckInterval != 0 || !n.checks_enabled || n.phase.load() != kPlaying) return;
  uint32_t frame = static_cast<uint32_t>(n.frame);
  uint32_t epoch = n.epoch;
  if (n.cfg.fresh) return;  // sin estados no hay huella que comparar
  lock.unlock();
  std::vector<uint8_t> raw;
  if (!hooks.save(raw)) return;
  uint32_t crc = crc_of(raw);
  // Solo para pruebas (rs_netplay_test): simula una desincronización.
  static bool forced = false;
  if (!is_host() && !forced && getenv("RS_NET_FORCE_DESYNC")) {
    forced = true;
    crc ^= 1;
  }
  if (is_host()) {
    lock.lock();
    if (epoch == n.epoch) {
      n.host_crc[frame] = crc;
      compare_checks_locked();
    }
  } else {
    Writer w;
    w.u32(epoch);
    w.u32(frame);
    w.u32(crc);
    send_msg(kCheck, w);
  }
}

// --- Paquetes ----------------------------------------------------------------------

namespace {

void packet_send_cb(int /*flags*/, const void* buf, size_t len, uint16_t /*client_id*/) {
  // Con dos jugadores, todo paquete (directo o difusión) va al otro.
  if (!buf || len == 0 || n.phase.load() != kPlaying) return;
  Writer w;
  w.u16(static_cast<uint16_t>(local_player()));
  w.bytes(buf, len);
  send_msg(kPacketMsg, w);
}

void deliver_packets() {
  if (!n.iface || !n.iface->receive) return;
  for (;;) {
    std::pair<uint16_t, std::vector<uint8_t>> pkt;
    {
      std::lock_guard<std::mutex> lock(n.m);
      if (n.packets.empty()) return;
      pkt = std::move(n.packets.front());
      n.packets.pop_front();
    }
    n.iface->receive(pkt.second.data(), pkt.second.size(), pkt.first);
  }
}

void packet_poll_receive_cb() { deliver_packets(); }

}  // namespace

void set_packet_interface(const retro_netpacket_callback* iface) { n.iface = iface; }
bool packet_interface_available() { return n.iface != nullptr; }

void packet_frame() {
  if (!n.iface || n.cfg.mode != kPacket) return;
  const int32_t p = n.phase.load();
  if (!n.packet_started) {
    // El anfitrión empieza la sesión antes de que llegue nadie; el invitado,
    // cuando ya está conectado (así lo define libretro).
    bool can_start = is_host() ? (p == kConnecting || p == kPlaying) : p == kPlaying;
    if (!can_start) return;
    n.iface->start(static_cast<uint16_t>(local_player()), packet_send_cb, packet_poll_receive_cb);
    n.packet_started = true;
    NET_LOG("Sesión de link iniciada en el núcleo (jugador %d)", local_player() + 1);
  }
  if (is_host() && p == kPlaying && !n.packet_peer_connected) {
    n.packet_peer_connected = true;
    if (n.iface->connected && !n.iface->connected(1)) {
      fail(kDisconnected, "El juego no admite más jugadores en este modo");
      return;
    }
  }
  if (p == kPlaying) {
    deliver_packets();
    if (n.iface->poll) n.iface->poll();
    return;
  }
  if (p == kDisconnected || p == kFailed || p == kOff) packet_shutdown();
}

void packet_shutdown() {
  if (!n.iface || !n.packet_started) return;
  if (is_host() && n.packet_peer_connected && n.iface->disconnected) n.iface->disconnected(1);
  if (n.iface->stop) n.iface->stop();
  n.packet_started = false;
  n.packet_peer_connected = false;
  NET_LOG("Sesión de link terminada en el núcleo");
}

}  // namespace rs::net
