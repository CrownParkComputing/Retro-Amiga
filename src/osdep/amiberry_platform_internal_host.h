#pragma once

#include "host_framebuffer.h"

// Returns true if mouse activation should be skipped when no SDL window exists.
// Host always has a window, so this guard is unnecessary — return false.
// Libretro returns true since it runs without an SDL window.
static inline bool osdep_platform_require_window_for_mouse()
{
	return false;
}

static inline bool osdep_platform_use_event_pump()
{
	return true;
}

static inline bool osdep_platform_should_delay_on_pause()
{
	return true;
}

static inline bool osdep_platform_init_sdl()
{
	/* No SDL joystick/gamepad subsystem when the host draws the picture.
	 *
	 * On Android those subsystems are backed by SDLControllerManager, a Java
	 * class SDLActivity creates -- and with the core running inside the
	 * launcher's process there is no SDLActivity. The joystick thread then
	 * calls pollInputDevices() on a null object and the whole app aborts
	 * about two seconds after boot. Input reaches the core through the host
	 * pad API (uae4arm_host_pad_*) from the launcher's own UI in this mode,
	 * so SDL's controller enumeration is not wanted here in the first place. */
	const Uint32 subsystems = SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_EVENTS
		| (uae4arm_host_framebuffer_output()
			? 0u
			: (SDL_INIT_JOYSTICK | SDL_INIT_GAMEPAD));
	if (!SDL_Init(subsystems))
	{
		write_log("SDL could not initialize! SDL_Error: %s\n", SDL_GetError());
		int num = SDL_GetNumVideoDrivers();
		for (int i = 0; i < num; ++i) {
			write_log("Video Driver %d: %s\n", i, SDL_GetVideoDriver(i));
		}
		return false;
	}
	write_log("SDL audio driver: %s\n",
		SDL_GetCurrentAudioDriver() ? SDL_GetCurrentAudioDriver() : "none");

	// SDL 3.2.x KMSDRM's default triple-buffer path leaves interval-0 page flips
	// asynchronous, avoiding the immediate drain imposed by the double-buffer
	// hint. Keep that lower-latency path; the shared-window terminal guard avoids
	// submitting another GUI flip after the exit decision.
	// SDL 3.4+ uses the hint for its existing blocking atomic presentation path.
	const char* video_driver = SDL_GetCurrentVideoDriver();
	if (video_driver && SDL_strcasecmp(video_driver, "kmsdrm") == 0) {
		if (SDL_GetVersion() < SDL_VERSIONNUM(3, 4, 0)) {
			write_log("KMSDRM: using SDL 3.2.x default triple-buffered presentation\n");
		} else if (SDL_SetHintWithPriority(SDL_HINT_VIDEO_DOUBLE_BUFFER, "1", SDL_HINT_OVERRIDE)) {
			write_log("KMSDRM: enabled double-buffered blocking atomic presentation\n");
		} else {
			write_log("KMSDRM: failed to enable double-buffered presentation: %s\n", SDL_GetError());
		}
	}

	// Enable native IME for international text input
	SDL_SetHint(SDL_HINT_IME_IMPLEMENTED_UI, "1");

#ifdef __ANDROID__
	// Trap the Android back button so SDL delivers it as SDL_SCANCODE_AC_BACK
	// instead of letting the system handle it (which would exit/minimize the app)
	SDL_SetHint(SDL_HINT_ANDROID_TRAP_BACK_BUTTON, "1");
#endif

#ifndef AMIBERRY_IOS
	/* Not on iOS: the host runs the core inside its own process and expects to
	   run it again, and SDL's UIKit backend does not come back from SDL_Quit -
	   a second SDL_Init blocks. See osdep_platform_shutdown_sdl. */
	(void)atexit(SDL_Quit);
#endif
	return true;
}

static inline void osdep_platform_shutdown_sdl()
{
#ifdef AMIBERRY_IOS
	/* Deliberately left initialised.
	 *
	 * On iOS the launcher and the emulator share a process, so leaving a game
	 * has to leave something that can start another one. SDL's UIKit backend
	 * cannot be re-initialised: after SDL_Quit the next SDL_Init never
	 * returns, which on a host that runs the core on the main thread hangs the
	 * whole app. The same test on Linux runs the core twice with a real window
	 * without complaint, which is what places the fault in that backend rather
	 * than in the emulator.
	 *
	 * The window is destroyed by the graphics shutdown either way; what stays
	 * is SDL's own initialisation, which the next run then reuses. */
#else
	SDL_Quit();
#endif
}

static inline void osdep_platform_init_ui()
{
	normalcursor = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_DEFAULT);
	if (!normalcursor)
		normalcursor = SDL_GetDefaultCursor();
	clipboard_init();
}

static inline void osdep_platform_sync_keyboard_leds()
{
#if defined(__linux__)
	if (!amiberry_led_console_get_flags(&kbd_flags))
		return;
	if (!amiberry_led_console_get_leds(&kbd_led_status))
		return;
	if (kbd_flags & 07 & LED_CAP)
	{
		kbd_led_status |= LED_CAP;
		inputdevice_do_keyboard(AK_CAPSLOCK, 1);
	}
	else
	{
		kbd_led_status &= ~LED_CAP;
		inputdevice_do_keyboard(AK_CAPSLOCK, 0);
	}
	amiberry_led_console_set_leds(kbd_led_status);
#else
	int caps = SDL_GetModState();
	caps = caps & SDL_KMOD_CAPS;
	if (caps == SDL_KMOD_CAPS)
		kbd_led_status |= ~0x04;
	else
		kbd_led_status &= ~0x04;
#endif
}

static inline void osdep_platform_update_clipboard()
{
	auto* clipboard_uae = uae_clipboard_get_text();
	if (clipboard_uae) {
		SDL_SetClipboardText(clipboard_uae);
		uae_clipboard_free_text(clipboard_uae);
	}
}

static inline void osdep_platform_call_real_main(int argc, char** argv)
{
#ifdef __APPLE__
	SDL_PumpEvents();
	SDL_Event event;
	if (SDL_PeepEvents(&event, 1, SDL_GETEVENT, SDL_EVENT_DROP_FILE, SDL_EVENT_DROP_FILE) > 0)
	{
		write_log("Intercepted SDL_EVENT_DROP_FILE event: %s\n", event.drop.data);
		char** new_argv = new char*[argc + 2];
		for (int i = 0; i < argc; ++i)
		{
			new_argv[i] = argv[i];
		}
		new_argv[argc] = const_cast<char*>(event.drop.data);
		new_argv[argc + 1] = nullptr;
		real_main(argc + 1, new_argv);
		delete[] new_argv;
	}
	else
	{
		real_main(argc, argv);
	}
#else
	real_main(argc, argv);
#endif
}
