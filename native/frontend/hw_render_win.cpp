// Renderizado por hardware en Windows (OpenGL de escritorio con WGL) para
// núcleos como PPSSPP.
//
// Igual que en Android, el núcleo dibuja en un FBO propio desde el hilo de
// emulación. Aquí no hay superficie nativa: cada fotograma se lee del FBO
// (capture) y se entrega a la ventana de Flutter por el mismo camino que los
// núcleos que dibujan por software (rs_copy_frame). El contexto vive en una
// ventana oculta que solo sirve para tener un "device context".
#ifdef _WIN32

#include <windows.h>
#include <GL/gl.h>

#include <algorithm>
#include <cstdarg>
#include <cstdio>

#include "hw_render.h"
#include "hw_vulkan.h"

// Constantes de OpenGL posteriores a la 1.1 (gl.h de Windows solo trae la 1.1).
#define RS_GL_FRAMEBUFFER 0x8D40
#define RS_GL_READ_FRAMEBUFFER 0x8CA8
#define RS_GL_RENDERBUFFER 0x8D41
#define RS_GL_COLOR_ATTACHMENT0 0x8CE0
#define RS_GL_DEPTH_ATTACHMENT 0x8D00
#define RS_GL_DEPTH_STENCIL_ATTACHMENT 0x821A
#define RS_GL_DEPTH24_STENCIL8 0x88F0
#define RS_GL_DEPTH_COMPONENT24 0x81A6
#define RS_GL_FRAMEBUFFER_COMPLETE 0x8CD5
#define RS_GL_RGBA8 0x8058

#define WGL_CONTEXT_MAJOR_VERSION_ARB 0x2091
#define WGL_CONTEXT_MINOR_VERSION_ARB 0x2092
#define WGL_CONTEXT_FLAGS_ARB 0x2094
#define WGL_CONTEXT_PROFILE_MASK_ARB 0x9126
#define WGL_CONTEXT_CORE_PROFILE_BIT_ARB 0x0001
#define WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB 0x0002

// Portátiles con dos GPU: pedir la dedicada (NVIDIA / AMD) cuando la haya.
extern "C" {
__declspec(dllexport) DWORD NvOptimusEnablement = 1;
__declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
}

namespace rs::hw {
namespace {

using PFNCREATECONTEXTATTRIBS = HGLRC(WINAPI*)(HDC, HGLRC, const int*);
using PFNGENFRAMEBUFFERS = void(APIENTRY*)(GLsizei, GLuint*);
using PFNDELETEFRAMEBUFFERS = void(APIENTRY*)(GLsizei, const GLuint*);
using PFNBINDFRAMEBUFFER = void(APIENTRY*)(GLenum, GLuint);
using PFNFRAMEBUFFERTEXTURE2D = void(APIENTRY*)(GLenum, GLenum, GLenum, GLuint, GLint);
using PFNGENRENDERBUFFERS = void(APIENTRY*)(GLsizei, GLuint*);
using PFNDELETERENDERBUFFERS = void(APIENTRY*)(GLsizei, const GLuint*);
using PFNBINDRENDERBUFFER = void(APIENTRY*)(GLenum, GLuint);
using PFNRENDERBUFFERSTORAGE = void(APIENTRY*)(GLenum, GLenum, GLsizei, GLsizei);
using PFNFRAMEBUFFERRENDERBUFFER = void(APIENTRY*)(GLenum, GLenum, GLenum, GLuint);
using PFNCHECKFRAMEBUFFERSTATUS = GLenum(APIENTRY*)(GLenum);

struct GlExt {
  PFNGENFRAMEBUFFERS GenFramebuffers = nullptr;
  PFNDELETEFRAMEBUFFERS DeleteFramebuffers = nullptr;
  PFNBINDFRAMEBUFFER BindFramebuffer = nullptr;
  PFNFRAMEBUFFERTEXTURE2D FramebufferTexture2D = nullptr;
  PFNGENRENDERBUFFERS GenRenderbuffers = nullptr;
  PFNDELETERENDERBUFFERS DeleteRenderbuffers = nullptr;
  PFNBINDRENDERBUFFER BindRenderbuffer = nullptr;
  PFNRENDERBUFFERSTORAGE RenderbufferStorage = nullptr;
  PFNFRAMEBUFFERRENDERBUFFER FramebufferRenderbuffer = nullptr;
  PFNCHECKFRAMEBUFFERSTATUS CheckFramebufferStatus = nullptr;
} gl;

retro_hw_render_callback g_cb{};
bool g_requested = false;
bool g_running = false;

HMODULE g_opengl32 = nullptr;
HWND g_hwnd = nullptr;
HDC g_dc = nullptr;
HGLRC g_ctx = nullptr;

GLuint g_fbo = 0;
GLuint g_color = 0;
GLuint g_depth = 0;

void log(const char* fmt, ...) {
  char buf[512];
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(buf, sizeof buf, fmt, ap);
  va_end(ap);
  fprintf(stderr, "[gl] %s\n", buf);
  OutputDebugStringA(buf);
}

uintptr_t current_framebuffer() { return g_fbo; }

retro_proc_address_t proc_address(const char* sym) {
  PROC p = wglGetProcAddress(sym);
  // wglGetProcAddress no devuelve las funciones de la 1.1 (y algunos drivers
  // devuelven 1, 2, 3 o -1 en vez de null): esas están en opengl32.dll.
  const auto v = reinterpret_cast<intptr_t>(p);
  if (v == 0 || v == 1 || v == 2 || v == 3 || v == -1) {
    p = g_opengl32 ? GetProcAddress(g_opengl32, sym) : nullptr;
  }
  return reinterpret_cast<retro_proc_address_t>(p);
}

template <typename T>
bool load(T& fn, const char* name) {
  fn = reinterpret_cast<T>(proc_address(name));
  if (!fn) log("Falta la función %s", name);
  return fn != nullptr;
}

bool load_ext() {
  return load(gl.GenFramebuffers, "glGenFramebuffers") &&
         load(gl.DeleteFramebuffers, "glDeleteFramebuffers") &&
         load(gl.BindFramebuffer, "glBindFramebuffer") &&
         load(gl.FramebufferTexture2D, "glFramebufferTexture2D") &&
         load(gl.GenRenderbuffers, "glGenRenderbuffers") &&
         load(gl.DeleteRenderbuffers, "glDeleteRenderbuffers") &&
         load(gl.BindRenderbuffer, "glBindRenderbuffer") &&
         load(gl.RenderbufferStorage, "glRenderbufferStorage") &&
         load(gl.FramebufferRenderbuffer, "glFramebufferRenderbuffer") &&
         load(gl.CheckFramebufferStatus, "glCheckFramebufferStatus");
}

bool create_window() {
  static const wchar_t* kClass = L"RetroStationGL";
  WNDCLASSW wc{};
  wc.style = CS_OWNDC;
  wc.lpfnWndProc = DefWindowProcW;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = kClass;
  RegisterClassW(&wc);  // falla sin problema si ya estaba registrada
  g_hwnd = CreateWindowExW(0, kClass, L"RetroStation GL", WS_POPUP, 0, 0, 16, 16, nullptr, nullptr,
                           wc.hInstance, nullptr);
  if (!g_hwnd) return false;
  g_dc = GetDC(g_hwnd);
  PIXELFORMATDESCRIPTOR pfd{};
  pfd.nSize = sizeof pfd;
  pfd.nVersion = 1;
  pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
  pfd.iPixelType = PFD_TYPE_RGBA;
  pfd.cColorBits = 32;
  pfd.cAlphaBits = 8;
  pfd.cDepthBits = 24;
  pfd.cStencilBits = 8;
  const int format = ChoosePixelFormat(g_dc, &pfd);
  return format != 0 && SetPixelFormat(g_dc, format, &pfd);
}

bool create_context() {
  // Contexto provisional para obtener wglCreateContextAttribsARB.
  HGLRC legacy = wglCreateContext(g_dc);
  if (!legacy || !wglMakeCurrent(g_dc, legacy)) return false;
  auto create_attribs =
      reinterpret_cast<PFNCREATECONTEXTATTRIBS>(wglGetProcAddress("wglCreateContextAttribsARB"));
  if (create_attribs) {
    const bool core = g_cb.context_type == RETRO_HW_CONTEXT_OPENGL_CORE;
    int major = static_cast<int>(g_cb.version_major);
    int minor = static_cast<int>(g_cb.version_minor);
    if (core && (major < 3 || (major == 3 && minor < 2))) {
      major = 3;
      minor = 3;
    }
    const int attribs[] = {
        WGL_CONTEXT_MAJOR_VERSION_ARB, core ? major : 2,
        WGL_CONTEXT_MINOR_VERSION_ARB, core ? minor : 1,
        WGL_CONTEXT_PROFILE_MASK_ARB,
        core ? WGL_CONTEXT_CORE_PROFILE_BIT_ARB : WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB,
        0};
    HGLRC modern = create_attribs(g_dc, nullptr, attribs);
    if (modern) {
      wglMakeCurrent(nullptr, nullptr);
      wglDeleteContext(legacy);
      g_ctx = modern;
      return wglMakeCurrent(g_dc, g_ctx) != FALSE;
    }
    log("No se pudo crear el contexto %d.%d; se usa el de compatibilidad", major, minor);
  }
  g_ctx = legacy;
  return true;
}

bool create_framebuffer(unsigned w, unsigned h) {
  glGenTextures(1, &g_color);
  glBindTexture(GL_TEXTURE_2D, g_color);
  glTexImage2D(GL_TEXTURE_2D, 0, RS_GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glBindTexture(GL_TEXTURE_2D, 0);

  gl.GenFramebuffers(1, &g_fbo);
  gl.BindFramebuffer(RS_GL_FRAMEBUFFER, g_fbo);
  gl.FramebufferTexture2D(RS_GL_FRAMEBUFFER, RS_GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, g_color, 0);
  if (g_cb.depth) {
    gl.GenRenderbuffers(1, &g_depth);
    gl.BindRenderbuffer(RS_GL_RENDERBUFFER, g_depth);
    gl.RenderbufferStorage(RS_GL_RENDERBUFFER,
                           g_cb.stencil ? RS_GL_DEPTH24_STENCIL8 : RS_GL_DEPTH_COMPONENT24, w, h);
    gl.FramebufferRenderbuffer(RS_GL_FRAMEBUFFER,
                               g_cb.stencil ? RS_GL_DEPTH_STENCIL_ATTACHMENT : RS_GL_DEPTH_ATTACHMENT,
                               RS_GL_RENDERBUFFER, g_depth);
    gl.BindRenderbuffer(RS_GL_RENDERBUFFER, 0);
  }
  const GLenum status = gl.CheckFramebufferStatus(RS_GL_FRAMEBUFFER);
  if (status != RS_GL_FRAMEBUFFER_COMPLETE) {
    log("FBO incompleto: 0x%x", status);
    return false;
  }
  glViewport(0, 0, w, h);
  glClearColor(0, 0, 0, 1);
  glClear(GL_COLOR_BUFFER_BIT);
  return true;
}

void destroy_context() {
  wglMakeCurrent(nullptr, nullptr);
  if (g_ctx) wglDeleteContext(g_ctx);
  if (g_dc) ReleaseDC(g_hwnd, g_dc);
  if (g_hwnd) DestroyWindow(g_hwnd);
  g_ctx = nullptr;
  g_dc = nullptr;
  g_hwnd = nullptr;
}

}  // namespace

bool request(retro_hw_render_callback* cb) {
  // Núcleos que solo dibujan con Vulkan (Azahar en iPhone): ver hw_vulkan.cpp.
  if (cb && cb->context_type == RETRO_HW_CONTEXT_VULKAN) return rs::vk::request(cb);
  if (!cb) return false;
  if (cb->context_type != RETRO_HW_CONTEXT_OPENGL && cb->context_type != RETRO_HW_CONTEXT_OPENGL_CORE) {
    log("Tipo de renderizado no admitido: %d", cb->context_type);
    return false;
  }
  cb->get_current_framebuffer = current_framebuffer;
  cb->get_proc_address = proc_address;
  g_cb = *cb;
  g_requested = true;
  log("El núcleo dibuja con OpenGL (tipo %d, versión %u.%u)", cb->context_type, cb->version_major,
      cb->version_minor);
  return true;
}

retro_hw_context_type preferred() { return RETRO_HW_CONTEXT_OPENGL_CORE; }

bool active() { return g_requested || rs::vk::active(); }

void reset() {
  rs::vk::reset();
  g_requested = false;
  g_cb = retro_hw_render_callback{};
}

bool start(unsigned max_width, unsigned max_height) {
  if (rs::vk::active()) return rs::vk::start();
  if (!g_requested || g_running) return g_running;
  if (!g_opengl32) g_opengl32 = LoadLibraryW(L"opengl32.dll");
  if (!create_window() || !create_context() || !load_ext()) {
    log("No se pudo crear el contexto OpenGL (error %lu)", GetLastError());
    destroy_context();
    return false;
  }
  log("OpenGL %s (%s)", reinterpret_cast<const char*>(glGetString(GL_VERSION)),
      reinterpret_cast<const char*>(glGetString(GL_RENDERER)));
  if (max_width == 0 || max_height == 0) {
    max_width = 1024;
    max_height = 1024;
  }
  if (!create_framebuffer(max_width, max_height)) {
    destroy_context();
    return false;
  }
  g_running = true;
  gl.BindFramebuffer(RS_GL_FRAMEBUFFER, g_fbo);
  if (g_cb.context_reset) g_cb.context_reset();
  log("Renderizado por hardware listo (%ux%u)", max_width, max_height);
  return true;
}

void stop() {
  if (rs::vk::active()) {
    rs::vk::stop();
    return;
  }
  if (!g_running) return;
  if (g_cb.context_destroy) g_cb.context_destroy();
  if (g_fbo) gl.DeleteFramebuffers(1, &g_fbo);
  if (g_color) glDeleteTextures(1, &g_color);
  if (g_depth) gl.DeleteRenderbuffers(1, &g_depth);
  g_fbo = g_color = g_depth = 0;
  destroy_context();
  g_running = false;
}

void poll_window() {}

// No hay superficie propia: rs_frontend lee el fotograma con capture().
void present(unsigned, unsigned) {}

bool capture(std::vector<uint32_t>& out, unsigned& width, unsigned& height) {
  if (rs::vk::active()) return rs::vk::capture(out, width, height);
  if (!g_running || width == 0 || height == 0) return false;
  out.resize(static_cast<size_t>(width) * height);
  gl.BindFramebuffer(RS_GL_READ_FRAMEBUFFER, g_fbo);
  glPixelStorei(GL_PACK_ALIGNMENT, 4);
  glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, out.data());
  gl.BindFramebuffer(RS_GL_FRAMEBUFFER, g_fbo);
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

#endif  // _WIN32
