// Renderizado por hardware con Vulkan (ver hw_vulkan.h).
#define VK_NO_PROTOTYPES
#include "hw_vulkan.h"

#include <vulkan/vulkan.h>

#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <mutex>

#include "libretro_vulkan.h"

#if defined(_WIN32)
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace rs::vk {
namespace {

void log(const char* fmt, ...) {
  char buf[512];
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(buf, sizeof buf, fmt, ap);
  va_end(ap);
  fprintf(stderr, "[vulkan] %s\n", buf);
}

retro_hw_render_callback g_cb{};
bool g_requested = false;
bool g_running = false;
const retro_hw_render_context_negotiation_interface_vulkan* g_negotiation = nullptr;

// Funciones de Vulkan (sin enlazar el cargador: se buscan en tiempo de ejecución).
PFN_vkGetInstanceProcAddr gipa = nullptr;
PFN_vkGetDeviceProcAddr gdpa = nullptr;
#define RS_VK_FUNCS(X)                                                                    \
  X(vkCreateInstance) X(vkDestroyInstance) X(vkEnumerateInstanceExtensionProperties)      \
  X(vkEnumeratePhysicalDevices) X(vkGetPhysicalDeviceProperties)                          \
  X(vkGetPhysicalDeviceQueueFamilyProperties) X(vkGetPhysicalDeviceMemoryProperties)      \
  X(vkCreateDevice) X(vkDestroyDevice) X(vkGetDeviceQueue) X(vkDeviceWaitIdle)            \
  X(vkCreateCommandPool) X(vkDestroyCommandPool) X(vkAllocateCommandBuffers)              \
  X(vkBeginCommandBuffer) X(vkEndCommandBuffer) X(vkResetCommandBuffer)                   \
  X(vkCmdPipelineBarrier) X(vkCmdCopyImageToBuffer) X(vkQueueSubmit)                      \
  X(vkCreateFence) X(vkDestroyFence) X(vkWaitForFences) X(vkResetFences)                  \
  X(vkCreateBuffer) X(vkDestroyBuffer) X(vkGetBufferMemoryRequirements)                   \
  X(vkAllocateMemory) X(vkFreeMemory) X(vkBindBufferMemory) X(vkMapMemory)                \
  X(vkUnmapMemory)
#define RS_VK_DECLARE(name) PFN_##name name = nullptr;
RS_VK_FUNCS(RS_VK_DECLARE)
#undef RS_VK_DECLARE

void* g_loader = nullptr;
VkInstance g_instance = VK_NULL_HANDLE;
VkPhysicalDevice g_gpu = VK_NULL_HANDLE;
VkDevice g_device = VK_NULL_HANDLE;
VkQueue g_queue = VK_NULL_HANDLE;
uint32_t g_queue_family = 0;
bool g_core_owns_device = false;

retro_hw_render_interface_vulkan g_iface{};
std::mutex g_queue_mutex;

// Última imagen entregada por el núcleo (set_image).
retro_vulkan_image g_image{};
bool g_has_image = false;
std::vector<VkSemaphore> g_wait_semaphores;
std::vector<VkCommandBuffer> g_core_commands;

// Copia de la imagen a memoria visible por la CPU.
VkCommandPool g_pool = VK_NULL_HANDLE;
VkCommandBuffer g_cmd = VK_NULL_HANDLE;
VkFence g_fence = VK_NULL_HANDLE;
VkBuffer g_staging = VK_NULL_HANDLE;
VkDeviceMemory g_staging_memory = VK_NULL_HANDLE;
VkDeviceSize g_staging_size = 0;
void* g_staging_map = nullptr;

// --- Interfaz que ve el núcleo ---------------------------------------------

void RETRO_CALLCONV set_image(void*, const retro_vulkan_image* image, uint32_t num_semaphores,
                              const VkSemaphore* semaphores, uint32_t) {
  if (image) {
    g_image = *image;
    g_has_image = true;
  }
  g_wait_semaphores.assign(semaphores, semaphores + num_semaphores);
}
uint32_t RETRO_CALLCONV get_sync_index(void*) { return 0; }
uint32_t RETRO_CALLCONV get_sync_index_mask(void*) { return 1; }
void RETRO_CALLCONV set_command_buffers(void*, uint32_t num, const VkCommandBuffer* cmd) {
  g_core_commands.assign(cmd, cmd + num);
}
// Cada captura espera a la GPU: no hay fotogramas en vuelo que esperar.
void RETRO_CALLCONV wait_sync_index(void*) {}
void RETRO_CALLCONV lock_queue(void*) { g_queue_mutex.lock(); }
void RETRO_CALLCONV unlock_queue(void*) { g_queue_mutex.unlock(); }
void RETRO_CALLCONV set_signal_semaphore(void*, VkSemaphore) {}

// --- Carga de Vulkan ---------------------------------------------------------

bool load_loader() {
#if defined(_WIN32)
  HMODULE lib = LoadLibraryA("vulkan-1.dll");
  if (!lib) return false;
  g_loader = lib;
  gipa = reinterpret_cast<PFN_vkGetInstanceProcAddr>(GetProcAddress(lib, "vkGetInstanceProcAddr"));
#elif defined(__APPLE__)
  // iPhone: MoltenVK va como framework dentro de la app (Runner.app/Frameworks),
  // igual que los núcleos; se abre solo cuando un juego lo necesita.
  for (const char* path : {"@executable_path/Frameworks/MoltenVK.framework/MoltenVK",
                           "@rpath/MoltenVK.framework/MoltenVK", "libMoltenVK.dylib"}) {
    g_loader = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (g_loader) break;
  }
  if (g_loader) {
    gipa = reinterpret_cast<PFN_vkGetInstanceProcAddr>(dlsym(g_loader, "vkGetInstanceProcAddr"));
  } else {
    log("No se pudo abrir MoltenVK: %s", dlerror());
  }
#else
  g_loader = dlopen("libvulkan.so", RTLD_NOW);
  if (!g_loader) g_loader = dlopen("libvulkan.so.1", RTLD_NOW);
  if (g_loader) gipa = reinterpret_cast<PFN_vkGetInstanceProcAddr>(dlsym(g_loader, "vkGetInstanceProcAddr"));
#endif
  return gipa != nullptr;
}

template <typename T>
bool instance_fn(T& fn, VkInstance instance, const char* name) {
  fn = reinterpret_cast<T>(gipa(instance, name));
  if (!fn) log("Falta %s", name);
  return fn != nullptr;
}

bool has_extension(const std::vector<VkExtensionProperties>& list, const char* name) {
  for (const auto& e : list) {
    if (std::strcmp(e.extensionName, name) == 0) return true;
  }
  return false;
}

bool create_instance() {
  if (!instance_fn(vkCreateInstance, VK_NULL_HANDLE, "vkCreateInstance") ||
      !instance_fn(vkEnumerateInstanceExtensionProperties, VK_NULL_HANDLE,
                   "vkEnumerateInstanceExtensionProperties")) {
    return false;
  }
  VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
  app.pApplicationName = "RetroStation";
  app.pEngineName = "RetroStation";
  app.apiVersion = VK_API_VERSION_1_1;
  const VkApplicationInfo* app_info = &app;
  if (g_negotiation && g_negotiation->get_application_info) {
    if (const VkApplicationInfo* core_app = g_negotiation->get_application_info()) app_info = core_app;
  }

  uint32_t count = 0;
  vkEnumerateInstanceExtensionProperties(nullptr, &count, nullptr);
  std::vector<VkExtensionProperties> available(count);
  vkEnumerateInstanceExtensionProperties(nullptr, &count, available.data());
  std::vector<const char*> extensions;
  VkInstanceCreateFlags flags = 0;
  // MoltenVK es una implementación "portable": con el cargador de Vulkan hay
  // que pedir que la enumere.
  if (has_extension(available, VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)) {
    extensions.push_back(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
    flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
  }
  if (has_extension(available, VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME)) {
    extensions.push_back(VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME);
  }

  VkInstanceCreateInfo info{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
  info.flags = flags;
  info.pApplicationInfo = app_info;
  info.enabledExtensionCount = static_cast<uint32_t>(extensions.size());
  info.ppEnabledExtensionNames = extensions.data();
  const VkResult r = vkCreateInstance(&info, nullptr, &g_instance);
  if (r != VK_SUCCESS) {
    log("vkCreateInstance falló (%d)", r);
    return false;
  }
#define RS_VK_LOAD(name) instance_fn(name, g_instance, #name);
  RS_VK_FUNCS(RS_VK_LOAD)
#undef RS_VK_LOAD
  gdpa = reinterpret_cast<PFN_vkGetDeviceProcAddr>(gipa(g_instance, "vkGetDeviceProcAddr"));
  return gdpa && vkEnumeratePhysicalDevices && vkCreateDevice && vkCmdCopyImageToBuffer;
}

bool pick_gpu() {
  uint32_t count = 0;
  vkEnumeratePhysicalDevices(g_instance, &count, nullptr);
  if (count == 0) {
    log("No hay ninguna GPU con Vulkan");
    return false;
  }
  std::vector<VkPhysicalDevice> gpus(count);
  vkEnumeratePhysicalDevices(g_instance, &count, gpus.data());
  g_gpu = gpus[0];
  for (VkPhysicalDevice gpu : gpus) {  // mejor una tarjeta dedicada si la hay
    VkPhysicalDeviceProperties props{};
    vkGetPhysicalDeviceProperties(gpu, &props);
    if (props.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
      g_gpu = gpu;
      break;
    }
  }
  VkPhysicalDeviceProperties props{};
  vkGetPhysicalDeviceProperties(g_gpu, &props);
  log("GPU: %s (Vulkan %u.%u)", props.deviceName, VK_API_VERSION_MAJOR(props.apiVersion),
      VK_API_VERSION_MINOR(props.apiVersion));
  return true;
}

bool create_device() {
  if (g_negotiation && g_negotiation->create_device) {
    // El núcleo elige extensiones y funciones y crea el dispositivo.
    retro_vulkan_context context{};
    if (!g_negotiation->create_device(&context, g_instance, g_gpu, VK_NULL_HANDLE, gipa, nullptr, 0,
                                      nullptr, 0, nullptr)) {
      log("El núcleo no pudo crear el dispositivo Vulkan");
      return false;
    }
    g_gpu = context.gpu;
    g_device = context.device;
    g_queue = context.queue;
    g_queue_family = context.queue_family_index;
    g_core_owns_device = g_negotiation->destroy_device != nullptr;
    return true;
  }
  uint32_t count = 0;
  vkGetPhysicalDeviceQueueFamilyProperties(g_gpu, &count, nullptr);
  std::vector<VkQueueFamilyProperties> families(count);
  vkGetPhysicalDeviceQueueFamilyProperties(g_gpu, &count, families.data());
  bool found = false;
  for (uint32_t i = 0; i < count; ++i) {
    if (families[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) {
      g_queue_family = i;
      found = true;
      break;
    }
  }
  if (!found) return false;
  const float priority = 1.0f;
  VkDeviceQueueCreateInfo queue{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
  queue.queueFamilyIndex = g_queue_family;
  queue.queueCount = 1;
  queue.pQueuePriorities = &priority;
  VkDeviceCreateInfo info{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
  info.queueCreateInfoCount = 1;
  info.pQueueCreateInfos = &queue;
  if (vkCreateDevice(g_gpu, &info, nullptr, &g_device) != VK_SUCCESS) return false;
  vkGetDeviceQueue(g_device, g_queue_family, 0, &g_queue);
  return true;
}

bool create_copy_resources() {
  VkCommandPoolCreateInfo pool{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
  pool.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
  pool.queueFamilyIndex = g_queue_family;
  if (vkCreateCommandPool(g_device, &pool, nullptr, &g_pool) != VK_SUCCESS) return false;
  VkCommandBufferAllocateInfo alloc{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
  alloc.commandPool = g_pool;
  alloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  alloc.commandBufferCount = 1;
  if (vkAllocateCommandBuffers(g_device, &alloc, &g_cmd) != VK_SUCCESS) return false;
  VkFenceCreateInfo fence{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
  return vkCreateFence(g_device, &fence, nullptr, &g_fence) == VK_SUCCESS;
}

void destroy_staging() {
  if (g_staging_map) vkUnmapMemory(g_device, g_staging_memory);
  if (g_staging) vkDestroyBuffer(g_device, g_staging, nullptr);
  if (g_staging_memory) vkFreeMemory(g_device, g_staging_memory, nullptr);
  g_staging_map = nullptr;
  g_staging = VK_NULL_HANDLE;
  g_staging_memory = VK_NULL_HANDLE;
  g_staging_size = 0;
}

bool ensure_staging(VkDeviceSize size) {
  if (g_staging && g_staging_size >= size) return true;
  destroy_staging();
  VkBufferCreateInfo info{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
  info.size = size;
  info.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
  info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
  if (vkCreateBuffer(g_device, &info, nullptr, &g_staging) != VK_SUCCESS) return false;
  VkMemoryRequirements req{};
  vkGetBufferMemoryRequirements(g_device, g_staging, &req);
  VkPhysicalDeviceMemoryProperties mem{};
  vkGetPhysicalDeviceMemoryProperties(g_gpu, &mem);
  const VkMemoryPropertyFlags want =
      VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
  uint32_t type = UINT32_MAX;
  for (uint32_t i = 0; i < mem.memoryTypeCount; ++i) {
    if ((req.memoryTypeBits & (1u << i)) && (mem.memoryTypes[i].propertyFlags & want) == want) {
      // Mejor memoria en caché: la CPU lee toda la imagen cada fotograma.
      if (type == UINT32_MAX ||
          (mem.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_HOST_CACHED_BIT)) {
        type = i;
      }
    }
  }
  if (type == UINT32_MAX) return false;
  VkMemoryAllocateInfo alloc{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
  alloc.allocationSize = req.size;
  alloc.memoryTypeIndex = type;
  if (vkAllocateMemory(g_device, &alloc, nullptr, &g_staging_memory) != VK_SUCCESS) return false;
  vkBindBufferMemory(g_device, g_staging, g_staging_memory, 0);
  if (vkMapMemory(g_device, g_staging_memory, 0, size, 0, &g_staging_map) != VK_SUCCESS) return false;
  g_staging_size = size;
  return true;
}

void destroy_all() {
  if (g_device) {
    destroy_staging();
    if (g_fence) vkDestroyFence(g_device, g_fence, nullptr);
    if (g_pool) vkDestroyCommandPool(g_device, g_pool, nullptr);
    if (g_core_owns_device && g_negotiation && g_negotiation->destroy_device) {
      g_negotiation->destroy_device();
    } else {
      vkDestroyDevice(g_device, nullptr);
    }
  }
  if (g_instance && vkDestroyInstance) vkDestroyInstance(g_instance, nullptr);
  g_fence = VK_NULL_HANDLE;
  g_pool = VK_NULL_HANDLE;
  g_cmd = VK_NULL_HANDLE;
  g_device = VK_NULL_HANDLE;
  g_instance = VK_NULL_HANDLE;
  g_gpu = VK_NULL_HANDLE;
  g_queue = VK_NULL_HANDLE;
  g_iface = retro_hw_render_interface_vulkan{};
  g_has_image = false;
  g_wait_semaphores.clear();
  g_core_commands.clear();
}

}  // namespace

bool request(const retro_hw_render_callback* cb) {
  if (!cb || cb->context_type != RETRO_HW_CONTEXT_VULKAN) return false;
  g_cb = *cb;
  g_requested = true;
  return true;
}

bool set_negotiation(const void* negotiation) {
  auto n = static_cast<const retro_hw_render_context_negotiation_interface_vulkan*>(negotiation);
  if (!n || n->interface_type != RETRO_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE_VULKAN) return false;
  g_negotiation = n;
  return true;
}

const void* render_interface() { return g_running ? &g_iface : nullptr; }

bool active() { return g_requested; }

void reset() {
  if (g_running) {
    {
      std::lock_guard<std::mutex> lock(g_queue_mutex);
      vkDeviceWaitIdle(g_device);
    }
    destroy_all();
    g_running = false;
  }
  g_requested = false;
  g_negotiation = nullptr;
  g_cb = retro_hw_render_callback{};
}

bool start() {
  if (!g_requested || g_running) return g_running;
  if (!load_loader()) {
    log("No se encontró Vulkan en este dispositivo");
    return false;
  }
  if (!create_instance() || !pick_gpu() || !create_device() || !create_copy_resources()) {
    destroy_all();
    return false;
  }
  g_iface.interface_type = RETRO_HW_RENDER_INTERFACE_VULKAN;
  g_iface.interface_version = RETRO_HW_RENDER_INTERFACE_VULKAN_VERSION;
  g_iface.handle = &g_iface;
  g_iface.instance = g_instance;
  g_iface.gpu = g_gpu;
  g_iface.device = g_device;
  g_iface.get_device_proc_addr = gdpa;
  g_iface.get_instance_proc_addr = gipa;
  g_iface.queue = g_queue;
  g_iface.queue_index = g_queue_family;
  g_iface.set_image = set_image;
  g_iface.get_sync_index = get_sync_index;
  g_iface.get_sync_index_mask = get_sync_index_mask;
  g_iface.set_command_buffers = set_command_buffers;
  g_iface.wait_sync_index = wait_sync_index;
  g_iface.lock_queue = lock_queue;
  g_iface.unlock_queue = unlock_queue;
  g_iface.set_signal_semaphore = set_signal_semaphore;
  g_running = true;
  log("Listo");
  if (g_cb.context_reset) g_cb.context_reset();
  return true;
}

void stop() {
  if (!g_running) return;
  {
    std::lock_guard<std::mutex> lock(g_queue_mutex);
    vkDeviceWaitIdle(g_device);
  }
  if (g_cb.context_destroy) g_cb.context_destroy();
  {
    std::lock_guard<std::mutex> lock(g_queue_mutex);
    vkDeviceWaitIdle(g_device);
  }
  // El dispositivo sigue vivo: el núcleo aún lo usa al descargar el juego
  // (retro_unload_game/retro_deinit). Se destruye en reset(), después.
  g_has_image = false;
}

bool capture(std::vector<uint32_t>& out, unsigned& width, unsigned& height) {
  if (!g_running || !g_has_image || width == 0 || height == 0) return false;
  const VkDeviceSize size = static_cast<VkDeviceSize>(width) * height * 4;
  if (!ensure_staging(size)) return false;
  const VkImage image = g_image.create_info.image;
  const VkImageLayout layout = g_image.image_layout;

  vkResetCommandBuffer(g_cmd, 0);
  VkCommandBufferBeginInfo begin{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
  begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  vkBeginCommandBuffer(g_cmd, &begin);
  VkImageMemoryBarrier barrier{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
  barrier.srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | VK_ACCESS_SHADER_WRITE_BIT |
                          VK_ACCESS_TRANSFER_WRITE_BIT;
  barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
  barrier.oldLayout = layout;
  barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
  barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  barrier.image = image;
  barrier.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
  vkCmdPipelineBarrier(g_cmd, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0,
                       0, nullptr, 0, nullptr, 1, &barrier);
  VkBufferImageCopy region{};
  region.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
  region.imageExtent = {width, height, 1};
  vkCmdCopyImageToBuffer(g_cmd, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, g_staging, 1, &region);
  // La imagen vuelve a como la dejó el núcleo, que la seguirá usando.
  barrier.srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
  barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
  barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
  barrier.newLayout = layout;
  vkCmdPipelineBarrier(g_cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0,
                       0, nullptr, 0, nullptr, 1, &barrier);
  vkEndCommandBuffer(g_cmd);

  // Comandos que el núcleo dejó con set_command_buffers (Azahar no usa) y luego la copia.
  std::vector<VkCommandBuffer> cmds = g_core_commands;
  cmds.push_back(g_cmd);
  std::vector<VkPipelineStageFlags> stages(g_wait_semaphores.size(), VK_PIPELINE_STAGE_ALL_COMMANDS_BIT);
  VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};
  submit.waitSemaphoreCount = static_cast<uint32_t>(g_wait_semaphores.size());
  submit.pWaitSemaphores = g_wait_semaphores.data();
  submit.pWaitDstStageMask = stages.data();
  submit.commandBufferCount = static_cast<uint32_t>(cmds.size());
  submit.pCommandBuffers = cmds.data();
  VkResult r;
  {
    std::lock_guard<std::mutex> lock(g_queue_mutex);
    r = vkQueueSubmit(g_queue, 1, &submit, g_fence);
  }
  g_core_commands.clear();
  g_wait_semaphores.clear();
  if (r != VK_SUCCESS) {
    log("vkQueueSubmit falló (%d)", r);
    return false;
  }
  vkWaitForFences(g_device, 1, &g_fence, VK_TRUE, UINT64_MAX);
  vkResetFences(g_device, 1, &g_fence);

  out.resize(static_cast<size_t>(width) * height);
  std::memcpy(out.data(), g_staging_map, static_cast<size_t>(size));
  const VkFormat format = g_image.create_info.format;
  const bool bgra = format == VK_FORMAT_B8G8R8A8_UNORM || format == VK_FORMAT_B8G8R8A8_SRGB;
  for (auto& p : out) {
    // Salida en bytes R, G, B, A (como glReadPixels con GL_RGBA), opaca.
    if (bgra) p = (p & 0xFF00FF00u) | ((p & 0xFFu) << 16) | ((p >> 16) & 0xFFu);
    p |= 0xFF000000u;
  }
  return true;
}

}  // namespace rs::vk
