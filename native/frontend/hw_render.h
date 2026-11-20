// Renderizado por hardware (OpenGL ES) para núcleos libretro que lo piden con
// RETRO_ENVIRONMENT_SET_HW_RENDER (p. ej. PPSSPP).
//
// El núcleo dibuja en un framebuffer propio (FBO); al terminar cada fotograma
// se copia escalado a la superficie de Flutter y se presenta con eglSwapBuffers.
// Todas las llamadas EGL/GL se hacen en el hilo de emulación, que es el dueño
// del contexto. La superficie de Flutter puede cambiar desde otro hilo (JNI):
// ese cambio se encola y lo aplica el hilo de emulación.
#pragma once

#include <cstdint>
#include <vector>

#include "libretro.h"

struct ANativeWindow;

namespace rs::hw {

// SET_HW_RENDER (en retro_load_game). Devuelve false si el tipo no se admite.
bool request(retro_hw_render_callback* cb);

// GET_PREFERRED_HW_RENDER.
retro_hw_context_type preferred();

// Si el núcleo cargado dibuja por hardware.
bool active();

// Olvida la petición del núcleo (al descargar el juego).
void reset();

// Hilo de emulación: crea el contexto y el FBO y llama a context_reset.
bool start(unsigned max_width, unsigned max_height);

// Hilo de emulación: llama a context_destroy y libera EGL.
void stop();

// Hilo de emulación: aplica un cambio de superficie pendiente.
void poll_window();

// Hilo de emulación, desde video_refresh: presenta el fotograma.
void present(unsigned width, unsigned height);

// Hilo de emulación: copia el último fotograma a RGBA (miniaturas).
bool capture(std::vector<uint32_t>& out, unsigned& width, unsigned& height);

// Cualquier hilo (JNI): nueva superficie, o null. Espera a que el hilo de
// emulación deje de usar la anterior antes de volver.
void set_window(ANativeWindow* window, bool emulation_running, void (*wake)());

// Si hay un cambio de superficie esperando al hilo de emulación.
bool window_change_pending();

}  // namespace rs::hw
