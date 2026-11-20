#include "ui_sound.h"

#include <windows.h>
#include <mmsystem.h>

#include <cstring>
#include <fstream>

namespace {

std::wstring ExeDir() {
  wchar_t path[MAX_PATH];
  DWORD n = GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring dir(path, n);
  return dir.substr(0, dir.find_last_of(L"\\/"));
}

std::vector<uint8_t> ReadFile(const std::wstring& path) {
  std::ifstream in(path, std::ios::binary);
  return std::vector<uint8_t>((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
}

// Posición y tamaño de las muestras ("data") dentro de un WAV.
bool FindData(const std::vector<uint8_t>& wav, size_t* offset, size_t* size) {
  if (wav.size() < 12 || std::memcmp(wav.data(), "RIFF", 4) != 0) return false;
  size_t pos = 12;
  while (pos + 8 <= wav.size()) {
    uint32_t len;
    std::memcpy(&len, wav.data() + pos + 4, 4);
    if (std::memcmp(wav.data() + pos, "data", 4) == 0) {
      *offset = pos + 8;
      *size = std::min<size_t>(len, wav.size() - *offset);
      return true;
    }
    pos += 8 + len + (len & 1);
  }
  return false;
}

}  // namespace

UiSound::UiSound(flutter::FlutterEngine* engine) {
  const std::wstring dir = ExeDir() + L"\\data\\sfx\\";
  for (const char* name : {"click", "open", "back", "move", "on"}) {
    std::wstring file = dir + L"sfx_" + std::wstring(name, name + std::strlen(name)) + L".wav";
    auto data = ReadFile(file);
    if (!data.empty()) sounds_[name] = std::move(data);
  }
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(), "retrostation/sfx", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "play") {
      result->NotImplemented();
      return;
    }
    std::string name;
    double volume = 1.0;
    if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
      auto n = args->find(flutter::EncodableValue("name"));
      if (n != args->end()) {
        if (const auto* s = std::get_if<std::string>(&n->second)) name = *s;
      }
      auto v = args->find(flutter::EncodableValue("volume"));
      if (v != args->end()) {
        if (const auto* d = std::get_if<double>(&v->second)) volume = *d;
      }
    }
    Play(name, volume);
    result->Success();
  });
}

void UiSound::Play(const std::string& name, double volume) {
  auto it = sounds_.find(name);
  if (it == sounds_.end()) return;
  // Se para el sonido anterior antes de reutilizar su memoria.
  PlaySoundW(nullptr, nullptr, 0);
  playing_ = it->second;
  size_t offset = 0, size = 0;
  if (FindData(playing_, &offset, &size) && volume < 0.999) {
    auto* samples = reinterpret_cast<int16_t*>(playing_.data() + offset);
    for (size_t i = 0; i < size / 2; ++i) samples[i] = static_cast<int16_t>(samples[i] * volume);
  }
  PlaySoundW(reinterpret_cast<LPCWSTR>(playing_.data()), nullptr, SND_MEMORY | SND_ASYNC | SND_NODEFAULT);
}
