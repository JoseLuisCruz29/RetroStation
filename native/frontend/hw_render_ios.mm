// Renderizado por hardware en iPhone (OpenGL ES con EAGL) para núcleos como
// PPSSPP.
//
// Como en Windows (hw_render_win.cpp): el núcleo dibuja en un FBO propio desde
// el hilo de emulación y cada fotograma se lee (capture) y se entrega a
// Flutter por el mismo camino que los núcleos que dibujan por software
// (rs_copy_frame). No hace falta ninguna capa ni superficie de la pantalla.
#if defined(__APPLE__)

#import <OpenGLES/EAGL.h>
#include <OpenGLES/ES3/gl.h>
#include <dlfcn.h>

#include <algorithm>
#include <cstdio>

#include "hw_render.h"

namespace rs::hw {
namespace {

retro_hw_render_callback g_cb{};
bool g_requested = false;
bool g_running = false;

EAGLContext* g_context = nil;
GLuint g_fbo = 0;
GLuint g_color = 0;
GLuint g_depth = 0;

uintptr_t current_framebuffer() { return g_fbo; }

// Las funciones de OpenGL ES están en el framework del sistema, ya cargado.
retro_proc_address_t proc_address(const char* sym) {
  return reinterpret_cast<retro_proc_address_t>(dlsym(RTLD_DEFAULT, sym));
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
    glRenderbufferStorage(GL_RENDERBUFFER, g_cb.stencil ? GL_DEPTH24_STENCIL8 : GL_DEPTH_COMPONENT24, w, h);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER,
                              g_cb.stencil ? GL_DEPTH_STENCIL_ATTACHMENT : GL_DEPTH_ATTACHMENT,
                              GL_RENDERBUFFER, g_depth);
    glBindRenderbuffer(GL_RENDERBUFFER, 0);
  }
  const GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
  if (status != GL_FRAMEBUFFER_COMPLETE) {
    fprintf(stderr, "[gl] FBO incompleto: 0x%x\n", status);
    return false;
  }
  glViewport(0, 0, w, h);
  glClearColor(0, 0, 0, 1);
  glClear(GL_COLOR_BUFFER_BIT);
  return true;
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
      fprintf(stderr, "[gl] Tipo de renderizado no admitido en iPhone: %d\n", cb->context_type);
      return false;
  }
  cb->get_current_framebuffer = current_framebuffer;
  cb->get_proc_address = proc_address;
  g_cb = *cb;
  g_requested = true;
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
  g_context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
  if (!g_context) g_context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
  if (!g_context || ![EAGLContext setCurrentContext:g_context]) {
    fprintf(stderr, "[gl] No se pudo crear el contexto OpenGL ES\n");
    g_context = nil;
    return false;
  }
  if (max_width == 0 || max_height == 0) {
    max_width = 1024;
    max_height = 1024;
  }
  if (!create_framebuffer(max_width, max_height)) {
    [EAGLContext setCurrentContext:nil];
    g_context = nil;
    return false;
  }
  g_running = true;
  glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
  if (g_cb.context_reset) g_cb.context_reset();
  return true;
}

void stop() {
  if (!g_running) return;
  if (g_cb.context_destroy) g_cb.context_destroy();
  if (g_fbo) glDeleteFramebuffers(1, &g_fbo);
  if (g_color) glDeleteTextures(1, &g_color);
  if (g_depth) glDeleteRenderbuffers(1, &g_depth);
  g_fbo = g_color = g_depth = 0;
  glFinish();
  [EAGLContext setCurrentContext:nil];
  g_context = nil;
  g_running = false;
}

void poll_window() {}

// No hay superficie propia: rs_frontend lee el fotograma con capture().
void present(unsigned, unsigned) {}

bool capture(std::vector<uint32_t>& out, unsigned& width, unsigned& height) {
  if (!g_running || width == 0 || height == 0) return false;
  out.resize(static_cast<size_t>(width) * height);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, g_fbo);
  glPixelStorei(GL_PACK_ALIGNMENT, 4);
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

void set_window(ANativeWindow*, bool, void (*)()) {}

bool window_change_pending() { return false; }

}  // namespace rs::hw

#endif  // __APPLE__
