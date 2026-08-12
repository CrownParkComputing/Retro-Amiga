/*
 * UAE4ARM 2026 — host bridge
 *
 * The core draws no UI of its own. Everything the user configures lives in the
 * Flutter host, which talks to the core through this plain C surface:
 *
 *   outbound (core -> host)  the core asks the host to present something
 *   inbound  (host -> core)  the host drives the running emulation
 *
 * Each platform host binds the same functions — JNI on Android, the Objective-C
 * view controller on iOS, direct calls on desktop — so no core file needs to
 * know which platform it is running on.
 */

#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Argument to show_menu / uae4arm_host_show_menu.
 * -1 requests the full pause menu; 0..3 request a disk requester for that
 * floppy drive. Values match the historic gui_display() shortcut numbering. */
#define UAE4ARM_HOST_MENU_MAIN (-1)

/*
 * Installed once by the platform host, before the core starts. Any field may
 * be null, in which case the corresponding request is silently dropped — a
 * headless core is a valid configuration.
 */
typedef struct uae4arm_host_callbacks
{
	void (*show_menu)(int shortcut);
	void (*toggle_virtual_keyboard)(void);
	void (*hide_virtual_keyboard)(void);
} uae4arm_host_callbacks;

/* Passing null clears the callbacks. The struct is copied, so the caller need
 * not keep it alive. */
void uae4arm_host_set_callbacks(const uae4arm_host_callbacks* callbacks);

/* ---- outbound: core -> host ------------------------------------------- */

void uae4arm_host_show_menu(int shortcut);
/* No core path triggers these yet; they exist so a host can drive the
 * on-screen keyboard without another round of plumbing. */
void uae4arm_host_toggle_virtual_keyboard(void);
void uae4arm_host_hide_virtual_keyboard(void);

/* ---- inbound: host -> core -------------------------------------------- */

/* Amiga raw key code, not an SDL scancode. */
void uae4arm_host_send_key(int amiga_keycode, bool pressed);

void uae4arm_host_set_pause(bool paused);
void uae4arm_host_restart(void);

void uae4arm_host_insert_floppy(int drive, const char* path);
void uae4arm_host_eject_floppy(int drive);
int  uae4arm_host_get_floppy_count(void);

/* 0 = none, 1 = on-screen joystick, 2 = on-screen CD32 pad */
void uae4arm_host_set_onscreen_controller(int mode);
/* JSEM_MODE constant for port 1 (3 = joystick, 7 = CD32 pad) */
void uae4arm_host_set_external_controller_mode(int jsem_mode);

void uae4arm_host_set_correct_aspect(bool enabled);
bool uae4arm_host_get_correct_aspect(void);

/* sdl_to_target maps SDL button indices onto target button indices. */
void uae4arm_host_apply_controller_mapping(const int* sdl_to_target, int count);

#ifdef __cplusplus
}
#endif
