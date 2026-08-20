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
#include "amiberry_gfx.h"
#include "protracker.h"
#include "savestate.h"
#include "uae.h"

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#if defined(__linux__) || defined(_WIN32)
#include <SDL3/SDL.h>
#endif

extern void uae_restart(struct uae_prefs* p, int opengui, const TCHAR* cfgfile);
extern int amiberry_main(int argc, char* argv[]);
extern void apply_android_controller_remap(const int* sdl_to_target, int count);

static uae4arm_host_callbacks host_callbacks;

/* When a host temporarily enables its touch pad, remember the user's real
   port assignment so hiding the pad gives the port back exactly as it was. */
static bool onscreen_port1_override = false;
static int saved_port1_id = 0;
static int saved_port1_mode = JSEM_MODE_DEFAULT;
static int pending_external_controller_mode = -1;
static bool pending_desktop_fullscreen = false;
static std::string session_state_path;
static std::string session_config_path;
static std::string session_title;

static int pad_device(int pad);

extern void reset_parse_cmdline();

extern bool get_logfile_enabled();
extern void set_logfile_enabled(bool enabled);

void uae4arm_host_set_logfile_enabled(bool enabled)
{
	set_logfile_enabled(enabled);
}

const char* uae4arm_host_logfile_path(void)
{
	static std::string path;
	path = get_logfile_enabled() ? get_logfile_path() : std::string();
	return path.c_str();
}

int uae4arm_host_run(int argc, char** argv)
{
	/* Every run brings its own game. The parser refuses to run twice, so
	   without this the second game inherits nothing from its command line -
	   no config, no WHDLoad archive - and boots default hardware with no
	   Kickstart, which shows as a black screen. */
	reset_parse_cmdline();
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
	/* Every control the old desktop message box offered - pause, quit -
	   lives on the host GUI's own strip now, on every platform. A native
	   dialog here was a second UI, and on Linux it was a zenity process
	   that could outlive the run and hang quit. */
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
	write_log("host: on-screen controller mode %d requested\n", mode);
	if (mode == 0) {
		changed_prefs.onscreen_joystick = false;
		changed_prefs.onscreen_cd32pad = false;
		if (onscreen_port1_override) {
			changed_prefs.jports[1].id = saved_port1_id;
			changed_prefs.jports[1].mode = saved_port1_mode;
			onscreen_port1_override = false;
		}
		set_config_changed();
		return;
	}

	const int pad = mode == 2 ? UAE4ARM_HOST_PAD_CD32 : UAE4ARM_HOST_PAD_JOYSTICK;
	const int device = pad_device(pad);
	if (device < 0)
		return;
	if (!onscreen_port1_override) {
		saved_port1_id = changed_prefs.jports[1].id;
		saved_port1_mode = changed_prefs.jports[1].mode;
		onscreen_port1_override = true;
	}
	changed_prefs.jports[1].id = JSEM_JOYS + device;
	changed_prefs.jports[1].mode = mode == 2 ? JSEM_MODE_JOYSTICK_CD32 : JSEM_MODE_JOYSTICK;
	changed_prefs.onscreen_joystick = mode == 1;
	changed_prefs.onscreen_cd32pad = mode == 2;
	set_config_changed();
}

void uae4arm_host_set_external_controller_mode(int jsem_mode)
{
	pending_external_controller_mode = jsem_mode;
	changed_prefs.jports[1].mode = jsem_mode;
	/* A connected Android/SDL controller is the first physical joystick. The
	   launcher may have generated joyport1=none; selecting the external mode
	   should make that controller usable immediately. A visible virtual pad
	   temporarily owns the port and is restored by set_onscreen_controller(0). */
	if (!onscreen_port1_override)
		changed_prefs.jports[1].id = JSEM_JOYS;
	set_config_changed();
}

void uae4arm_host_apply_pending_controller_mode(void)
{
	if (pending_external_controller_mode >= 0 && !onscreen_port1_override) {
		changed_prefs.jports[1].id = JSEM_JOYS;
		changed_prefs.jports[1].mode = pending_external_controller_mode;
	}
	if (pending_desktop_fullscreen) {
		currprefs.gfx_apmode[APMODE_NATIVE].gfx_fullscreen = GFX_FULLWINDOW;
		currprefs.gfx_apmode[APMODE_RTG].gfx_fullscreen = GFX_FULLWINDOW;
		changed_prefs.gfx_apmode[APMODE_NATIVE].gfx_fullscreen = GFX_FULLWINDOW;
		changed_prefs.gfx_apmode[APMODE_RTG].gfx_fullscreen = GFX_FULLWINDOW;
	}
}

void uae4arm_host_set_desktop_fullscreen(bool enabled)
{
	pending_desktop_fullscreen = enabled;
}

void uae4arm_host_set_port0_joystick(bool joystick)
{
	/* Port 0 is the mouse port, and stays that way by default. Two-player
	   games want a second joystick there instead - JSEM_JOYS is the first
	   physical stick, +1 the second, since port 1 will have taken the
	   first. Turning it off puts the mouse back. */
	changed_prefs.jports[0].id = joystick ? JSEM_JOYS + 1 : JSEM_MICE;
	changed_prefs.jports[0].mode = joystick ? JSEM_MODE_JOYSTICK : JSEM_MODE_MOUSE;
	set_config_changed();
	write_log("host: port 0 -> %s\n", joystick ? "second joystick" : "mouse");
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

void uae4arm_host_quit(void)
{
	/* The same call the emulator's own quit menu makes. The main loop picks
	   it up on the next frame and unwinds, which is what lets the host know
	   emulation is over rather than having to guess. */
	uae_quit();
}

void uae4arm_host_set_session(const char* state_path, const char* config_path,
	const char* title)
{
	session_state_path = state_path ? state_path : "";
	session_config_path = config_path ? config_path : "";
	session_title = title ? title : "Amiga session";
}

bool uae4arm_host_save_session(void)
{
	if (session_state_path.empty() || session_config_path.empty())
		return false;
	uae4arm_host_save_state(session_state_path.c_str());
	std::error_code ec;
	const std::filesystem::path state(session_state_path);
	const std::filesystem::path directory = state.parent_path();
	std::filesystem::create_directories(directory, ec);
	if (ec || !std::filesystem::exists(state, ec))
		return false;

	const std::filesystem::path index = directory / "recent.txt";
	std::vector<std::string> lines;
	{
		std::ifstream input(index);
		std::string line;
		while (std::getline(input, line)) {
			/* timestamp \t title \t state \t config - three tabs. The state
			   path sits between the second and third; comparing a field that
			   needed a fourth tab kept every stale row, so one game pushed
			   the rest off the shelf with copies of itself. */
			const std::size_t tab = line.find('\t');
			const std::size_t second = tab == std::string::npos
				? std::string::npos : line.find('\t', tab + 1);
			const std::size_t third = second == std::string::npos
				? std::string::npos : line.find('\t', second + 1);
			if (third == std::string::npos ||
				line.substr(second + 1, third - second - 1) != session_state_path)
				lines.push_back(line);
		}
	}
	const auto now = std::chrono::duration_cast<std::chrono::milliseconds>(
		std::chrono::system_clock::now().time_since_epoch()).count();
	lines.insert(lines.begin(), std::to_string(now) + "\t" + session_title + "\t" +
		session_state_path + "\t" + session_config_path);
	while (lines.size() > 5) {
		const std::string dropped = lines.back();
		lines.pop_back();
		const std::size_t first = dropped.find('\t');
		const std::size_t second = first == std::string::npos
			? std::string::npos : dropped.find('\t', first + 1);
		const std::size_t third = second == std::string::npos
			? std::string::npos : dropped.find('\t', second + 1);
		const std::size_t fourth = third == std::string::npos
			? std::string::npos : dropped.find('\t', third + 1);
		if (fourth != std::string::npos)
			std::filesystem::remove(dropped.substr(third + 1, fourth - third - 1), ec);
	}
	std::ofstream output(index, std::ios::trunc);
	if (!output)
		return false;
	for (const std::string& line : lines)
		output << line << '\n';
	return true;
}

bool uae4arm_host_launch(const char* config_path, const char* whdload_archive)
{
	const bool have_archive = whdload_archive && *whdload_archive;
	const bool have_config = config_path && *config_path;
	if (!have_archive && !have_config)
		return false;

	/* From the machine's defaults each time: a restart that inherited the
	   last game's prefs would carry its memory, its ROM and its disks into
	   the next one. */
	default_prefs(&changed_prefs, true, 0);

	if (have_config && target_cfgfile_load(&changed_prefs, config_path, CONFIG_TYPE_ALL, 0) == 0)
		return false;

	if (have_archive)
	{
		/* The same call --autoload makes. It writes the hardware the game's
		   database entry asks for over what the config said, which is what
		   makes a WHDLoad game work. */
		whdload_auto_prefs(&changed_prefs, whdload_archive);
	}

	/* opengui 0 leaves restart_config empty, and real_main2 then takes
	   changed_prefs as they stand - which is where the new machine is. */
	uae_restart(&changed_prefs, 0, nullptr);
	return true;
}

void uae4arm_host_set_emulation_visible(bool visible)
{
	AmigaMonitor* mon = &AMonitors[0];
	if (!mon->amiga_window)
		return;
	if (visible)
		SDL_ShowWindow(mon->amiga_window);
	else
		SDL_HideWindow(mon->amiga_window);
}

/* ---- mouse ------------------------------------------------------------- */

void uae4arm_host_mouse_move(int dx, int dy)
{
	if (dx == 0 && dy == 0)
		return;
	/* setmousestate drops deltas silently when the mouse device is not
	   enabled in the current mapping, which reads as "the pointer ignores
	   me" with nothing in the log. Say so, once per run. */
	static bool reported;
	if (!reported) {
		reported = true;
		write_log("host: touch mouse first delta (port0 id=%d mode=%d)\n",
			currprefs.jports[0].id, currprefs.jports[0].mode);
	}
	/* Port 0, axes 0 and 1, relative: the fourth argument is what makes it
	   relative rather than an absolute position. */
	setmousestate(0, 0, dx, 0);
	setmousestate(0, 1, dy, 0);
}

void uae4arm_host_mouse_button(int button, bool pressed)
{
	if (button < 0 || button > 2)
		return;
	setmousebuttonstate(0, button, pressed ? 1 : 0);
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
