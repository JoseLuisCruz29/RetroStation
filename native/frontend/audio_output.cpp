#include "audio_output.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <type_traits>

#ifdef __ANDROID__
#include <SLES/OpenSLES.h>
#include <SLES/OpenSLES_Android.h>
#include <aaudio/AAudio.h>
#include <android/log.h>
#include <dlfcn.h>
#define AUDIO_LOG(...) __android_log_print(ANDROID_LOG_INFO, "RetroStation", __VA_ARGS__)
#else
#define AUDIO_LOG(...)
#endif

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <audioclient.h>
#include <mmdeviceapi.h>

#include <future>
#include <thread>
#endif

#ifdef __APPLE__
#include <AudioToolbox/AudioToolbox.h>
#include <TargetConditionals.h>
#endif

namespace rs {

// --- StereoRing --------------------------------------------------------------

size_t StereoRing::write(const int16_t* frames, size_t count) {
  size_t free_frames = capacity_ - available();
  size_t n = std::min(count, free_frames);
  size_t w = write_.load();
  for (size_t i = 0; i < n; ++i) {
    size_t idx = ((w + i) % capacity_) * 2;
    data_[idx] = frames[i * 2];
    data_[idx + 1] = frames[i * 2 + 1];
  }
  write_.store(w + n);
  return n;
}

size_t StereoRing::read(int16_t* out, size_t count) {
  size_t n = std::min(count, available());
  size_t r = read_.load();
  for (size_t i = 0; i < n; ++i) {
    size_t idx = ((r + i) % capacity_) * 2;
    out[i * 2] = data_[idx];
    out[i * 2 + 1] = data_[idx + 1];
  }
  read_.store(r + n);
  return n;
}

// --- Resampler ---------------------------------------------------------------

void Resampler::configure(double input_rate, double output_rate) {
  base_ratio_ = output_rate / input_rate;
  position_ = 0.0;
  prev_[0] = prev_[1] = 0;
}

void Resampler::process(const int16_t* in, size_t frames, StereoRing& ring) {
  if (frames == 0) return;
  // DRC: objetivo = buffer medio lleno. Desviación máxima ±0,5 %.
  constexpr double kMaxDelta = 0.005;
  double fill = static_cast<double>(ring.available()) / ring.capacity();
  double ratio = base_ratio_ * (1.0 + kMaxDelta * (1.0 - 2.0 * fill));
  double step = 1.0 / ratio;  // avance en la entrada por cada muestra de salida

  scratch_.clear();
  scratch_.reserve(static_cast<size_t>(frames * ratio + 4) * 2);
  // Interpola entre prev_ (muestra -1) y las muestras de entrada.
  while (true) {
    size_t i = static_cast<size_t>(position_);
    if (i >= frames) break;
    double t = position_ - i;
    const int16_t* a = i == 0 ? prev_ : &in[(i - 1) * 2];
    const int16_t* b = &in[i * 2];
    for (int c = 0; c < 2; ++c) {
      scratch_.push_back(static_cast<int16_t>(a[c] + (b[c] - a[c]) * t));
    }
    position_ += step;
  }
  position_ -= static_cast<double>(frames);
  prev_[0] = in[(frames - 1) * 2];
  prev_[1] = in[(frames - 1) * 2 + 1];
  ring.write(scratch_.data(), scratch_.size() / 2);
}

// --- AudioOutput -------------------------------------------------------------

#ifdef __ANDROID__
namespace {

// AAudio existe desde Android 8.0 (API 26). La app admite Android 7.0, así que
// no se enlaza: se carga en tiempo de ejecución y, si no está, se usa OpenSL ES.
struct AAudioApi {
  bool loaded = false;
  aaudio_result_t (*createStreamBuilder)(AAudioStreamBuilder**);
  void (*setDirection)(AAudioStreamBuilder*, aaudio_direction_t);
  void (*setFormat)(AAudioStreamBuilder*, aaudio_format_t);
  void (*setChannelCount)(AAudioStreamBuilder*, int32_t);
  void (*setPerformanceMode)(AAudioStreamBuilder*, aaudio_performance_mode_t);
  void (*setSharingMode)(AAudioStreamBuilder*, aaudio_sharing_mode_t);
  void (*setDataCallback)(AAudioStreamBuilder*, AAudioStream_dataCallback, void*);
  aaudio_result_t (*openStream)(AAudioStreamBuilder*, AAudioStream**);
  aaudio_result_t (*deleteBuilder)(AAudioStreamBuilder*);
  const char* (*resultToText)(aaudio_result_t);
  int32_t (*getSampleRate)(AAudioStream*);
  int32_t (*getBufferSizeInFrames)(AAudioStream*);
  aaudio_result_t (*requestStart)(AAudioStream*);
  aaudio_result_t (*requestPause)(AAudioStream*);
  aaudio_result_t (*requestStop)(AAudioStream*);
  aaudio_result_t (*close)(AAudioStream*);
};

const AAudioApi& aaudio() {
  static AAudioApi api = [] {
    AAudioApi a{};
    void* lib = dlopen("libaaudio.so", RTLD_NOW | RTLD_LOCAL);
    if (!lib) return a;
    bool ok = true;
    auto sym = [&](auto& fn, const char* name) {
      fn = reinterpret_cast<std::remove_reference_t<decltype(fn)>>(dlsym(lib, name));
      ok = ok && fn != nullptr;
    };
    sym(a.createStreamBuilder, "AAudio_createStreamBuilder");
    sym(a.setDirection, "AAudioStreamBuilder_setDirection");
    sym(a.setFormat, "AAudioStreamBuilder_setFormat");
    sym(a.setChannelCount, "AAudioStreamBuilder_setChannelCount");
    sym(a.setPerformanceMode, "AAudioStreamBuilder_setPerformanceMode");
    sym(a.setSharingMode, "AAudioStreamBuilder_setSharingMode");
    sym(a.setDataCallback, "AAudioStreamBuilder_setDataCallback");
    sym(a.openStream, "AAudioStreamBuilder_openStream");
    sym(a.deleteBuilder, "AAudioStreamBuilder_delete");
    sym(a.resultToText, "AAudio_convertResultToText");
    sym(a.getSampleRate, "AAudioStream_getSampleRate");
    sym(a.getBufferSizeInFrames, "AAudioStream_getBufferSizeInFrames");
    sym(a.requestStart, "AAudioStream_requestStart");
    sym(a.requestPause, "AAudioStream_requestPause");
    sym(a.requestStop, "AAudioStream_requestStop");
    sym(a.close, "AAudioStream_close");
    a.loaded = ok;
    return a;
  }();
  return api;
}

aaudio_data_callback_result_t data_callback(AAudioStream*, void* user, void* audio,
                                            int32_t frames) {
  static_cast<AudioOutput*>(user)->render(static_cast<int16_t*>(audio), frames);
  return AAUDIO_CALLBACK_RESULT_CONTINUE;
}

void sl_callback(SLAndroidSimpleBufferQueueItf, void* user) {
  static_cast<AudioOutput*>(user)->opensl_enqueue_next();
}

}  // namespace
#endif

bool AudioOutput::open(double core_sample_rate) {
  close();
#ifdef __ANDROID__
  if (open_aaudio(core_sample_rate)) return true;
  return open_opensl(core_sample_rate);
#elif defined(_WIN32)
  return open_wasapi(core_sample_rate);
#elif defined(__APPLE__)
  return open_coreaudio(core_sample_rate);
#else
  (void)core_sample_rate;
  return false;
#endif
}

bool AudioOutput::open_aaudio(double core_sample_rate) {
#ifdef __ANDROID__
  const AAudioApi& a = aaudio();
  if (!a.loaded) return false;
  AAudioStreamBuilder* builder = nullptr;
  if (a.createStreamBuilder(&builder) != AAUDIO_OK) return false;
  a.setDirection(builder, AAUDIO_DIRECTION_OUTPUT);
  a.setFormat(builder, AAUDIO_FORMAT_PCM_I16);
  a.setChannelCount(builder, 2);
  a.setPerformanceMode(builder, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
  a.setSharingMode(builder, AAUDIO_SHARING_MODE_SHARED);
  a.setDataCallback(builder, data_callback, this);
  AAudioStream* stream = nullptr;
  aaudio_result_t res = a.openStream(builder, &stream);
  a.deleteBuilder(builder);
  if (res != AAUDIO_OK) {
    AUDIO_LOG("AAudio no disponible: %s", a.resultToText(res));
    return false;
  }
  output_rate_ = a.getSampleRate(stream);
  resampler_.configure(core_sample_rate, output_rate_);
  ring_.clear();
  stream_ = stream;
  backend_ = Backend::aaudio;
  a.requestStart(stream);
  AUDIO_LOG("Audio (AAudio): %.0f Hz -> %d Hz, buffer %d frames", core_sample_rate,
            output_rate_, a.getBufferSizeInFrames(stream));
  return true;
#else
  (void)core_sample_rate;
  return false;
#endif
}

bool AudioOutput::open_opensl(double core_sample_rate) {
#ifdef __ANDROID__
  SLObjectItf engine_obj = nullptr;
  if (slCreateEngine(&engine_obj, 0, nullptr, 0, nullptr, nullptr) != SL_RESULT_SUCCESS) {
    AUDIO_LOG("OpenSL ES no disponible");
    return false;
  }
  sl_engine_obj_ = engine_obj;
  SLEngineItf engine = nullptr;
  SLObjectItf mix_obj = nullptr;
  SLObjectItf player_obj = nullptr;
  SLPlayItf play = nullptr;
  SLAndroidSimpleBufferQueueItf queue = nullptr;
  bool ok = (*engine_obj)->Realize(engine_obj, SL_BOOLEAN_FALSE) == SL_RESULT_SUCCESS &&
            (*engine_obj)->GetInterface(engine_obj, SL_IID_ENGINE, &engine) == SL_RESULT_SUCCESS &&
            (*engine)->CreateOutputMix(engine, &mix_obj, 0, nullptr, nullptr) == SL_RESULT_SUCCESS;
  if (ok) {
    sl_mix_obj_ = mix_obj;
    ok = (*mix_obj)->Realize(mix_obj, SL_BOOLEAN_FALSE) == SL_RESULT_SUCCESS;
  }
  if (ok) {
    // 48 kHz estéreo 16 bits: lo admiten todos los dispositivos; el
    // remuestreador adapta la frecuencia del núcleo.
    SLDataLocator_AndroidSimpleBufferQueue loc_queue = {
        SL_DATALOCATOR_ANDROIDSIMPLEBUFFERQUEUE, kSlBuffers};
    SLDataFormat_PCM pcm = {SL_DATAFORMAT_PCM,        2,
                            SL_SAMPLINGRATE_48,       SL_PCMSAMPLEFORMAT_FIXED_16,
                            SL_PCMSAMPLEFORMAT_FIXED_16,
                            SL_SPEAKER_FRONT_LEFT | SL_SPEAKER_FRONT_RIGHT,
                            SL_BYTEORDER_LITTLEENDIAN};
    SLDataSource source = {&loc_queue, &pcm};
    SLDataLocator_OutputMix loc_mix = {SL_DATALOCATOR_OUTPUTMIX, mix_obj};
    SLDataSink sink = {&loc_mix, nullptr};
    const SLInterfaceID ids[] = {SL_IID_ANDROIDSIMPLEBUFFERQUEUE};
    const SLboolean req[] = {SL_BOOLEAN_TRUE};
    ok = (*engine)->CreateAudioPlayer(engine, &player_obj, &source, &sink, 1, ids, req) ==
         SL_RESULT_SUCCESS;
  }
  if (ok) {
    sl_player_obj_ = player_obj;
    ok = (*player_obj)->Realize(player_obj, SL_BOOLEAN_FALSE) == SL_RESULT_SUCCESS &&
         (*player_obj)->GetInterface(player_obj, SL_IID_PLAY, &play) == SL_RESULT_SUCCESS &&
         (*player_obj)->GetInterface(player_obj, SL_IID_ANDROIDSIMPLEBUFFERQUEUE, &queue) ==
             SL_RESULT_SUCCESS &&
         (*queue)->RegisterCallback(queue, sl_callback, this) == SL_RESULT_SUCCESS;
  }
  if (!ok) {
    AUDIO_LOG("No se pudo abrir OpenSL ES");
    stream_ = this;  // para que close() libere lo creado
    backend_ = Backend::opensl;
    close();
    return false;
  }
  sl_play_ = play;
  sl_queue_ = queue;
  output_rate_ = 48000;
  resampler_.configure(core_sample_rate, output_rate_);
  ring_.clear();
  stream_ = this;
  backend_ = Backend::opensl;
  sl_next_ = 0;
  // Se ceban todas las colas con silencio; cada vez que una termina, el
  // callback la rellena con audio real.
  for (int i = 0; i < kSlBuffers; ++i) opensl_enqueue_next();
  (*play)->SetPlayState(play, SL_PLAYSTATE_PLAYING);
  AUDIO_LOG("Audio (OpenSL ES): %.0f Hz -> %d Hz, %d x %d frames", core_sample_rate,
            output_rate_, kSlBuffers, kSlFrames);
  return true;
#else
  (void)core_sample_rate;
  return false;
#endif
}

// --- Windows (WASAPI) --------------------------------------------------------

#ifdef _WIN32
struct AudioOutput::WasapiState {
  std::thread thread;
  std::atomic<bool> stop{false};
  std::atomic<bool> paused{false};
};

namespace {
template <typename T>
void release(T*& p) {
  if (p) p->Release();
  p = nullptr;
}
}  // namespace

// Todo el trabajo con COM se hace en el hilo de audio: modo compartido con
// evento, 48 kHz estéreo de 16 bits (Windows convierte al formato del
// dispositivo) y un búfer de unos 40 ms.
bool AudioOutput::open_wasapi(double core_sample_rate) {
  auto* st = new WasapiState;
  std::promise<bool> ready;
  auto started = ready.get_future();
  st->thread = std::thread([this, st, &ready] {
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    IMMDeviceEnumerator* enumerator = nullptr;
    IMMDevice* device = nullptr;
    IAudioClient* client = nullptr;
    IAudioRenderClient* render_client = nullptr;
    HANDLE event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    UINT32 buffer_frames = 0;
    WAVEFORMATEX fmt{};
    fmt.wFormatTag = WAVE_FORMAT_PCM;
    fmt.nChannels = 2;
    fmt.nSamplesPerSec = 48000;
    fmt.wBitsPerSample = 16;
    fmt.nBlockAlign = 4;
    fmt.nAvgBytesPerSec = 48000 * 4;
    bool ok =
        event &&
        SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                   __uuidof(IMMDeviceEnumerator), reinterpret_cast<void**>(&enumerator))) &&
        SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device)) &&
        SUCCEEDED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                   reinterpret_cast<void**>(&client))) &&
        SUCCEEDED(client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                                     AUDCLNT_STREAMFLAGS_EVENTCALLBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM |
                                         AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
                                     400000 /* 40 ms en unidades de 100 ns */, 0, &fmt, nullptr)) &&
        SUCCEEDED(client->SetEventHandle(event)) && SUCCEEDED(client->GetBufferSize(&buffer_frames)) &&
        SUCCEEDED(client->GetService(__uuidof(IAudioRenderClient), reinterpret_cast<void**>(&render_client))) &&
        SUCCEEDED(client->Start());
    ready.set_value(ok);
    while (ok && !st->stop.load()) {
      if (WaitForSingleObject(event, 100) != WAIT_OBJECT_0) continue;
      UINT32 padding = 0;
      if (FAILED(client->GetCurrentPadding(&padding))) break;
      UINT32 frames = buffer_frames - padding;
      if (frames == 0) continue;
      BYTE* data = nullptr;
      if (FAILED(render_client->GetBuffer(frames, &data))) break;
      if (st->paused.load()) {
        render_client->ReleaseBuffer(frames, AUDCLNT_BUFFERFLAGS_SILENT);
      } else {
        render(reinterpret_cast<int16_t*>(data), static_cast<int32_t>(frames));
        render_client->ReleaseBuffer(frames, 0);
      }
    }
    if (client) client->Stop();
    release(render_client);
    release(client);
    release(device);
    release(enumerator);
    if (event) CloseHandle(event);
    CoUninitialize();
  });
  if (!started.get()) {
    st->stop.store(true);
    st->thread.join();
    delete st;
    return false;
  }
  output_rate_ = 48000;
  resampler_.configure(core_sample_rate, output_rate_);
  ring_.clear();
  wasapi_ = st;
  stream_ = this;
  backend_ = Backend::wasapi;
  return true;
}
#else
bool AudioOutput::open_wasapi(double) { return false; }
#endif

// --- iPhone (CoreAudio, unidad RemoteIO) -----------------------------------------
// El sistema llama a rs_coreaudio_render desde su hilo de audio con el búfer
// que hay que rellenar: 48 kHz, estéreo, 16 bits intercalados (iOS convierte
// al formato del altavoz o los auriculares).

#ifdef __APPLE__
namespace {
OSStatus rs_coreaudio_render(void* ref, AudioUnitRenderActionFlags*, const AudioTimeStamp*, UInt32,
                             UInt32 frames, AudioBufferList* io) {
  auto* self = static_cast<AudioOutput*>(ref);
  self->render(static_cast<int16_t*>(io->mBuffers[0].mData), static_cast<int32_t>(frames));
  return noErr;
}
}  // namespace

bool AudioOutput::open_coreaudio(double core_sample_rate) {
  AudioComponentDescription desc{};
  desc.componentType = kAudioUnitType_Output;
#if TARGET_OS_IPHONE
  desc.componentSubType = kAudioUnitSubType_RemoteIO;
#else
  desc.componentSubType = kAudioUnitSubType_DefaultOutput;
#endif
  desc.componentManufacturer = kAudioUnitManufacturer_Apple;
  AudioComponent comp = AudioComponentFindNext(nullptr, &desc);
  AudioUnit unit = nullptr;
  if (!comp || AudioComponentInstanceNew(comp, &unit) != noErr) return false;

  AudioStreamBasicDescription fmt{};
  fmt.mSampleRate = 48000;
  fmt.mFormatID = kAudioFormatLinearPCM;
  fmt.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
  fmt.mBytesPerPacket = 4;
  fmt.mFramesPerPacket = 1;
  fmt.mBytesPerFrame = 4;
  fmt.mChannelsPerFrame = 2;
  fmt.mBitsPerChannel = 16;
  AURenderCallbackStruct cb{rs_coreaudio_render, this};
  if (AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fmt,
                           sizeof(fmt)) != noErr ||
      AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb,
                           sizeof(cb)) != noErr ||
      AudioUnitInitialize(unit) != noErr) {
    AudioComponentInstanceDispose(unit);
    return false;
  }
  output_rate_ = 48000;
  resampler_.configure(core_sample_rate, output_rate_);
  ring_.clear();
  stream_ = unit;
  backend_ = Backend::coreaudio;
  AudioOutputUnitStart(unit);
  return true;
}
#else
bool AudioOutput::open_coreaudio(double) { return false; }
#endif

void AudioOutput::opensl_enqueue_next() {
#ifdef __ANDROID__
  auto queue = static_cast<SLAndroidSimpleBufferQueueItf>(sl_queue_);
  if (!queue) return;
  int16_t* buf = sl_buffers_[sl_next_];
  sl_next_ = (sl_next_ + 1) % kSlBuffers;
  render(buf, kSlFrames);
  (*queue)->Enqueue(queue, buf, sizeof(sl_buffers_[0]));
#endif
}

void AudioOutput::close() {
#ifdef __APPLE__
  if (stream_) {
    auto unit = static_cast<AudioUnit>(stream_);
    AudioOutputUnitStop(unit);  // espera a que termine el callback en curso
    AudioUnitUninitialize(unit);
    AudioComponentInstanceDispose(unit);
  }
  stream_ = nullptr;
  backend_ = Backend::none;
#endif
#ifdef _WIN32
  if (wasapi_) {
    wasapi_->stop.store(true);
    if (wasapi_->thread.joinable()) wasapi_->thread.join();
    delete wasapi_;
    wasapi_ = nullptr;
  }
  stream_ = nullptr;
  backend_ = Backend::none;
#endif
#ifdef __ANDROID__
  if (!stream_) return;
  if (backend_ == Backend::aaudio) {
    auto* stream = static_cast<AAudioStream*>(stream_);
    aaudio().requestStop(stream);
    aaudio().close(stream);
  } else if (backend_ == Backend::opensl) {
    if (auto play = static_cast<SLPlayItf>(sl_play_)) {
      (*play)->SetPlayState(play, SL_PLAYSTATE_STOPPED);
    }
    // Destroy espera a que termine el callback en curso.
    if (auto o = static_cast<SLObjectItf>(sl_player_obj_)) (*o)->Destroy(o);
    if (auto o = static_cast<SLObjectItf>(sl_mix_obj_)) (*o)->Destroy(o);
    if (auto o = static_cast<SLObjectItf>(sl_engine_obj_)) (*o)->Destroy(o);
    sl_player_obj_ = sl_mix_obj_ = sl_engine_obj_ = nullptr;
    sl_play_ = sl_queue_ = nullptr;
  }
  stream_ = nullptr;
  backend_ = Backend::none;
#endif
}

void AudioOutput::set_paused(bool paused) {
#ifdef __APPLE__
  if (stream_) {
    auto unit = static_cast<AudioUnit>(stream_);
    if (paused) {
      AudioOutputUnitStop(unit);
      ring_.clear();
    } else {
      AudioOutputUnitStart(unit);
    }
  }
  return;
#endif
#ifdef _WIN32
  if (wasapi_) {
    if (paused) ring_.clear();
    wasapi_->paused.store(paused);
  }
  return;
#endif
#ifdef __ANDROID__
  if (!stream_) return;
  if (backend_ == Backend::aaudio) {
    auto* stream = static_cast<AAudioStream*>(stream_);
    if (paused) {
      aaudio().requestPause(stream);
      ring_.clear();
    } else {
      aaudio().requestStart(stream);
    }
  } else if (backend_ == Backend::opensl) {
    auto play = static_cast<SLPlayItf>(sl_play_);
    if (paused) ring_.clear();
    (*play)->SetPlayState(play, paused ? SL_PLAYSTATE_PAUSED : SL_PLAYSTATE_PLAYING);
  }
#else
  (void)paused;
#endif
}

void AudioOutput::push(const int16_t* frames, size_t count) {
  if (!stream_) return;
  std::lock_guard<std::mutex> lock(push_mutex_);
  resampler_.process(frames, count, ring_);
}

void AudioOutput::render(int16_t* out, int32_t frames) {
  size_t got = ring_.read(out, static_cast<size_t>(frames));
  if (got < static_cast<size_t>(frames)) {
    // Subdesbordamiento: silencio en lugar de ruido.
    std::memset(out + got * 2, 0, (frames - got) * 2 * sizeof(int16_t));
  }
  float vol = muted_.load() ? 0.0f : volume_.load();
  if (vol < 0.999f) {
    for (int32_t i = 0; i < frames * 2; ++i) {
      out[i] = static_cast<int16_t>(out[i] * vol);
    }
  }
}

}  // namespace rs
