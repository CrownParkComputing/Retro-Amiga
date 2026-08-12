/*
 * UAE4ARM 2026 — host bridge implementation.
 *
 * Platform-free: every function here is the same on Android, iOS and desktop.
 * Platform code contributes only the callback struct and, where the platform
 * needs marshalling, a thin shim (see android_keyboard_bridge.cpp).
 */

#include "uae4arm_host.h"

#include "sysconfig.h"
#include "sysdeps.h"
#include "options.h"
#include "disk.h"
#include "inputdevice.h"
#include "target.h"

extern void uae_restart(struct uae_prefs* p, int opengui, const TCHAR* cfgfile);
extern void apply_android_controller_remap(const int* sdl_to_target, int count);

static uae4arm_host_callbacks host_callbacks;

void uae4arm_host_set_callbacks(const uae4arm_host_callbacks* callbacks)
{
	if (callbacks)
		host_callbacks = *callbacks;
	else
		host_callbacks = uae4arm_host_callbacks{};
}

/* ---- outbound: core -> host ------------------------------------------- */

void uae4arm_host_show_menu(int shortcut)
{
	if (host_callbacks.show_menu)
		host_callbacks.show_menu(shortcut);
}

void uae4arm_host_toggle_virtual_keyboard(void)
{
	if (host_callbacks.toggle_virtual_keyboard)
		host_callbacks.toggle_virtual_keyboard();
}

void uae4arm_host_hide_virtual_keyboard(void)
{
	if (host_callbacks.hide_virtual_keyboard)
		host_callbacks.hide_virtual_keyboard();
}

/* ---- inbound: host -> core -------------------------------------------- */

void uae4arm_host_send_key(int amiga_keycode, bool pressed)
{
	inputdevice_do_keyboard(amiga_keycode, pressed ? 1 : 0);
}

void uae4arm_host_set_pause(bool paused)
{
	if (paused)
		setpaused(1);
	else
		resumepaused(1);
}

void uae4arm_host_restart(void)
{
	/* opengui 0 keeps the "-G" no-gui launch flag honoured (restart_program=2),
	   which is what an in-game Reboot should do. */
	uae_restart(&currprefs, 0, nullptr);
}

void uae4arm_host_insert_floppy(int drive, const char* path)
{
	if (drive < 0 || drive > 3 || !path || !*path)
		return;
	disk_insert(drive, path);
}

void uae4arm_host_eject_floppy(int drive)
{
	if (drive < 0 || drive > 3)
		return;
	disk_eject(drive);
}

int uae4arm_host_get_floppy_count(void)
{
	return currprefs.nr_floppies;
}

void uae4arm_host_set_onscreen_controller(int mode)
{
	changed_prefs.onscreen_joystick = (mode == 1);
	changed_prefs.onscreen_cd32pad = (mode == 2);
	set_config_changed();
}

void uae4arm_host_set_external_controller_mode(int jsem_mode)
{
	changed_prefs.jports[1].mode = jsem_mode;
	set_config_changed();
}

void uae4arm_host_set_correct_aspect(bool enabled)
{
	/* Same mechanism as the AKS_AUTO_CROP_IMAGE hotkey: applied live. */
	changed_prefs.gfx_correct_aspect = enabled ? 1 : 0;
	set_config_changed();
}

bool uae4arm_host_get_correct_aspect(void)
{
	return currprefs.gfx_correct_aspect != 0;
}

void uae4arm_host_apply_controller_mapping(const int* sdl_to_target, int count)
{
	if (!sdl_to_target || count <= 0)
		return;
	apply_android_controller_remap(sdl_to_target, count);
}
