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
/* Desktop-only request used when the native control sheet's Return button is
 * selected. The host marshals launcher presentation back to its UI thread. */
#define UAE4ARM_HOST_MENU_QUIT (-2)

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

/* ---- logging ----------------------------------------------------------- */

/*
 * Writes the emulator's log to a file as well as to the platform log.
 *
 * On a handheld there is no console to read, and logcat needs a computer and
 * a cable. With the core running inside the launcher the app can show its own
 * emulator log on the Logs page, which is the only place a user -- or anyone
 * debugging on the device itself -- can actually see why a game did not
 * start. Call before uae4arm_host_run.
 */
void uae4arm_host_set_logfile_enabled(bool enabled);

/* Where that log is being written, or "" when logging to file is off. The
 * pointer stays valid until the next call. */
const char* uae4arm_host_logfile_path(void);

/* ---- starting the emulator -------------------------------------------- */

/*
 * Runs the emulator. Takes the same argv the command line does and does not
 * return until emulation ends.
 *
 * This exists so a host that loads the core as a library has a stable C name
 * to call. amiberry_main is C++ and exports mangled, which a dlsym'ing host
 * would have to hardcode.
 */
int uae4arm_host_run(int argc, char** argv);

/* ---- outbound: core -> host ------------------------------------------- */

void uae4arm_host_show_menu(int shortcut);
/* No core path triggers these yet; they exist so a host can drive the
 * on-screen keyboard without another round of plumbing. */
void uae4arm_host_toggle_virtual_keyboard(void);
void uae4arm_host_hide_virtual_keyboard(void);

/* ---- inbound: host -> core -------------------------------------------- */

/* Amiga raw key code, not an SDL scancode. */
void uae4arm_host_send_key(int amiga_keycode, bool pressed);

/* The Amiga mouse, for hosts that draw their own touch controls.
 *
 * Relative, because that is what the hardware is: the Amiga has no notion of
 * where the pointer is on a host screen, and a touch that jumped it to an
 * absolute position would fight whatever the guest thinks the position is.
 * Buttons are 0 left, 1 right, 2 middle. */
void uae4arm_host_mouse_move(int dx, int dy);
void uae4arm_host_mouse_button(int button, bool pressed);

void uae4arm_host_set_pause(bool paused);
void uae4arm_host_restart(void);

/* Starts a different machine without leaving the core.
 *
 * The core can only be run once in a process - it tears SDL down on the way
 * out and a second run blocks in SDL's startup - which on a host that runs it
 * on the main thread means one game per launch of the app. So a second game
 * is a RESTART rather than a new run: the prefs are replaced and the core's
 * own restart loop picks them up, exactly as its Reboot does.
 *
 * [whdload_archive] may be empty for a plain config, or an .lha, in which case
 * the booter builds the machine around it the way --autoload does. Returns
 * false if the config could not be read, in which case nothing changes and
 * whatever was running keeps running. */
bool uae4arm_host_launch(const char* config_path, const char* whdload_archive);

/* Shows or hides the emulator's window, so a host with its own launcher can
   have the screen back without ending emulation. */
void uae4arm_host_set_emulation_visible(bool visible);

/* Ends emulation, so uae4arm_host_run returns and the host gets its screen
   back. Needed where the launcher and the emulator are one process - iOS runs
   the core on the main thread, so without this there is no way out of a game
   short of killing the app. */
void uae4arm_host_quit(void);

/* Desktop hosts provide the state/config paths for the current launch.  The
 * shared core then performs the same save-and-index operation on Return that
 * Android performs in its Activity. */
void uae4arm_host_set_session(const char* state_path, const char* config_path,
	const char* title);
bool uae4arm_host_save_session(void);

void uae4arm_host_insert_floppy(int drive, const char* path);
void uae4arm_host_eject_floppy(int drive);
int  uae4arm_host_get_floppy_count(void);

/* 0 = none, 1 = on-screen joystick, 2 = on-screen CD32 pad */
void uae4arm_host_set_onscreen_controller(int mode);
/* JSEM_MODE constant for port 1 (3 = joystick, 7 = CD32 pad) */
void uae4arm_host_set_external_controller_mode(int jsem_mode);
/* Reapply the host's physical-controller request after the config parser has
 * populated changed_prefs, but before the first inputdevice_init/update. */
void uae4arm_host_apply_pending_controller_mode(void);
/* Desktop hosts use one full-window SDL surface while a game is active, so
 * the launcher cannot show through around a smaller emulation window. */
void uae4arm_host_set_desktop_fullscreen(bool enabled);

/* Puts the second physical joystick in port 0 (true) or gives the port back
 * to the mouse (false), for two-player games with two controllers plugged
 * in. Port 1 keeps the first joystick either way. */
void uae4arm_host_set_port0_joystick(bool joystick);

void uae4arm_host_set_correct_aspect(bool enabled);
bool uae4arm_host_get_correct_aspect(void);

/* sdl_to_target maps SDL button indices onto target button indices. */
void uae4arm_host_apply_controller_mapping(const int* sdl_to_target, int count);

/* ---- save states ------------------------------------------------------- */

/*
 * Asks the core to write a save state to [path].
 *
 * It is a request, not a write: the state can only be captured at a safe point
 * in the frame, so the core does it on the next vsync and this returns before
 * the file exists. A host that wants to list the state afterwards has to wait
 * for the file rather than assume it.
 *
 * Restoring is not here because it needs no API: a .uss handed to the core on
 * the command line is restored at startup.
 */
void uae4arm_host_save_state(const char* path);

/* ---- music ------------------------------------------------------------- */
/*
 * The launcher's own music, which is a ProTracker replayer on its own audio
 * device - see protracker.h. It runs whether or not anything is emulating, so
 * a host may call these before the emulator has ever started.
 */

bool uae4arm_host_music_play(const char* path);
void uae4arm_host_music_stop(void);
void uae4arm_host_music_set_paused(bool paused);
bool uae4arm_host_music_is_paused(void);
bool uae4arm_host_music_is_playing(void);
/* Valid until the next call; copy it if you need to keep it. */
const char* uae4arm_host_music_title(void);
/* 0..1 peak level, for a visualiser. */
float uae4arm_host_music_level(void);
void uae4arm_host_music_set_volume(float volume);

/* ---- inbound: host-drawn controls ------------------------------------- */
/*
 * Lets a host that draws its own touch controls feed the emulation directly.
 * Both pads are virtual input devices registered with the core's input layer,
 * so a host pad is indistinguishable from a physical one: it obeys the user's
 * port assignment and custom mappings.
 */

#define UAE4ARM_HOST_PAD_JOYSTICK 1 /* 2-button Amiga joystick */
#define UAE4ARM_HOST_PAD_CD32     2 /* 7-button CD32 pad */

/* Button indices, matching the device registration order. */
#define UAE4ARM_HOST_JOY_FIRE1  0
#define UAE4ARM_HOST_JOY_FIRE2  1

#define UAE4ARM_HOST_CD32_RED    0
#define UAE4ARM_HOST_CD32_BLUE   1
#define UAE4ARM_HOST_CD32_GREEN  2
#define UAE4ARM_HOST_CD32_YELLOW 3
#define UAE4ARM_HOST_CD32_PLAY   4
#define UAE4ARM_HOST_CD32_RWD    5
#define UAE4ARM_HOST_CD32_FFW    6

/* Full deflection on either axis; the value passed to uae4arm_host_pad_axis. */
#define UAE4ARM_HOST_AXIS_MAX 32767

/* Registers the virtual device if it is not already present. Safe to call
 * repeatedly, and cheap enough to call before each batch of input. Physical
 * devices are not re-enumerated, so custom mappings survive. */
void uae4arm_host_pad_attach(int pad);
/* Applies queued pad input. EMULATOR THREAD ONLY - the pad_* calls above may
 * be made from any thread and only enqueue; this is where the core's input
 * device table is actually touched. Called from process_event(). */
void uae4arm_host_drain_pad_events(void);

/* axis: 0 = X (left negative), 1 = Y (up negative).
 * value is clamped to +/-UAE4ARM_HOST_AXIS_MAX. */
void uae4arm_host_pad_axis(int pad, int axis, int value);

/* Digital d-pad convenience, equivalent to two uae4arm_host_pad_axis calls at
 * full deflection. Opposing directions cancel, as they do on real hardware. */
void uae4arm_host_pad_direction(int pad, bool left, bool right, bool up, bool down);

void uae4arm_host_pad_button(int pad, int button, bool pressed);

/* Releases every axis and button on the pad. Hosts should call this when the
 * touch surface is dismissed, otherwise a held direction sticks. */
void uae4arm_host_pad_release_all(int pad);

#ifdef __cplusplus
}
#endif
