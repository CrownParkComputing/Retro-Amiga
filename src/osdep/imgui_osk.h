/*
 * On-screen keyboard shim.
 *
 * Upstream Amiberry draws its on-screen keyboard as an ImGui overlay. This
 * fork has no ImGui, and the host UI owns the keyboard, so every entry point
 * is an inline no-op that reports "not showing". Core code can then call these
 * unconditionally and the compiler folds the calls away.
 *
 * When the host wants to send keys it goes through uae4arm_host_send_key()
 * instead; see uae4arm_host.h.
 */

#pragma once

// D-pad / button state bitmask for imgui_osk_process() and osk_control().
#define OSK_UP     0x01
#define OSK_DOWN   0x02
#define OSK_LEFT   0x04
#define OSK_RIGHT  0x08
#define OSK_BUTTON 0x10

inline void imgui_osk_init() {}
inline void imgui_osk_shutdown() {}
inline void imgui_osk_toggle() {}
inline void imgui_osk_hide() {}
inline bool imgui_osk_is_active() { return false; }
inline bool imgui_osk_should_render() { return false; }
inline void imgui_osk_render() {}
inline bool imgui_osk_process(int, int*, int*) { return false; }
inline bool imgui_osk_handle_finger_down(float, float, int) { return false; }
inline bool imgui_osk_handle_finger_up(float, float, int) { return false; }
inline bool imgui_osk_handle_finger_motion(float, float, int) { return false; }
inline bool imgui_osk_hit_test(float, float) { return false; }
inline void imgui_osk_set_transparency(float) {}
inline void imgui_osk_set_language(const char*) {}
inline void imgui_osk_set_numpad(bool) {}
void osk_control(int x, int y, int button, int buttonstate);
