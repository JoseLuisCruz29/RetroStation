// Sockets iguales en Android (POSIX) y Windows (Winsock) para netplay.cpp.
#pragma once

#include <cstddef>
#include <cstdint>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <ws2tcpip.h>

namespace rs::net::sock {

using sock_t = SOCKET;
constexpr sock_t kNone = INVALID_SOCKET;
using io_t = int;
constexpr int kErrIntr = WSAEINTR;
constexpr int kErrAgain = WSAEWOULDBLOCK;
constexpr int kErrInProgress = WSAEWOULDBLOCK;  // connect() sin bloqueo en Winsock
constexpr int kShutBoth = SD_BOTH;

inline bool init() {
  static bool ok = [] {
    WSADATA data;
    return WSAStartup(MAKEWORD(2, 2), &data) == 0;
  }();
  return ok;
}
inline int last_error() { return WSAGetLastError(); }
inline void close_socket(sock_t s) { closesocket(s); }
inline void set_nonblocking(sock_t s, bool on) {
  u_long mode = on ? 1 : 0;
  ioctlsocket(s, FIONBIO, &mode);
}
inline int poll_fds(pollfd* fds, size_t count, int timeout_ms) {
  return WSAPoll(fds, static_cast<ULONG>(count), timeout_ms);
}
inline io_t send_bytes(sock_t s, const void* p, size_t n) {
  return ::send(s, static_cast<const char*>(p), static_cast<int>(n), 0);
}
inline io_t recv_bytes(sock_t s, void* p, size_t n) {
  return ::recv(s, static_cast<char*>(p), static_cast<int>(n), 0);
}
inline io_t send_to(sock_t s, const void* p, size_t n, const sockaddr_in& to) {
  return ::sendto(s, static_cast<const char*>(p), static_cast<int>(n), 0,
                  reinterpret_cast<const sockaddr*>(&to), sizeof(to));
}
inline void set_int(sock_t s, int level, int name, int value) {
  setsockopt(s, level, name, reinterpret_cast<const char*>(&value), sizeof(value));
}
inline int get_int(sock_t s, int level, int name) {
  int value = 0;
  int len = sizeof(value);
  getsockopt(s, level, name, reinterpret_cast<char*>(&value), &len);
  return value;
}

// Despertar el hilo de red: Windows no tiene pipe() para sockets, así que se
// usa un socket UDP de bucle local que se envía un byte a sí mismo.
inline bool wake_open(sock_t w[2]) {
  sock_t s = socket(AF_INET, SOCK_DGRAM, 0);
  if (s == INVALID_SOCKET) return false;
  sockaddr_in a{};
  a.sin_family = AF_INET;
  a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  a.sin_port = 0;
  if (bind(s, reinterpret_cast<sockaddr*>(&a), sizeof(a)) != 0) {
    closesocket(s);
    return false;
  }
  w[0] = s;
  w[1] = INVALID_SOCKET;  // mismo socket: solo hace falta cerrarlo una vez
  return true;
}
inline void wake_signal(sock_t w[2]) {
  if (w[0] == INVALID_SOCKET) return;
  sockaddr_in a{};
  int len = sizeof(a);
  if (getsockname(w[0], reinterpret_cast<sockaddr*>(&a), &len) != 0) return;
  char c = 1;
  sendto(w[0], &c, 1, 0, reinterpret_cast<sockaddr*>(&a), sizeof(a));
}

}  // namespace rs::net::sock

#else
#include <arpa/inet.h>
#include <cerrno>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

namespace rs::net::sock {

using sock_t = int;
constexpr sock_t kNone = -1;
using io_t = ssize_t;
constexpr int kErrIntr = EINTR;
constexpr int kErrAgain = EAGAIN;
constexpr int kErrInProgress = EINPROGRESS;
constexpr int kShutBoth = SHUT_RDWR;

inline bool init() { return true; }
inline int last_error() { return errno; }
inline void close_socket(sock_t s) { close(s); }
inline void set_nonblocking(sock_t s, bool on) {
  int flags = fcntl(s, F_GETFL, 0);
  fcntl(s, F_SETFL, on ? (flags | O_NONBLOCK) : (flags & ~O_NONBLOCK));
}
inline int poll_fds(pollfd* fds, size_t count, int timeout_ms) {
  return poll(fds, static_cast<nfds_t>(count), timeout_ms);
}
inline io_t send_bytes(sock_t s, const void* p, size_t n) { return ::send(s, p, n, MSG_NOSIGNAL); }
inline io_t recv_bytes(sock_t s, void* p, size_t n) { return ::recv(s, p, n, 0); }
inline io_t send_to(sock_t s, const void* p, size_t n, const sockaddr_in& to) {
  return ::sendto(s, p, n, 0, reinterpret_cast<const sockaddr*>(&to), sizeof(to));
}
inline void set_int(sock_t s, int level, int name, int value) {
  setsockopt(s, level, name, &value, sizeof(value));
}
inline int get_int(sock_t s, int level, int name) {
  int value = 0;
  socklen_t len = sizeof(value);
  getsockopt(s, level, name, &value, &len);
  return value;
}
inline bool wake_open(sock_t w[2]) { return pipe(w) == 0; }
inline void wake_signal(sock_t w[2]) {
  if (w[1] < 0) return;
  char c = 1;
  (void)!write(w[1], &c, 1);
}

}  // namespace rs::net::sock
#endif

namespace rs::net::sock {
inline bool valid(sock_t s) { return s != kNone; }
}  // namespace rs::net::sock
