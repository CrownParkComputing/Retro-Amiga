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
#include "amiberry_input.h"
#include "protracker.h"
#include "savestate.h"

extern void uae_restart(struct uae_prefs* p, int opengui, const TCHAR* cfgfile);
extern int amiberry_main(int argc, char* argv[]);
extern void apply_android_controller_remap(const int* sdl_to_target, int count);

static uae4arm_host_callbacks host_callbacks;

int uae4arm_host_run(int argc, char** argv)
{
	return amiberry_main(argc, argv);
}

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

/* ---- save states ------------------------------------------------------- */

void uae4arm_host_save_state(const char* path)
{
	if (!path || !*path)
		return;
	/* Same call the emulator's own save-state menu makes: compress, no
	   dialogs, saving rather than loading. The core picks up the request on
	   the next frame. */
	savestate_initsave(path, 1, true, true);
	save_state(path, _T("Amiga-Retro"));
}

/* ---- music ------------------------------------------------------------- */
/* Straight pass-through; the player owns all the state. Kept here so a host
   binds one header rather than two. */

bool uae4arm_host_music_play(const char* path)
{
	return music_player_play(path);
}

void uae4arm_host_music_stop(void)
{
	music_player_stop();
}

void uae4arm_host_music_set_paused(bool paused)
{
	music_player_set_paused(paused);
}

bool uae4arm_host_music_is_paused(void)
{
	return music_player_is_paused();
}

bool uae4arm_host_music_is_playing(void)
{
	return music_player_is_playing();
}

const char* uae4arm_host_music_title(void)
{
	return music_player_title();
}

float uae4arm_host_music_level(void)
{
	return music_player_level();
}

void uae4arm_host_music_set_volume(float volume)
{
	music_player_set_volume(volume);
}

/* ---- inbound: host-drawn controls ------------------------------------- */

/* Number of buttons each virtual pad registers, used by release_all. */
static int pad_button_count(int pad)
{
	return pad == UAE4ARM_HOST_PAD_CD32 ? 7 : 2;
}

/* Registers on demand, then returns the device index, or -1 if the pad could
   not be registered (input device table full). */
static int pad_device(int pad)
{
	if (pad == UAE4ARM_HOST_PAD_CD32) {
		ensure_onscreen_cd32pad_registered();
		return get_onscreen_cd32pad_device_index();
	}
	if (pad == UAE4ARM_HOST_PAD_JOYSTICK) {
		ensure_onscreen_joystick_registered();
		return get_onscreen_joystick_device_index();
	}
	return -1;
}

void uae4arm_host_pad_attach(int pad)
{
	pad_device(pad);
}

void uae4arm_host_pad_axis(int pad, int axis, int value)
{
	if (axis != 0 && axis != 1)
		return;
	const int dev = pad_device(pad);
	if (dev < 0)
		return;

	if (value > UAE4ARM_HOST_AXIS_MAX)
		value = UAE4ARM_HOST_AXIS_MAX;
	else if (value < -UAE4ARM_HOST_AXIS_MAX)
		value = -UAE4ARM_HOST_AXIS_MAX;

	setjoystickstate(dev, axis, value, UAE4ARM_HOST_AXIS_MAX);
}

void uae4arm_host_pad_direction(int pad, bool left, bool right, bool up, bool down)
{
	int x = 0;
	if (left)  x -= UAE4ARM_HOST_AXIS_MAX;
	if (right) x += UAE4ARM_HOST_AXIS_MAX;

	int y = 0;
	if (up)   y -= UAE4ARM_HOST_AXIS_MAX;
	if (down) y += UAE4ARM_HOST_AXIS_MAX;

	uae4arm_host_pad_axis(pad, 0, x);
	uae4arm_host_pad_axis(pad, 1, y);
}

void uae4arm_host_pad_button(int pad, int button, bool pressed)
{
	if (button < 0 || button >= pad_button_count(pad))
		return;
	const int dev = pad_device(pad);
	if (dev < 0)
		return;
	setjoybuttonstate(dev, button, pressed ? 1 : 0);
}

void uae4arm_host_pad_release_all(int pad)
{
	const int dev = pad_device(pad);
	if (dev < 0)
		return;

	setjoystickstate(dev, 0, 0, UAE4ARM_HOST_AXIS_MAX);
	setjoystickstate(dev, 1, 0, UAE4ARM_HOST_AXIS_MAX);

	const int buttons = pad_button_count(pad);
	for (int button = 0; button < buttons; button++)
		setjoybuttonstate(dev, button, 0);
}
