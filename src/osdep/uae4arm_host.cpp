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
#include <deque>
#include <mutex>
#include <filesystem>
#include <fstream>
#include <string>
#include <utility>
#include <vector>

#if defined(__linux__) || defined(_WIN32)
#include <SDL3/SDL.h>
#endif

#if defined(__linux__)
#include <sys/resource.h>
#include <sys/syscall.h>
#include <unistd.h>
#endif

extern void uae_restart(struct uae_prefs* p, int opengui, const TCHAR* cfgfile);
extern int amiberry_main(int argc, char* argv[]);
extern void apply_android_controller_remap(const int* sdl_to_target, int count);

static uae4arm_host_callbacks host_callbacks;

/* When a host temporarily enables its touch pad, remember the user's real
   port assignment so hiding the pad gives the port back exactly as it was. */
/* Which Amiga port the host's pad drives, and what that port held before it
 * took it over.
 *
 * This used to be hardwired to port 1, which is where most games want a
 * joystick -- but a good many of the older ones read port 0, the mouse port,
 * and on real hardware you simply moved the plug. Without that, those games
 * are unplayable however good the controls are, which is what "I can't play
 * games because only the on-screen keyboard works" comes down to for some of
 * them. See uae4arm_host_swap_pad_port. */
static int onscreen_pad_port = 1;
static bool onscreen_pad_port_override = false;
static int saved_pad_port_id = 0;
static int saved_pad_port_mode = JSEM_MODE_DEFAULT;
/* The on-screen controller mode last asked for, so a port swap can put the
 * same pad down in the other port rather than guess at one. */
static int onscreen_controller_mode = 0;
static int pending_external_controller_mode = -1;
static bool pending_desktop_fullscreen = false;
static std::string session_state_path;
static std::string session_config_path;
static std::string session_title;
static std::mutex session_lock;

static int pad_device(int pad);
static void queue_onscreen_controller_request(int mode);
static void apply_swap_pad_port(void);
static void queue_external_controller_mode_request(int jsem_mode);
static void reset_host_queues(void);

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

namespace {

/*
 * The emulation thread has to outrank the launcher's.
 *
 * This is the one thing the old design got for free and the in-process one
 * does not. The emulator used to have a process to itself; now it is a thread
 * inside the Flutter app, next to the UI thread, the raster thread, the Dart
 * GC and whatever the platform channels are doing -- all of which Android
 * schedules at or above an ordinary thread's priority, because they are what
 * draws the screen.
 *
 * Nothing in the tree ever raised it. Amiberry's own setpriority() is driven
 * from window activation events that headless never receives, and its default
 * is NORMAL in any case. So the thread generating audio ran at the same
 * priority as everything competing with it, and every scheduling gap longer
 * than a buffer became an underrun. That is the "tears up music", "audio has
 * deteriorated", "hopeless optimization" report: not the mixer, the scheduler.
 *
 * -2, and the exact number matters in both directions.
 *
 * The first attempt used -10, the shape of THREAD_PRIORITY_URGENT_DISPLAY.
 * That is AHEAD of Flutter's UI thread (-4) and its raster thread (-8), and
 * the result was worse than the problem: a collection driving a large RTG
 * screen kept the emulation thread runnable more or less permanently, the
 * launcher's own threads stopped getting scheduled, and the app became
 * unresponsive -- including the controls for leaving the game. A slow setup
 * is a nuisance; a slow setup you cannot get out of is a trap.
 *
 * -2 lifts this above ordinary background work -- which is what was causing
 * the underruns -- while leaving the threads that draw the launcher ahead of
 * it. The audio callback SDL runs is higher still and unaffected either way.
 *
 * An app may do this to its own threads: Android raises RLIMIT_NICE for app
 * processes precisely so it can. Where it may not (an unprivileged desktop)
 * the call fails, is logged once, and the emulator runs exactly as it did.
 */
void raise_emulation_thread_priority()
{
#if defined(__linux__)
	errno = 0;
	if (setpriority(PRIO_PROCESS, static_cast<id_t>(syscall(SYS_gettid)), -2) != 0 &&
	    errno != 0) {
		write_log("emulation thread: could not raise priority (%s); audio may "
			"break up under load\n", strerror(errno));
		return;
	}
	write_log("emulation thread: priority raised to nice -2\n");
#endif
}

}  // namespace

int uae4arm_host_run(int argc, char** argv)
{
	raise_emulation_thread_priority();
	/* Every run brings its own game. The parser refuses to run twice, so
	   without this the second game inherits nothing from its command line -
	   no config, no WHDLoad archive - and boots default hardware with no
	   Kickstart, which shows as a black screen. */
	reset_parse_cmdline();
	const int result = amiberry_main(argc, argv);
	/* Clear input left by a finger/controller releasing while the core was
	 * unwinding. Doing this before amiberry_main races the newly spawned host
	 * UI, which can legitimately enqueue its controller setup immediately. */
	reset_host_queues();
	return result;
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

namespace {

struct CoreCommand {
	enum class Kind {
		Key,
		Pause,
		Restart,
		InsertFloppy,
		EjectFloppy,
		Port0Joystick,
		SwapPadPort,
		CorrectAspect,
		MouseMove,
		MouseButton,
		SaveSession,
		SaveState,
		Launch,
		Quit
	};

	Kind kind;
	int a = 0;
	int b = 0;
	bool flag = false;
	std::string path;
	std::string extra;
	std::string title;
};

std::mutex core_command_lock;
std::deque<CoreCommand> core_commands;
constexpr size_t CORE_COMMAND_SOFT_MAX = 512;

bool core_command_is_coalescable(CoreCommand::Kind kind)
{
	return kind == CoreCommand::Kind::MouseMove ||
		kind == CoreCommand::Kind::Pause ||
		kind == CoreCommand::Kind::CorrectAspect ||
		kind == CoreCommand::Kind::Port0Joystick;
}

void core_command_enqueue(CoreCommand command)
{
	std::lock_guard<std::mutex> guard(core_command_lock);

	/* Pointer motion is a delta, so consecutive reports combine. This keeps a
	 * busy Flutter gesture from filling the queue without dropping distance. */
	if (command.kind == CoreCommand::Kind::MouseMove && !core_commands.empty() &&
		core_commands.back().kind == CoreCommand::Kind::MouseMove) {
		CoreCommand& previous = core_commands.back();
		previous.a = std::clamp(previous.a + command.a, -32767, 32767);
		previous.b = std::clamp(previous.b + command.b, -32767, 32767);
		return;
	}

	/* Only the latest state matters for these switches. Do not do this for
	 * keys/buttons: losing a release produces a permanently held control. */
	if (core_command_is_coalescable(command.kind)) {
		for (auto it = core_commands.rbegin(); it != core_commands.rend(); ++it) {
			if (it->kind == command.kind) {
				*it = std::move(command);
				return;
			}
		}
	}

	if (core_commands.size() >= CORE_COMMAND_SOFT_MAX) {
		auto disposable = std::find_if(core_commands.begin(), core_commands.end(),
			[](const CoreCommand& queued) {
				return core_command_is_coalescable(queued.kind);
			});
		if (disposable != core_commands.end())
			core_commands.erase(disposable);
		else if (core_command_is_coalescable(command.kind))
			return;
		/* Critical commands may exceed the soft cap briefly. A key-up, save or
		 * quit is safer than a stuck key or a session silently not saved. */
	}
	core_commands.push_back(std::move(command));
}

void clear_core_commands()
{
	std::lock_guard<std::mutex> guard(core_command_lock);
	core_commands.clear();
}

} // namespace

void uae4arm_host_send_key(int amiga_keycode, bool pressed)
{
	CoreCommand command{CoreCommand::Kind::Key};
	command.a = amiga_keycode;
	command.flag = pressed;
	core_command_enqueue(std::move(command));
}

void uae4arm_host_set_pause(bool paused)
{
	CoreCommand command{CoreCommand::Kind::Pause};
	command.flag = paused;
	core_command_enqueue(std::move(command));
}

void uae4arm_host_restart(void)
{
	core_command_enqueue(CoreCommand{CoreCommand::Kind::Restart});
}

void uae4arm_host_insert_floppy(int drive, const char* path)
{
	if (drive < 0 || drive > 3 || !path || !*path)
		return;
	CoreCommand command{CoreCommand::Kind::InsertFloppy};
	command.a = drive;
	command.path = path;
	core_command_enqueue(std::move(command));
}

void uae4arm_host_eject_floppy(int drive)
{
	if (drive < 0 || drive > 3)
		return;
	CoreCommand command{CoreCommand::Kind::EjectFloppy};
	command.a = drive;
	core_command_enqueue(std::move(command));
}

int uae4arm_host_get_floppy_count(void)
{
	return currprefs.nr_floppies;
}

void uae4arm_host_set_onscreen_controller(int mode)
{
	/* The host UI and the emulator run on different threads. Registering a
	 * virtual pad or changing the input prefs here races inputdevice_vsync()
	 * and used to corrupt the input table. Queue the whole request; the same
	 * emulator-thread drain that applies button events applies this too. */
	queue_onscreen_controller_request(mode);
}

void uae4arm_host_set_external_controller_mode(int jsem_mode)
{
	queue_external_controller_mode_request(jsem_mode);
}

void uae4arm_host_apply_pending_controller_mode(void)
{
	if (pending_external_controller_mode >= 0 && !onscreen_pad_port_override) {
		changed_prefs.jports[onscreen_pad_port].id = JSEM_JOYS;
		changed_prefs.jports[onscreen_pad_port].mode = pending_external_controller_mode;
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
	CoreCommand command{CoreCommand::Kind::Port0Joystick};
	command.flag = joystick;
	core_command_enqueue(std::move(command));
}

void uae4arm_host_swap_pad_port(void)
{
	/* Queued, not applied. Moving a pad between ports rewrites jports and
	 * re-registers the device, and doing that from the UI thread is the same
	 * race that corrupts the input table -- see the note on
	 * apply_onscreen_controller_request. */
	core_command_enqueue(CoreCommand{CoreCommand::Kind::SwapPadPort});
}

int uae4arm_host_pad_port(void)
{
	return onscreen_pad_port;
}

void uae4arm_host_set_correct_aspect(bool enabled)
{
	/* Same mechanism as the AKS_AUTO_CROP_IMAGE hotkey: applied live. */
	CoreCommand command{CoreCommand::Kind::CorrectAspect};
	command.flag = enabled;
	core_command_enqueue(std::move(command));
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
	core_command_enqueue(CoreCommand{CoreCommand::Kind::Quit});
}

void uae4arm_host_set_session(const char* state_path, const char* config_path,
	const char* title)
{
	std::lock_guard<std::mutex> guard(session_lock);
	session_state_path = state_path ? state_path : "";
	session_config_path = config_path ? config_path : "";
	session_title = title ? title : "Amiga session";
}

bool uae4arm_host_save_session(void)
{
	CoreCommand command{CoreCommand::Kind::SaveSession};
	{
		std::lock_guard<std::mutex> guard(session_lock);
		if (session_state_path.empty() || session_config_path.empty())
			return false;
		command.path = session_state_path;
		command.extra = session_config_path;
		command.title = session_title;
	}
	core_command_enqueue(std::move(command));
	return true;
}

static bool perform_save_session(const CoreCommand& command)
{
	if (command.path.empty() || command.extra.empty())
		return false;
	savestate_initsave(command.path.c_str(), 1, true, true);
	save_state(command.path.c_str(), _T("Amiga-Retro"));
	std::error_code ec;
	const std::filesystem::path state(command.path);
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
				line.substr(second + 1, third - second - 1) != command.path)
				lines.push_back(line);
		}
	}
	const auto now = std::chrono::duration_cast<std::chrono::milliseconds>(
		std::chrono::system_clock::now().time_since_epoch()).count();
	lines.insert(lines.begin(), std::to_string(now) + "\t" + command.title + "\t" +
		command.path + "\t" + command.extra);
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
	if (have_config && !std::filesystem::exists(config_path))
		return false;
	CoreCommand command{CoreCommand::Kind::Launch};
	command.path = have_config ? config_path : "";
	command.extra = have_archive ? whdload_archive : "";
	core_command_enqueue(std::move(command));
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
	CoreCommand command{CoreCommand::Kind::MouseMove};
	command.a = dx;
	command.b = dy;
	core_command_enqueue(std::move(command));
}

void uae4arm_host_mouse_button(int button, bool pressed)
{
	if (button < 0 || button > 2)
		return;
	CoreCommand command{CoreCommand::Kind::MouseButton};
	command.a = button;
	command.flag = pressed;
	core_command_enqueue(std::move(command));
}

/* ---- save states ------------------------------------------------------- */

void uae4arm_host_save_state(const char* path)
{
	if (!path || !*path)
		return;
	CoreCommand command{CoreCommand::Kind::SaveState};
	command.path = path;
	core_command_enqueue(std::move(command));
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

void uae4arm_host_music_release_audio(void)
{
	music_player_release_device();
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

static void drain_core_commands()
{
	std::deque<CoreCommand> commands;
	{
		std::lock_guard<std::mutex> guard(core_command_lock);
		if (core_commands.empty())
			return;
		commands.swap(core_commands);
	}

	static bool mouse_reported = false;
	for (const CoreCommand& command : commands) {
		switch (command.kind) {
		case CoreCommand::Kind::Key:
			inputdevice_do_keyboard(command.a, command.flag ? 1 : 0);
			break;

		case CoreCommand::Kind::Pause:
			if (command.flag)
				setpaused(1);
			else
				resumepaused(1);
			break;

		case CoreCommand::Kind::Restart:
			/* opengui 0 keeps the -G no-GUI launch honoured. */
			uae_restart(&currprefs, 0, nullptr);
			break;

		case CoreCommand::Kind::InsertFloppy:
			disk_insert(command.a, command.path.c_str());
			break;

		case CoreCommand::Kind::EjectFloppy:
			disk_eject(command.a);
			break;

		case CoreCommand::Kind::Port0Joystick:
			changed_prefs.jports[0].id = command.flag ? JSEM_JOYS + 1 : JSEM_MICE;
			changed_prefs.jports[0].mode = command.flag
				? JSEM_MODE_JOYSTICK : JSEM_MODE_MOUSE;
			set_config_changed();
			write_log("host: port 0 -> %s\n",
				command.flag ? "second joystick" : "mouse");
			break;

		case CoreCommand::Kind::SwapPadPort:
			apply_swap_pad_port();
			break;

		case CoreCommand::Kind::CorrectAspect:
			changed_prefs.gfx_correct_aspect = command.flag ? 1 : 0;
			set_config_changed();
			break;

		case CoreCommand::Kind::MouseMove:
			if (!mouse_reported) {
				mouse_reported = true;
				write_log("host: touch mouse first delta (port0 id=%d mode=%d)\n",
					currprefs.jports[0].id, currprefs.jports[0].mode);
			}
			setmousestate(0, 0, command.a, 0);
			setmousestate(0, 1, command.b, 0);
			break;

		case CoreCommand::Kind::MouseButton:
			setmousebuttonstate(0, command.a, command.flag ? 1 : 0);
			break;

		case CoreCommand::Kind::SaveSession:
			perform_save_session(command);
			break;

		case CoreCommand::Kind::SaveState:
			savestate_initsave(command.path.c_str(), 1, true, true);
			save_state(command.path.c_str(), _T("Amiga-Retro"));
			break;

		case CoreCommand::Kind::Launch:
			/* From defaults each time, so the previous machine's media and RAM do
			 * not bleed into the next one. Config parsing and restart both mutate
			 * global prefs and therefore belong on this thread too. */
			default_prefs(&changed_prefs, true, 0);
			if (!command.path.empty() &&
				target_cfgfile_load(&changed_prefs, command.path.c_str(),
					CONFIG_TYPE_ALL, 0) == 0) {
				write_log("host: queued launch could not load %s\n",
					command.path.c_str());
				break;
			}
			if (!command.extra.empty())
				whdload_auto_prefs(&changed_prefs, command.extra.c_str());
			uae_restart(&changed_prefs, 0, nullptr);
			break;

		case CoreCommand::Kind::Quit:
			uae_quit();
			break;
		}
	}
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

/* Pad input arrives on whichever thread the host UI runs on - the Android
 * platform thread, the iOS main thread - while the emulator runs on its own.
 * The calls below reach the core's input-device table, and registering a pad
 * mutates that table: doing it from another thread while the emulator is
 * building or reading it corrupted the heap, aborting out of the allocator in
 * unordered_map::find during config parsing.
 *
 * So nothing is applied where it is asked for. Events are queued under a lock
 * and drained by uae4arm_host_drain_pad_events() on the emulator thread, the
 * same shape as the Android touch-neutralization request already published
 * through process_event(). */
namespace {

struct PadEvent {
	enum class Kind {
		Attach,
		Axis,
		Direction,
		Button,
		ReleaseAll,
		SetOnscreenController,
		SetExternalControllerMode
	};
	Kind kind;
	int pad;
	int a;      /* axis index, or button index */
	int value;  /* axis value, or pressed */
	bool left, right, up, down;
};

std::mutex pad_queue_lock;
std::deque<PadEvent> pad_queue;

/* A cap, not a policy: if the emulator thread stalls - a long disk seek, a
 * savestate write - a stick held down would otherwise grow this without
 * bound. Dropping the oldest keeps the newest, which is the one the player
 * is holding right now. */
constexpr size_t PAD_QUEUE_MAX = 256;

void pad_enqueue(const PadEvent& event)
{
	std::lock_guard<std::mutex> guard(pad_queue_lock);
	if (pad_queue.size() >= PAD_QUEUE_MAX) {
		/* Motion is replaceable; releases and mode changes are not. Dropping the
		 * oldest event indiscriminately is how a busy touch sequence leaves fire
		 * held forever. */
		auto disposable = std::find_if(pad_queue.begin(), pad_queue.end(),
			[](const PadEvent& queued) {
				return queued.kind == PadEvent::Kind::Axis ||
					queued.kind == PadEvent::Kind::Direction ||
					queued.kind == PadEvent::Kind::Attach;
			});
		if (disposable != pad_queue.end())
			pad_queue.erase(disposable);
		else if (event.kind == PadEvent::Kind::Axis ||
			event.kind == PadEvent::Kind::Direction ||
			event.kind == PadEvent::Kind::Attach)
			return;
	}
	pad_queue.push_back(event);
}

} // namespace

static void reset_host_queues(void)
{
	clear_core_commands();
	{
		std::lock_guard<std::mutex> guard(pad_queue_lock);
		pad_queue.clear();
	}
	onscreen_pad_port_override = false;
	onscreen_pad_port = 1;
	onscreen_controller_mode = 0;
	pending_external_controller_mode = -1;
	{
		std::lock_guard<std::mutex> guard(session_lock);
		session_state_path.clear();
		session_config_path.clear();
		session_title.clear();
	}
}

static void queue_onscreen_controller_request(int mode)
{
	if (mode < 0 || mode > 2)
		return;
	pad_enqueue(PadEvent{PadEvent::Kind::SetOnscreenController, mode, 0, 0,
		false, false, false, false});
}

static void queue_external_controller_mode_request(int jsem_mode)
{
	pad_enqueue(PadEvent{PadEvent::Kind::SetExternalControllerMode, jsem_mode,
		0, 0, false, false, false, false});
}

/* These two helpers are emulator-thread only. In particular pad_device()
 * registers a device and mutates di_joystick/num_joystick, so it must never
 * be reached directly from Flutter's platform thread. */
static void apply_onscreen_controller_request(int mode)
{
	write_log("host: on-screen controller mode %d requested\n", mode);
	onscreen_controller_mode = mode;
	if (mode == 0) {
		changed_prefs.onscreen_joystick = false;
		changed_prefs.onscreen_cd32pad = false;
		if (onscreen_pad_port_override) {
			changed_prefs.jports[onscreen_pad_port].id = saved_pad_port_id;
			changed_prefs.jports[onscreen_pad_port].mode = saved_pad_port_mode;
			onscreen_pad_port_override = false;
		}
		set_config_changed();
		return;
	}

	const int pad = mode == 2 ? UAE4ARM_HOST_PAD_CD32 : UAE4ARM_HOST_PAD_JOYSTICK;
	const int device = pad_device(pad);
	if (device < 0)
		return;
	if (!onscreen_pad_port_override) {
		saved_pad_port_id = changed_prefs.jports[onscreen_pad_port].id;
		saved_pad_port_mode = changed_prefs.jports[onscreen_pad_port].mode;
		onscreen_pad_port_override = true;
	}
	changed_prefs.jports[onscreen_pad_port].id = JSEM_JOYS + device;
	changed_prefs.jports[onscreen_pad_port].mode = mode == 2
		? JSEM_MODE_JOYSTICK_CD32 : JSEM_MODE_JOYSTICK;
	changed_prefs.onscreen_joystick = mode == 1;
	changed_prefs.onscreen_cd32pad = mode == 2;
	set_config_changed();
}

/*
 * Moves the pad to the other Amiga port, live.
 *
 * Both ports are handled as a pair of "what was here before" notes rather than
 * by swapping the two entries wholesale: the pad is a device this file
 * registered, and the port it vacates has to get back precisely what it had --
 * the mouse, a physical stick, or nothing -- or swapping twice does not return
 * the machine to where it started.
 *
 * The mouse genuinely leaves when the pad takes port 0. That is what happens
 * on the real machine when you move the plug, and it is what the games that
 * want a joystick in port 0 are expecting.
 */
static void apply_swap_pad_port(void)
{
	const int from = onscreen_pad_port;
	const int to = from == 1 ? 0 : 1;

	/* Give the port the pad is leaving back exactly what it had. */
	if (onscreen_pad_port_override) {
		changed_prefs.jports[from].id = saved_pad_port_id;
		changed_prefs.jports[from].mode = saved_pad_port_mode;
		onscreen_pad_port_override = false;
	}

	onscreen_pad_port = to;

	if (onscreen_controller_mode != 0) {
		/* Re-runs the ordinary path, which takes its own note of what the new
		 * port held. */
		apply_onscreen_controller_request(onscreen_controller_mode);
	} else {
		/* No on-screen pad is drawn, but a device is still bound to the port:
		 * a physical controller, or the touch pad with its picture hidden.
		 * That is the thing to move. */
		saved_pad_port_id = changed_prefs.jports[to].id;
		saved_pad_port_mode = changed_prefs.jports[to].mode;
		onscreen_pad_port_override = true;
		changed_prefs.jports[to].id = JSEM_JOYS;
		changed_prefs.jports[to].mode = pending_external_controller_mode >= 0
			? pending_external_controller_mode : JSEM_MODE_JOYSTICK;
	}
	set_config_changed();
	write_log("host: pad moved from port %d to port %d\n", from, to);
}

static void apply_external_controller_mode_request(int jsem_mode)
{
	pending_external_controller_mode = jsem_mode;
	changed_prefs.jports[onscreen_pad_port].mode = jsem_mode;
	/* The host-fed virtual pad is the first joystick on the in-process path.
	 * A config may say joyport1=none; selecting a controller must override it. */
	if (!onscreen_pad_port_override)
		changed_prefs.jports[onscreen_pad_port].id = JSEM_JOYS;
	set_config_changed();
}

void uae4arm_host_pad_attach(int pad)
{
	pad_enqueue(PadEvent{PadEvent::Kind::Attach, pad, 0, 0, false, false, false, false});
}

void uae4arm_host_pad_axis(int pad, int axis, int value)
{
	if (axis != 0 && axis != 1)
		return;

	if (value > UAE4ARM_HOST_AXIS_MAX)
		value = UAE4ARM_HOST_AXIS_MAX;
	else if (value < -UAE4ARM_HOST_AXIS_MAX)
		value = -UAE4ARM_HOST_AXIS_MAX;

	pad_enqueue(PadEvent{PadEvent::Kind::Axis, pad, axis, value, false, false, false, false});
}

void uae4arm_host_pad_direction(int pad, bool left, bool right, bool up, bool down)
{
	/* Queued as one event rather than two axis writes. Split across the lock
	 * a diagonal could be drained half-applied, which reads as a stick that
	 * flicks straight before it goes diagonal. */
	pad_enqueue(PadEvent{PadEvent::Kind::Direction, pad, 0, 0, left, right, up, down});
}

void uae4arm_host_pad_button(int pad, int button, bool pressed)
{
	if (button < 0 || button >= pad_button_count(pad))
		return;
	pad_enqueue(PadEvent{PadEvent::Kind::Button, pad, button, pressed ? 1 : 0,
		false, false, false, false});
}

void uae4arm_host_pad_release_all(int pad)
{
	pad_enqueue(PadEvent{PadEvent::Kind::ReleaseAll, pad, 0, 0, false, false, false, false});
}

/* Applies everything queued since the last call. Emulator thread only: this
 * is where the input-device table is touched, and the whole point of the
 * queue is that it happens on one thread. */
void uae4arm_host_drain_pad_events(void)
{
	drain_core_commands();
	std::deque<PadEvent> events;
	{
		std::lock_guard<std::mutex> guard(pad_queue_lock);
		if (pad_queue.empty())
			return;
		events.swap(pad_queue);
	}

	for (const PadEvent& event : events) {
		if (event.kind == PadEvent::Kind::SetOnscreenController) {
			apply_onscreen_controller_request(event.pad);
			continue;
		}
		if (event.kind == PadEvent::Kind::SetExternalControllerMode) {
			apply_external_controller_mode_request(event.pad);
			continue;
		}

		/* Registers on first use, on this thread. */
		const int dev = pad_device(event.pad);
		if (dev < 0)
			continue;

		/* And make sure the Amiga is actually listening to it.
		 *
		 * set_external_controller_mode writes changed_prefs, but the core
		 * applies the pending controller mode during startup - before the
		 * launcher's call arrives - and nothing re-applies it afterwards. The
		 * result was a port bound to nothing: every button reached the right
		 * device, setjoybuttonstate ran, and the machine ignored all of it
		 * because currprefs.jports[1].id was -1. Checked per drain rather than
		 * per event, and only when it is actually wrong, so this is a no-op
		 * once the port is bound. */
		const int wanted = JSEM_JOYS + dev;
		if (currprefs.jports[1].id != wanted) {
			const int mode = pending_external_controller_mode >= 0
				? pending_external_controller_mode
				: (event.pad == UAE4ARM_HOST_PAD_CD32
					? JSEM_MODE_JOYSTICK_CD32 : JSEM_MODE_JOYSTICK);
			write_log(_T("pad: binding port 1 to device %d (was %d)\n"),
				wanted, currprefs.jports[1].id);
			changed_prefs.jports[1].id = wanted;
			changed_prefs.jports[1].mode = mode;
			set_config_changed();
		}

		switch (event.kind) {
		case PadEvent::Kind::Attach:
			break; /* pad_device did it. */

		case PadEvent::Kind::Axis:
			setjoystickstate(dev, event.a, event.value, UAE4ARM_HOST_AXIS_MAX);
			break;

		case PadEvent::Kind::Direction: {
			int x = 0;
			if (event.left)  x -= UAE4ARM_HOST_AXIS_MAX;
			if (event.right) x += UAE4ARM_HOST_AXIS_MAX;
			int y = 0;
			if (event.up)   y -= UAE4ARM_HOST_AXIS_MAX;
			if (event.down) y += UAE4ARM_HOST_AXIS_MAX;
			setjoystickstate(dev, 0, x, UAE4ARM_HOST_AXIS_MAX);
			setjoystickstate(dev, 1, y, UAE4ARM_HOST_AXIS_MAX);
			break;
		}

		case PadEvent::Kind::Button:
			setjoybuttonstate(dev, event.a, event.value);
			break;

		case PadEvent::Kind::ReleaseAll: {
			setjoystickstate(dev, 0, 0, UAE4ARM_HOST_AXIS_MAX);
			setjoystickstate(dev, 1, 0, UAE4ARM_HOST_AXIS_MAX);
			const int buttons = pad_button_count(event.pad);
			for (int button = 0; button < buttons; button++)
				setjoybuttonstate(dev, button, 0);
			break;
		}

		case PadEvent::Kind::SetOnscreenController:
		case PadEvent::Kind::SetExternalControllerMode:
			break; /* Applied before pad_device(), above. */
		}
	}
}
