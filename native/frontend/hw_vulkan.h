// Renderizado por hardware con Vulkan para núcleos libretro que lo piden con
// RETRO_HW_CONTEXT_VULKAN (Azahar en iPhone, donde no hay OpenGL de escritorio
// ni OpenGL ES 3.2). En iPhone Vulkan lo da MoltenVK (sobre Metal); en el PC,
// el controlador de la tarjeta (vulkan-1.dll), lo que permite probarlo aquí.
//
// Como con OpenGL en Windows e iPhone: el núcleo dibuja en su propia imagen,
// se la pasa al frontend con set_image y cada fotograma se copia a memoria
// normal y se entrega a Flutter (rs_copy_frame). No hay superficie ni swapchain.
//
// Todo se llama desde el hilo de emulación, salvo lock_queue/unlock_queue, que
// el núcleo puede llamar desde sus propios hilos.
#pragma once

#include <cstdint>
#include <vector>

#include "libretro.h"

namespace rs::vk {

// SET_HW_RENDER con RETRO_HW_CONTEXT_VULKAN.
bool request(const retro_hw_render_callback* cb);

// SET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE (el núcleo crea su dispositivo).
bool set_negotiation(const void* negotiation);

// GET_HW_RENDER_INTERFACE: la interfaz retro_hw_render_interface_vulkan, o
// null si Vulkan no está iniciado.
const void* render_interface();

// Si el núcleo cargado dibuja con Vulkan.
bool active();

// Olvida la petición del núcleo (al descargar el juego).
void reset();

// Hilo de emulación: crea instancia y dispositivo y llama a context_reset.
bool start();

// Hilo de emulación: llama a context_destroy y libera Vulkan.
void stop();

// Hilo de emulación: copia la última imagen del núcleo a RGBA.
bool capture(std::vector<uint32_t>& out, unsigned& width, unsigned& height);

}  // namespace rs::vk
