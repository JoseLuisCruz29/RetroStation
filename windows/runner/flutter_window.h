#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "gamepad_input.h"
#include "native_video.h"
#include "ui_sound.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 // Pantalla completa sin bordes (F11) o vuelta a la ventana.
  void ToggleFullscreen();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Canal "retrostation/video".
  std::unique_ptr<NativeVideo> native_video_;

  // Canal "retrostation/sfx" (sonidos de la interfaz).
  std::unique_ptr<UiSound> ui_sound_;

  // Canal "retrostation/gamepad" (mandos).
  std::unique_ptr<GamepadInput> gamepad_;

  // Canal "retrostation/window": pantalla completa (F11).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> window_channel_;
  bool fullscreen_ = false;
  LONG saved_style_ = 0;
  WINDOWPLACEMENT saved_placement_{sizeof(WINDOWPLACEMENT)};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
