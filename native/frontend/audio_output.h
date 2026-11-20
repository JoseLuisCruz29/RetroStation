// Salida de audio del frontend: buffer circular + remuestreo con control
// dinámico de velocidad (DRC) para evitar cortes sin desincronizar.
#ifndef RS_AUDIO_OUTPUT_H
#define RS_AUDIO_OUTPUT_H

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <vector>

namespace rs {

// Buffer circular de muestras estéreo int16 (un productor, un consumidor).
class StereoRing {
 public:
  explicit StereoRing(size_t frames) : data_(frames * 2), capacity_(frames) {}

  size_t capacity() const { return capacity_; }
  size_t available() const { return write_.load() - read_.load(); }

  // Devuelve cuántos frames se escribieron (descarta el resto si está lleno).
  size_t write(const int16_t* frames, size_t count);
  // Lee hasta `count` frames; devuelve los leídos.
  size_t read(int16_t* out, size_t count);
  void clear() { read_.store(write_.load()); }

 private:
  std::vector<int16_t> data_;
  size_t capacity_;
  std::atomic<size_t> write_{0};
  std::atomic<size_t> read_{0};
};

// Remuestreador lineal de input_rate a output_rate. El factor se corrige
// ligeramente según el llenado del buffer (técnica DRC de RetroArch).
class Resampler {
 public:
  void configure(double input_rate, double output_rate);
  // Convierte `frames` frames de entrada y los escribe en `ring`.
  void process(const int16_t* in, size_t frames, StereoRing& ring);

 private:
  double base_ratio_ = 1.0;  // salida / entrada
  double position_ = 0.0;    // posición fraccional entre prev_ y la muestra actual
  int16_t prev_[2] = {0, 0};
  std::vector<int16_t> scratch_;
};

class AudioOutput {
 public:
  bool open(double core_sample_rate);
  void close();
  void set_paused(bool paused);
  void set_volume(float volume) { volume_.store(volume); }
  void set_muted(bool muted) { muted_.store(muted); }
  // Llamado desde el hilo de emulación con las muestras del núcleo.
  void push(const int16_t* frames, size_t count);
  bool is_open() const { return stream_ != nullptr; }
  int32_t output_rate() const { return output_rate_; }

  // Llamado desde el hilo de audio del sistema.
  void render(int16_t* out, int32_t frames);

 private:
  bool open_aaudio(double core_sample_rate);
  bool open_opensl(double core_sample_rate);
  bool open_wasapi(double core_sample_rate);  // Windows

 public:
  // Usado por el callback de OpenSL ES: rellena y encola el siguiente bloque.
  void opensl_enqueue_next();

 private:
  enum class Backend { none, aaudio, opensl, wasapi };
  Backend backend_ = Backend::none;
  // Windows: hilo de audio WASAPI (definido en audio_output.cpp).
  struct WasapiState;
  WasapiState* wasapi_ = nullptr;
  void* stream_ = nullptr;  // AAudioStream* o, con OpenSL ES, puntero no nulo de estado
  // OpenSL ES (Android 7.x, donde no existe AAudio).
  const void* sl_engine_obj_ = nullptr;   // SLObjectItf
  const void* sl_mix_obj_ = nullptr;      // SLObjectItf
  const void* sl_player_obj_ = nullptr;   // SLObjectItf
  const void* sl_play_ = nullptr;         // SLPlayItf
  const void* sl_queue_ = nullptr;        // SLAndroidSimpleBufferQueueItf
  static constexpr int kSlBuffers = 3;
  static constexpr int kSlFrames = 512;
  int16_t sl_buffers_[kSlBuffers][kSlFrames * 2] = {};
  int sl_next_ = 0;
  int32_t output_rate_ = 48000;
  StereoRing ring_{8192};
  Resampler resampler_;
  std::mutex push_mutex_;
  std::atomic<float> volume_{1.0f};
  std::atomic<bool> muted_{false};
};

}  // namespace rs

#endif
