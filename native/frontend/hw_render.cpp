#include "hw_render.h"

#ifdef __ANDROID__

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <android/log.h>
#include <android/native_window.h>
#include <dlfcn.h>

#include <chrono>
#include <condition_variable>
#include <mutex>

#define HW_LOG(prio, ...) __android_log_print(prio, "RetroStation", __VA_ARGS__)

namespace rs::hw {
namespace {

retro_hw_render_callback g_cb{};
bool g_requested = false;

EGLDisplay g_display = EGL_NO_DISPLAY;
EGLConfig g_config = nullptr;
EGLContext g_context = EGL_NO_CONTEXT;
EGLSurface g_pbuffer = EGL_NO_SURFACE;  // superficie mínima mientras no hay ventana
EGLSurface g_surface = EGL_NO_SURFACE;
ANativeWindow* g_window = nullptr;      // referencia propia de la ventana en uso
void* g_gles_lib = nullptr;
bool g_running = false;                 // el contexto existe (hilo de emulación)

GLuint g_fbo = 0;
GLuint g_color = 0;
GLuint g_depth = 0;

// Cambio de superficie pedido desde JNI y aplicado por el hilo de emulación.
std::mutex g_win_mutex;
std::condition_variable g_win_cv;
bool g_pending = false;
ANativeWindow* g_pending_window = nullptr;

uintptr_t current_framebuffer() { return g_fbo; }

retro_proc_address_t proc_address(const char* sym) {
  auto p = reinterpret_cast<retro_proc_address_t>(eglGetProcAddress(sym));
  // En Android antiguos eglGetProcAddress no devuelve las funciones del núcleo
  // de GLES; están en la biblioteca.
  if (!p && g_gles_lib) p = reinterpret_cast<retro_proc_address_t>(dlsym(g_gles_lib, sym));
  return p;
}

bool choose_config() {
  const EGLint es3_bit = 0x40;  // EGL_OPENGL_ES3_BIT_KHR
  for (EGLint renderable : {es3_bit, static_cast<EGLint>(EGL_OPENGL_ES2_BIT)}) {
    const EGLint attribs[] = {EGL_RENDERABLE_TYPE, renderable,
                              EGL_SURFACE_TYPE, EGL_WINDOW_BIT | EGL_PBUFFER_BIT,
                              EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
                              EGL_ALPHA_SIZE, 8, EGL_NONE};
    EGLint count = 0;
    if (eglChooseConfig(g_display, attribs, &g_config, 1, &count) && count > 0) return true;
  }
  return false;
}

bool create_context() {
  for (EGLint version : {3, 2}) {
    const EGLint attribs[] = {EGL_CONTEXT_CLIENT_VERSION, version, EGL_NONE};
    g_context = eglCreateContext(g_display, g_config, EGL_NO_CONTEXT, attribs);
    if (g_context != EGL_NO_CONTEXT) {
      HW_LOG(ANDROID_LOG_INFO, "Contexto OpenGL ES %d creado", version);
      return true;
    }
  }
  return false;
}

bool create_framebuffer(unsigned w, unsigned h) {
  glGenTextures(1, &g_color);
  glBindTexture(GL_TEXTURE_2D, g_color);
  glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, w, h);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glBindTexture(GL_TEXTURE_2D, 0);

  glGenFramebuffers(1, &g_fbo);
  glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, g_color, 0);

  if (g_cb.depth) {
    glGenRenderbuffers(1, &g_depth);
    glBindRenderbuffer(GL_RENDERBUFFER, g_depth);
    glRenderbufferStorage(GL_RENDERBUFFER, g_cb.stencil ? GL_DEPTH24_STENCIL8 : GL_DEPTH_COMPONENT24,
                          w, h);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER,
                              g_cb.stencil ? GL_DEPTH_STENCIL_ATTACHMENT : GL_DEPTH_ATTACHMENT,
                              GL_RENDERBUFFER, g_depth);
    glBindRenderbuffer(GL_RENDERBUFFER, 0);
  }
  const GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
  if (status != GL_FRAMEBUFFER_COMPLETE) {
    HW_LOG(ANDROID_LOG_ERROR, "FBO incompleto: 0x%x", status);
    return false;
  }
  glViewport(0, 0, w, h);
  glClearColor(0, 0, 0, 1);
  glClear(GL_COLOR_BUFFER_BIT);
  return true;
}

void make_current_offscreen() {
  eglMakeCurrent(g_display, g_pbuffer, g_pbuffer, g_context);
}

void destroy_window_surface() {
  make_current_offscreen();
  if (g_surface != EGL_NO_SURFACE) {
    eglDestroySurface(g_display, g_surface);
    g_surface = EGL_NO_SURFACE;
  }
  if (g_window) {
    ANativeWindow_release(g_window);
    g_window = nullptr;
  }
}

}  // namespace

bool request(retro_hw_render_callback* cb) {
  if (!cb) return false;
  switch (cb->context_type) {
    case RETRO_HW_CONTEXT_OPENGLES2:
    case RETRO_HW_CONTEXT_OPENGLES3:
    case RETRO_HW_CONTEXT_OPENGLES_VERSION:
      break;
    default:
      HW_LOG(ANDROID_LOG_WARN, "Tipo de renderizado no admitido: %d", cb->context_type);
      return false;
  }
  cb->get_current_framebuffer = current_framebuffer;
  cb->get_proc_address = proc_address;
  g_cb = *cb;
  g_requested = true;
  HW_LOG(ANDROID_LOG_INFO, "El núcleo dibuja con OpenGL ES (tipo %d, profundidad %d, stencil %d)",
         cb->context_type, cb->depth, cb->stencil);
  return true;
}

retro_hw_context_type preferred() { return RETRO_HW_CONTEXT_OPENGLES3; }

bool active() { return g_requested; }

void reset() {
  g_requested = false;
  g_cb = retro_hw_render_callback{};
}

bool start(unsigned max_width, unsigned max_height) {
  if (!g_requested || g_running) return g_running;
  if (!g_gles_lib) g_gles_lib = dlopen("libGLESv3.so", RTLD_NOW | RTLD_LOCAL);
  if (!g_gles_lib) g_gles_lib = dlopen("libGLESv2.so", RTLD_NOW | RTLD_LOCAL);

  g_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  if (g_display == EGL_NO_DISPLAY || !eglInitialize(g_display, nullptr, nullptr) ||
      !choose_config() || !create_context()) {
    HW_LOG(ANDROID_LOG_ERROR, "No se pudo crear el contexto OpenGL ES: 0x%x", eglGetError());
    return false;
  }
  const EGLint pb[] = {EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE};
  g_pbuffer = eglCreatePbufferSurface(g_display, g_config, pb);
  make_current_offscreen();

  if (max_width == 0 || max_height == 0) {
    max_width = 1024;
    max_height = 1024;
  }
  if (!create_framebuffer(max_width, max_height)) return false;
  g_running = true;
  poll_window();
  glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
  if (g_cb.context_reset) g_cb.context_reset();
  HW_LOG(ANDROID_LOG_INFO, "Renderizado por hardware listo (%ux%u)", max_width, max_height);
  return true;
}

void stop() {
  if (!g_running) return;
  if (g_cb.context_destroy) g_cb.context_destroy();
  make_current_offscreen();
  if (g_fbo) glDeleteFramebuffers(1, &g_fbo);
  if (g_color) glDeleteTextures(1, &g_color);
  if (g_depth) glDeleteRenderbuffers(1, &g_depth);
  g_fbo = g_color = g_depth = 0;
  {
    std::lock_guard<std::mutex> lock(g_win_mutex);
    destroy_window_surface();
    if (g_pending_window) ANativeWindow_release(g_pending_window);
    g_pending_window = nullptr;
    g_pending = false;
  }
  g_win_cv.notify_all();
  eglMakeCurrent(g_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  if (g_pbuffer != EGL_NO_SURFACE) eglDestroySurface(g_display, g_pbuffer);
  if (g_context != EGL_NO_CONTEXT) eglDestroyContext(g_display, g_context);
  g_pbuffer = EGL_NO_SURFACE;
  g_context = EGL_NO_CONTEXT;
  // No se llama a eglTerminate: la pantalla EGL por defecto es compartida con
  // el motor de Flutter en el mismo proceso.
  eglReleaseThread();
  g_running = false;
}

void poll_window() {
  if (!g_running) return;
  {
    std::lock_guard<std::mutex> lock(g_win_mutex);
    if (!g_pending) return;
    ANativeWindow* window = g_pending_window;
    g_pending_window = nullptr;
    g_pending = false;
    destroy_window_surface();
    if (window) {
      g_window = window;
      g_surface = eglCreateWindowSurface(g_display, g_config, window, nullptr);
      if (g_surface == EGL_NO_SURFACE) {
        HW_LOG(ANDROID_LOG_ERROR, "No se pudo crear la superficie EGL: 0x%x", eglGetError());
      }
    }
    if (g_surface != EGL_NO_SURFACE) {
      eglMakeCurrent(g_display, g_surface, g_surface, g_context);
      // Sin esperar al refresco: la emulación marca su propio ritmo.
      eglSwapInterval(g_display, 0);
    }
  }
  g_win_cv.notify_all();
  glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
}

void present(unsigned width, unsigned height) {
  poll_window();
  if (!g_running || g_surface == EGL_NO_SURFACE || width == 0 || height == 0) return;
  EGLint sw = 0, sh = 0;
  eglQuerySurface(g_display, g_surface, EGL_WIDTH, &sw);
  eglQuerySurface(g_display, g_surface, EGL_HEIGHT, &sh);
  if (sw <= 0 || sh <= 0) return;

  glBindFramebuffer(GL_READ_FRAMEBUFFER, g_fbo);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
  glDisable(GL_SCISSOR_TEST);
  glViewport(0, 0, sw, sh);
  // Origen abajo-izquierda (lo normal en OpenGL) = igual que la ventana.
  const bool flip = !g_cb.bottom_left_origin;
  glBlitFramebuffer(0, 0, width, height, 0, flip ? sh : 0, sw, flip ? 0 : sh,
                    GL_COLOR_BUFFER_BIT, GL_LINEAR);
  eglSwapBuffers(g_display, g_surface);
  glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
}

bool capture(std::vector<uint32_t>& out, unsigned& width, unsigned& height) {
  if (!g_running || width == 0 || height == 0) return false;
  out.resize(static_cast<size_t>(width) * height);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, g_fbo);
  glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, out.data());
  glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
  if (g_cb.bottom_left_origin) {
    for (unsigned y = 0; y < height / 2; ++y) {
      std::swap_ranges(out.begin() + y * width, out.begin() + (y + 1) * width,
                       out.begin() + (height - 1 - y) * width);
    }
  }
  for (auto& p : out) p |= 0xFF000000u;
  return true;
}

void set_window(ANativeWindow* window, bool emulation_running, void (*wake)()) {
  std::unique_lock<std::mutex> lock(g_win_mutex);
  if (g_pending_window) ANativeWindow_release(g_pending_window);
  if (window) ANativeWindow_acquire(window);
  g_pending_window = window;
  g_pending = true;
  if (!emulation_running || !g_running) return;  // start() la aplicará
  if (wake) wake();
  // Flutter libera la superficie al volver de esta llamada: hay que esperar a
  // que el hilo de emulación deje de usarla.
  g_win_cv.wait_for(lock, std::chrono::seconds(2), [] { return !g_pending; });
}

bool window_change_pending() {
  std::lock_guard<std::mutex> lock(g_win_mutex);
  return g_pending;
}

}  // namespace rs::hw

#elif !defined(_WIN32)  // Pruebas en el PC (Linux): sin renderizado por hardware.

namespace rs::hw {
bool request(retro_hw_render_callback*) { return false; }
retro_hw_context_type preferred() { return RETRO_HW_CONTEXT_NONE; }
bool active() { return false; }
void reset() {}
bool start(unsigned, unsigned) { return false; }
void stop() {}
void poll_window() {}
void present(unsigned, unsigned) {}
bool capture(std::vector<uint32_t>&, unsigned&, unsigned&) { return false; }
void set_window(ANativeWindow*, bool, void (*)()) {}
bool window_change_pending() { return false; }
}  // namespace rs::hw

#endif
