// Pro Controller de Switch leído directamente por HID (como hacen SDL o
// Steam), con o sin Steam abierto.
//
// La API de joystick de Windows solo entiende el modo "simple" del mando
// (informe 0x3F). Steam lo cambia al modo completo de Nintendo (informe 0x30,
// 60 veces por segundo) y entonces Windows ya no ve ninguna pulsación. Aquí se
// leen los dos formatos y, al abrir el mando, se pide el modo completo y se
// enciende la luz del jugador 1 (deja de parpadear).
//
// Los botones se devuelven en el orden del modo simple, el mismo que usa Dart
// (lib/controllers/gamepad.dart): B, A, Y, X, L, R, ZL, ZR, −, +, L3, R3,
// Home, Captura.
#pragma once

#include <windows.h>
#include <hidsdi.h>
#include <setupapi.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string>
#include <vector>

struct NintendoState {
  uint32_t buttons = 0;
  int pov = -1;  // centésimas de grado, -1 = suelta
  double lx = 0, ly = 0;  // -1..1, y hacia abajo
  double rx = 0, ry = 0;  // joystick derecho
  bool operator==(const NintendoState& o) const {
    return buttons == o.buttons && pov == o.pov && std::abs(lx - o.lx) < 0.02 &&
           std::abs(ly - o.ly) < 0.02 && std::abs(rx - o.rx) < 0.02 && std::abs(ry - o.ry) < 0.02;
  }
};

class NintendoHid {
 public:
  static constexpr USHORT kVendor = 0x057e;
  static constexpr USHORT kProController = 0x2009;

  ~NintendoHid() { Close(); }

  // Rutas HID de los Pro Controller conectados.
  static std::vector<std::wstring> Enumerate() {
    std::vector<std::wstring> paths;
    GUID guid;
    HidD_GetHidGuid(&guid);
    HDEVINFO set = SetupDiGetClassDevsW(&guid, nullptr, nullptr, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
    if (set == INVALID_HANDLE_VALUE) return paths;
    SP_DEVICE_INTERFACE_DATA iface{sizeof(iface)};
    for (DWORD i = 0; SetupDiEnumDeviceInterfaces(set, nullptr, &guid, i, &iface); ++i) {
      DWORD size = 0;
      SetupDiGetDeviceInterfaceDetailW(set, &iface, nullptr, 0, &size, nullptr);
      std::vector<BYTE> buf(size);
      auto* detail = reinterpret_cast<SP_DEVICE_INTERFACE_DETAIL_DATA_W*>(buf.data());
      detail->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W);
      if (!SetupDiGetDeviceInterfaceDetailW(set, &iface, detail, size, nullptr, nullptr)) continue;
      HANDLE h = CreateFileW(detail->DevicePath, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0,
                             nullptr);
      if (h == INVALID_HANDLE_VALUE) continue;
      HIDD_ATTRIBUTES attr{sizeof(attr)};
      if (HidD_GetAttributes(h, &attr) && attr.VendorID == kVendor && attr.ProductID == kProController) {
        paths.emplace_back(detail->DevicePath);
      }
      CloseHandle(h);
    }
    SetupDiDestroyDeviceInfoList(set);
    return paths;
  }

  bool Open(const std::wstring& path) {
    path_ = path;
    handle_ = CreateFileW(path.c_str(), GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                          OPEN_EXISTING, FILE_FLAG_OVERLAPPED, nullptr);
    if (handle_ == INVALID_HANDLE_VALUE) return false;
    PHIDP_PREPARSED_DATA pre = nullptr;
    if (HidD_GetPreparsedData(handle_, &pre)) {
      HIDP_CAPS caps{};
      HidP_GetCaps(pre, &caps);
      in_len_ = caps.InputReportByteLength;
      out_len_ = caps.OutputReportByteLength;
      HidD_FreePreparsedData(pre);
    }
    if (in_len_ == 0) in_len_ = 362;
    if (out_len_ == 0) out_len_ = 49;
    in_.assign(in_len_, 0);
    read_ov_.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    Subcommand(0x03, 0x30);  // modo completo (informe 0x30)
    Subcommand(0x30, 0x01);  // luz del jugador 1 fija
    return true;
  }

  void Close() {
    if (handle_ != INVALID_HANDLE_VALUE) {
      CancelIoEx(handle_, nullptr);
      if (pending_) {
        DWORD n;
        GetOverlappedResult(handle_, &read_ov_, &n, TRUE);
      }
      CloseHandle(handle_);
    }
    if (read_ov_.hEvent) CloseHandle(read_ov_.hEvent);
    handle_ = INVALID_HANDLE_VALUE;
    read_ov_ = {};
    pending_ = false;
  }

  const std::wstring& path() const { return path_; }

  // Diagnóstico: informes recibidos y tipo del último.
  int reports = 0;
  int last_id = -1;
  USHORT input_length() const { return in_len_; }
  USHORT output_length() const { return out_len_; }

  // Lee los informes que hayan llegado (sin esperar). Devuelve false si el
  // mando se ha desconectado.
  bool Poll(NintendoState& state) {
    for (int i = 0; i < 16; ++i) {
      if (!pending_) {
        ResetEvent(read_ov_.hEvent);
        if (ReadFile(handle_, in_.data(), in_len_, nullptr, &read_ov_) || GetLastError() == ERROR_IO_PENDING) {
          pending_ = true;
        } else {
          return false;
        }
      }
      DWORD n = 0;
      if (!GetOverlappedResult(handle_, &read_ov_, &n, FALSE)) {
        if (GetLastError() == ERROR_IO_INCOMPLETE) return true;  // aún no hay más
        return false;
      }
      pending_ = false;
      ++reports;
      last_id = n > 0 ? in_[0] : -1;
      Parse(in_.data(), n, state);
    }
    return true;
  }

 private:
  static double Axis12(int v) { return std::clamp((v - 2048) / 1550.0, -1.0, 1.0); }
  static double Axis16(int v) { return std::clamp((v - 32768) / 32768.0, -1.0, 1.0); }

  static int PovFrom(bool up, bool down, bool left, bool right) {
    if (up && right) return 4500;
    if (down && right) return 13500;
    if (down && left) return 22500;
    if (up && left) return 31500;
    if (up) return 0;
    if (right) return 9000;
    if (down) return 18000;
    if (left) return 27000;
    return -1;
  }

  static void Parse(const uint8_t* r, DWORD n, NintendoState& s) {
    if (n >= 12 && (r[0] == 0x30 || r[0] == 0x21)) {
      const uint8_t right = r[3], shared = r[4], left = r[5];
      uint32_t b = 0;
      auto set = [&](int bit, bool on) { if (on) b |= 1u << bit; };
      set(0, right & 0x04);  // B
      set(1, right & 0x08);  // A
      set(2, right & 0x01);  // Y
      set(3, right & 0x02);  // X
      set(4, left & 0x40);   // L
      set(5, right & 0x40);  // R
      set(6, left & 0x80);   // ZL
      set(7, right & 0x80);  // ZR
      set(8, shared & 0x01);   // −
      set(9, shared & 0x02);   // +
      set(10, shared & 0x08);  // L3
      set(11, shared & 0x04);  // R3
      set(12, shared & 0x10);  // Home
      set(13, shared & 0x20);  // Captura
      s.buttons = b;
      s.pov = PovFrom(left & 0x02, left & 0x01, left & 0x08, left & 0x04);
      const int x = r[6] | ((r[7] & 0x0F) << 8);
      const int y = (r[7] >> 4) | (r[8] << 4);
      s.lx = Axis12(x);
      s.ly = -Axis12(y);  // en el mando, arriba es más
      const int rxv = r[9] | ((r[10] & 0x0F) << 8);
      const int ryv = (r[10] >> 4) | (r[11] << 4);
      s.rx = Axis12(rxv);
      s.ry = -Axis12(ryv);
    } else if (n >= 12 && r[0] == 0x3F) {
      s.buttons = r[1] | (r[2] << 8);
      const int hat = r[3];
      static const int kHat[] = {0, 4500, 9000, 13500, 18000, 22500, 27000, 31500};
      s.pov = hat < 8 ? kHat[hat] : -1;
      s.lx = Axis16(r[4] | (r[5] << 8));
      s.ly = Axis16(r[6] | (r[7] << 8));
      if (n >= 12) {
        s.rx = Axis16(r[8] | (r[9] << 8));
        s.ry = Axis16(r[10] | (r[11] << 8));
      }
    }
  }

  void Subcommand(uint8_t command, uint8_t arg) {
    std::vector<uint8_t> out(std::max<USHORT>(out_len_, 12), 0);
    static const uint8_t kNeutralRumble[8] = {0x00, 0x01, 0x40, 0x40, 0x00, 0x01, 0x40, 0x40};
    out[0] = 0x01;
    out[1] = counter_++ & 0x0F;
    std::copy(std::begin(kNeutralRumble), std::end(kNeutralRumble), out.begin() + 2);
    out[10] = command;
    out[11] = arg;
    OVERLAPPED ov{};
    ov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    DWORD n = 0;
    if (!WriteFile(handle_, out.data(), static_cast<DWORD>(out.size()), nullptr, &ov) &&
        GetLastError() == ERROR_IO_PENDING) {
      if (WaitForSingleObject(ov.hEvent, 200) != WAIT_OBJECT_0) CancelIoEx(handle_, &ov);
      GetOverlappedResult(handle_, &ov, &n, TRUE);
    }
    CloseHandle(ov.hEvent);
    Sleep(30);  // el mando necesita un momento entre órdenes
  }

  std::wstring path_;
  HANDLE handle_ = INVALID_HANDLE_VALUE;
  OVERLAPPED read_ov_{};
  bool pending_ = false;
  std::vector<uint8_t> in_;
  USHORT in_len_ = 0, out_len_ = 0;
  uint8_t counter_ = 0;
};
