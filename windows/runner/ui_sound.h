// Efectos de sonido de la interfaz en Windows (canal "retrostation/sfx", igual
// que en Android). Los WAV (PCM de 16 bits) se copian junto a la app en
// data/sfx y se reproducen con PlaySound, aplicando el volumen pedido.
#pragma once

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <map>
#include <memory>
#include <string>
#include <vector>

class UiSound {
 public:
  explicit UiSound(flutter::FlutterEngine* engine);

 private:
  void Play(const std::string& name, double volume);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::map<std::string, std::vector<uint8_t>> sounds_;  // WAV completo
  std::vector<uint8_t> playing_;  // copia con el volumen aplicado (debe vivir mientras suena)
};
