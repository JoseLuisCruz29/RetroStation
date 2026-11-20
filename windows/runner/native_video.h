// Imagen del emulador en Windows: el motor nativo (retrostation_native.dll)
// avisa de cada fotograma nuevo y Flutter lo copia como textura de píxeles.
// Canal "retrostation/video", igual que en Android (MainActivity.kt).
#pragma once

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include <memory>
#include <mutex>
#include <vector>

class NativeVideo {
 public:
  explicit NativeVideo(flutter::FlutterEngine* engine);
  ~NativeVideo();

 private:
  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  int64_t Create();
  void Release();
  const FlutterDesktopPixelBuffer* CopyFrame(size_t width, size_t height);
  static void OnFrame(void* self);

  flutter::PluginRegistrarWindows* registrar_ = nullptr;
  flutter::TextureRegistrar* textures_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::TextureVariant> texture_;
  int64_t texture_id_ = -1;

  // Funciones del motor (la DLL que también usa Dart por FFI).
  using CopyFn = int32_t (*)(uint8_t*, int32_t, int32_t*, int32_t*);
  using SetCallbackFn = void (*)(void (*)(void*), void*);
  CopyFn copy_frame_ = nullptr;
  SetCallbackFn set_frame_callback_ = nullptr;

  std::vector<uint8_t> pixels_;
  FlutterDesktopPixelBuffer buffer_{};
};
