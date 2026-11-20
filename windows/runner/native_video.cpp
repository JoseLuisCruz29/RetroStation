#include "native_video.h"

#include <windows.h>

#include <flutter/plugin_registrar.h>

NativeVideo::NativeVideo(flutter::FlutterEngine* engine) {
  registrar_ = flutter::PluginRegistrarManager::GetInstance()->GetRegistrar<flutter::PluginRegistrarWindows>(
      engine->GetRegistrarForPlugin("RetroStationNativeVideo"));
  textures_ = registrar_->texture_registrar();
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar_->messenger(), "retrostation/video", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) { HandleMethodCall(call, std::move(result)); });

  // La misma DLL que abre Dart: Windows devuelve el módulo ya cargado.
  if (HMODULE lib = LoadLibraryW(L"retrostation_native.dll")) {
    copy_frame_ = reinterpret_cast<CopyFn>(GetProcAddress(lib, "rs_copy_frame"));
    set_frame_callback_ = reinterpret_cast<SetCallbackFn>(GetProcAddress(lib, "rs_set_frame_callback"));
  }
}

NativeVideo::~NativeVideo() { Release(); }

void NativeVideo::HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                                   std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "create") {
    int64_t id = Create();
    if (id < 0) {
      result->Error("video", "No se pudo cargar retrostation_native.dll");
    } else {
      result->Success(flutter::EncodableValue(id));
    }
  } else if (call.method_name() == "release") {
    Release();
    result->Success();
  } else {
    result->NotImplemented();
  }
}

int64_t NativeVideo::Create() {
  Release();
  if (!copy_frame_ || !set_frame_callback_) return -1;
  texture_ = std::make_unique<flutter::TextureVariant>(
      flutter::PixelBufferTexture([this](size_t w, size_t h) { return CopyFrame(w, h); }));
  texture_id_ = textures_->RegisterTexture(texture_.get());
  set_frame_callback_(&NativeVideo::OnFrame, this);
  return texture_id_;
}

void NativeVideo::Release() {
  if (set_frame_callback_) set_frame_callback_(nullptr, nullptr);
  if (texture_id_ >= 0) {
    textures_->UnregisterTexture(texture_id_);
    texture_id_ = -1;
  }
  texture_.reset();
}

// Hilo de emulación: hay fotograma nuevo (MarkTextureFrameAvailable admite
// llamarse desde cualquier hilo).
void NativeVideo::OnFrame(void* self) {
  auto* video = static_cast<NativeVideo*>(self);
  if (video->texture_id_ >= 0) video->textures_->MarkTextureFrameAvailable(video->texture_id_);
}

// Hilo de render de Flutter: copia el último fotograma (RGBA8888).
const FlutterDesktopPixelBuffer* NativeVideo::CopyFrame(size_t, size_t) {
  int32_t w = 0, h = 0;
  int32_t needed = copy_frame_(nullptr, 0, &w, &h);
  if (needed <= 0) return nullptr;
  pixels_.resize(static_cast<size_t>(needed));
  if (copy_frame_(pixels_.data(), needed, &w, &h) != 0) return nullptr;
  buffer_.buffer = pixels_.data();
  buffer_.width = static_cast<size_t>(w);
  buffer_.height = static_cast<size_t>(h);
  return &buffer_;
}
