#include "gamepad_input.h"

#include <mmsystem.h>

#include <chrono>
#include <cmath>

namespace {

std::string Utf8(const std::wstring& w) {
  if (w.empty()) return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), static_cast<int>(w.size()), nullptr, 0, nullptr, nullptr);
  std::string s(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.c_str(), static_cast<int>(w.size()), s.data(), n, nullptr, nullptr);
  return s;
}

double Normalize(DWORD value, UINT min, UINT max) {
  if (max <= min) return 0;
  return (static_cast<double>(value) - min) / (static_cast<double>(max) - min) * 2.0 - 1.0;
}

}  // namespace

GamepadInput::GamepadInput(flutter::FlutterEngine* engine, HWND window) : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(), "retrostation/gamepad", &flutter::StandardMethodCodec::GetInstance());
  thread_ = std::thread([this] { Run(); });
}

GamepadInput::~GamepadInput() {
  running_ = false;
  if (thread_.joinable()) thread_.join();
}

bool GamepadInput::Read(UINT id, Pad& pad) {
  JOYINFOEX info{sizeof(info), JOY_RETURNALL};
  if (joyGetPosEx(id, &info) != JOYERR_NOERROR) return false;
  const auto& c = pad.caps;
  std::array<double, 6> axes{
      Normalize(info.dwXpos, c.wXmin, c.wXmax), Normalize(info.dwYpos, c.wYmin, c.wYmax),
      Normalize(info.dwZpos, c.wZmin, c.wZmax), Normalize(info.dwRpos, c.wRmin, c.wRmax),
      Normalize(info.dwUpos, c.wUmin, c.wUmax), Normalize(info.dwVpos, c.wVmin, c.wVmax),
  };
  const int pov = info.dwPOV > 36000 ? -1 : static_cast<int>(info.dwPOV);
  bool changed = info.dwButtons != pad.buttons || pov != pad.pov;
  for (size_t i = 0; i < axes.size(); ++i) {
    if (std::fabs(axes[i] - pad.axes[i]) > 0.02) changed = true;
  }
  if (changed) {
    pad.buttons = info.dwButtons;
    pad.pov = pov;
    pad.axes = axes;
    pad.dirty = true;
  }
  return true;
}

void GamepadInput::ScanHid() {
  const auto paths = NintendoHid::Enumerate();
  for (const auto& path : paths) {
    bool open = false;
    for (const auto& h : hid_) open |= h && h->path() == path;
    if (open) continue;
    for (size_t i = 0; i < hid_.size(); ++i) {
      if (hid_[i]) continue;
      auto dev = std::make_unique<NintendoHid>();
      if (!dev->Open(path)) break;
      hid_[i] = std::move(dev);
      Pad& pad = pads_[kHidFirst + i];
      pad = Pad{};
      pad.connected = true;
      pad.name = L"Pro Controller";
      pad.vid = NintendoHid::kVendor;
      pad.pid = NintendoHid::kProController;
      pad.dirty = true;
      break;
    }
  }
}

bool GamepadInput::ReadHid(int slot, Pad& pad) {
  auto& dev = hid_[slot - kHidFirst];
  if (!dev) return false;
  NintendoState s;
  s.buttons = pad.buttons;
  s.pov = pad.pov;
  s.lx = pad.axes[0];
  s.ly = pad.axes[1];
  const NintendoState before = s;
  if (!dev->Poll(s)) {
    dev.reset();
    return false;
  }
  if (!(s == before)) {
    pad.buttons = s.buttons;
    pad.pov = s.pov;
    pad.axes = {s.lx, s.ly, 0, 0, 0, 0};
    pad.dirty = true;
  }
  return true;
}

void GamepadInput::Scan() {
  ScanHid();
  const UINT count = std::min<UINT>(joyGetNumDevs(), static_cast<UINT>(kHidFirst));
  for (UINT id = 0; id < count; ++id) {
    Pad& pad = pads_[id];
    if (pad.connected) continue;
    JOYINFOEX info{sizeof(info), JOY_RETURNBUTTONS};
    if (joyGetPosEx(id, &info) != JOYERR_NOERROR) continue;
    pad = Pad{};
    if (joyGetDevCapsW(id, &pad.caps, sizeof(pad.caps)) != JOYERR_NOERROR) continue;
    // Los mandos de Nintendo se leen por HID (ScanHid). Además, Windows deja
    // aquí un mando "fantasma" emparejado pero desconectado que nunca cambia.
    if (pad.caps.wMid == NintendoHid::kVendor) {
      pad = Pad{};
      continue;
    }
    pad.connected = true;
    pad.name = pad.caps.szPname;
    pad.vid = pad.caps.wMid;
    pad.pid = pad.caps.wPid;
    pad.dirty = true;
    Read(id, pad);
  }
}

void GamepadInput::Run() {
  timeBeginPeriod(1);
  auto next_scan = std::chrono::steady_clock::now();
  while (running_) {
    const auto now = std::chrono::steady_clock::now();
    // Mandos nuevos: cada 2 s (preguntar por ranuras vacías es lento).
    if (now >= next_scan) {
      Scan();
      next_scan = now + std::chrono::seconds(2);
    }
    bool any = false;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      for (int id = 0; id < static_cast<int>(pads_.size()); ++id) {
        Pad& pad = pads_[id];
        if (!pad.connected) continue;
        const bool ok = id >= kHidFirst ? ReadHid(id, pad) : Read(id, pad);
        if (!ok) {
          pad = Pad{};
          pad.dirty = true;  // desconectado
        }
        if (pad.dirty) {
          pending_.emplace_back(id, pad);
          pad.dirty = false;
          any = true;
        }
      }
    }
    if (any && !posted_.exchange(true)) PostMessage(window_, kMessage, 0, 0);
    Sleep(4);
  }
  timeEndPeriod(1);
}

void GamepadInput::Flush() {
  std::vector<std::pair<int, Pad>> changes;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    changes.swap(pending_);
    posted_ = false;
  }
  // Solo el último estado de cada mando.
  for (size_t i = 0; i < changes.size(); ++i) {
    bool newer = false;
    for (size_t j = i + 1; j < changes.size(); ++j) newer |= changes[j].first == changes[i].first;
    if (newer) continue;
    const auto& [id, pad] = changes[i];
    flutter::EncodableMap m{{flutter::EncodableValue("id"), flutter::EncodableValue(id)},
                            {flutter::EncodableValue("connected"), flutter::EncodableValue(pad.connected)}};
    if (pad.connected) {
      flutter::EncodableList axes;
      for (double a : pad.axes) axes.emplace_back(a);
      m[flutter::EncodableValue("name")] = flutter::EncodableValue(Utf8(pad.name));
      m[flutter::EncodableValue("vid")] = flutter::EncodableValue(pad.vid);
      m[flutter::EncodableValue("pid")] = flutter::EncodableValue(pad.pid);
      m[flutter::EncodableValue("buttons")] = flutter::EncodableValue(static_cast<int64_t>(pad.buttons));
      m[flutter::EncodableValue("pov")] = flutter::EncodableValue(pad.pov);
      m[flutter::EncodableValue("axes")] = flutter::EncodableValue(axes);
    }
    channel_->InvokeMethod("state", std::make_unique<flutter::EncodableValue>(m));
  }
}
