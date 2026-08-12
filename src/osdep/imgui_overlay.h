#pragma once

/*
 * ImGui overlay shim.
 *
 * Upstream Amiberry composites its GUI, on-screen keyboard and debugger
 * console through a shared ImGui overlay attached to the emulation window.
 * This fork has no ImGui: the host UI draws everything outside the emulator
 * surface, so the overlay never initialises and every entry point is an inline
 * no-op reporting "not initialised".
 *
 * The ImGui types are only ever passed through, so forward declarations are
 * enough and no ImGui headers are needed.
 */

struct SDL_Window;
struct SDL_Renderer;
struct ImDrawData;
struct ImFont;
struct ImGui_ImplVulkan_InitInfo;

inline void imgui_overlay_init(SDL_Window*, SDL_Renderer*, void*) {}
inline void imgui_overlay_init_vulkan(SDL_Window*, ImGui_ImplVulkan_InitInfo*) {}
inline void imgui_overlay_handle_vulkan_swapchain_change(ImGui_ImplVulkan_InitInfo*) {}
inline void imgui_overlay_shutdown() {}
inline bool imgui_overlay_is_initialized() { return false; }
inline void imgui_overlay_begin_frame() {}
inline void imgui_overlay_end_frame() {}
inline ImDrawData* imgui_overlay_get_draw_data() { return nullptr; }
inline void imgui_overlay_restore_context() {}
inline bool imgui_overlay_is_vulkan() { return false; }
inline ImFont* imgui_overlay_get_font() { return nullptr; }
inline ImFont* imgui_overlay_get_font_small() { return nullptr; }
