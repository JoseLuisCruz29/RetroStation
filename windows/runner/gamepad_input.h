// Mandos en Windows (Pro Controller de Switch, mandos de Xbox, genéricos USB o
// Bluetooth...) con la API de joystick de Windows (winmm), que ve cualquier
// mando HID. Los Pro Controller de Switch se leen directamente por HID
// (nintendo_hid.h), porque con Steam abierto la API de Windows no los ve.
//
// Un hilo lee los mandos cada 4 ms y, cuando algo cambia, avisa a la ventana
// (PostMessage). La ventana envía el estado a Dart por el canal
// "retrostation/gamepad" (método "state"), donde se traduce a botones de la
// consola según Ajustes > Mando.
#pragma once

#include <windows.h>

#include "nintendo_hid.h"

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <array>
#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

class GamepadInput {
 public:
  // Mensaje que se envía a la ventana cuando hay cambios.
  static constexpr UINT kMessage = WM_APP + 0x47;

  GamepadInput(flutter::FlutterEngine* engine, HWND window);
  ~GamepadInput();

  // Hilo de la ventana: envía a Dart los cambios pendientes.
  void Flush();

 private:
  struct Pad {
    bool connected = false;
    std::wstring name;
    int vid = 0, pid = 0;
    JOYCAPSW caps{};
    DWORD buttons = 0;
    int pov = -1;  // centésimas de grado, -1 = centrada
    std::array<double, 6> axes{};  // x, y, z, r, u, v en -1..1
    bool dirty = false;
  };

  void Run();
  void Scan();
  bool Read(UINT id, Pad& pad);
  void ScanHid();
  bool ReadHid(int slot, Pad& pad);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND window_;
  std::thread thread_;
  std::atomic<bool> running_{true};
  std::atomic<bool> posted_{false};
  std::mutex mutex_;
  // 0-15: mandos de la API de Windows; 16-19: Pro Controller por HID.
  static constexpr int kHidFirst = 16;
  std::array<Pad, 20> pads_{};      // estado del hilo de lectura
  std::array<std::unique_ptr<NintendoHid>, 4> hid_{};
  std::vector<std::pair<int, Pad>> pending_;  // cambios para la ventana
};
