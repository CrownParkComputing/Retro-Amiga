/*
 * music_player.cpp - plays one module through its own SDL audio stream.
 *
 * Separate from the emulator's audio on purpose. The workbench plays music
 * while nothing is emulating, and the emulator opens its own device when a
 * game starts; sharing one would mean the launcher's music dictated the
 * emulator's buffer size and rate, which is exactly backwards.
 *
 * SDL3's audio streams call back from an audio thread, so everything the
 * callback touches is behind one mutex. The lock is held only while mixing
 * into the stream, never while loading a file.
 */

#include "protracker.h"

#include <SDL3/SDL.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

extern void write_log(const char* format, ...);

namespace {

constexpr int kSampleRate = 44100;

std::mutex g_lock;
ProTracker* g_module = nullptr;
SDL_AudioStream* g_stream = nullptr;
std::string g_title;
bool g_paused = false;
float g_volume = 0.7f;

/* Mixed here first, then scaled by the volume and handed to SDL. Sized for a
   comfortable callback; SDL asks for what it wants and this loops. */
std::vector<int16_t> g_mix;

void SDLCALL feed(void* /*userdata*/, SDL_AudioStream* stream,
	int additional, int /*total*/)
{
	if (additional <= 0)
		return;

	std::lock_guard<std::mutex> guard(g_lock);
	if (!g_module)
		return;

	const int frames_wanted = additional / static_cast<int>(sizeof(int16_t) * 2);
	if (frames_wanted <= 0)
		return;

	if (static_cast<int>(g_mix.size()) < frames_wanted * 2)
		g_mix.resize(static_cast<size_t>(frames_wanted) * 2);

	if (g_paused) {
		/* Feed silence rather than starving the stream: an underrun on iOS
		   ends the audio session, and the tune would not resume. */
		memset(g_mix.data(), 0, static_cast<size_t>(frames_wanted) * 2 * sizeof(int16_t));
	} else {
		protracker_render(g_module, g_mix.data(), frames_wanted);
		if (g_volume < 0.999f) {
			const int scale = static_cast<int>(g_volume * 256.0f);
			for (int i = 0; i < frames_wanted * 2; i++)
				g_mix[i] = static_cast<int16_t>((g_mix[i] * scale) >> 8);
		}
	}

	SDL_PutAudioStreamData(stream, g_mix.data(),
		frames_wanted * static_cast<int>(sizeof(int16_t) * 2));
}

/* Opens the device on first use. The launcher may never play anything, and on
   iOS opening an audio device has side effects on the app's audio session. */
bool ensure_stream()
{
	if (g_stream)
		return true;

	if (!SDL_WasInit(SDL_INIT_AUDIO) && !SDL_InitSubSystem(SDL_INIT_AUDIO)) {
		write_log("music: SDL audio init failed: %s\n", SDL_GetError());
		return false;
	}

	SDL_AudioSpec spec;
	SDL_zero(spec);
	spec.freq = kSampleRate;
	spec.format = SDL_AUDIO_S16;
	spec.channels = 2;

	g_stream = SDL_OpenAudioDeviceStream(
		SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, feed, nullptr);
	if (!g_stream) {
		write_log("music: could not open an audio stream: %s\n", SDL_GetError());
		return false;
	}
	SDL_ResumeAudioStreamDevice(g_stream);
	return true;
}

std::vector<uint8_t> read_file(const char* path)
{
	std::vector<uint8_t> bytes;
	FILE* file = fopen(path, "rb");
	if (!file)
		return bytes;

	fseek(file, 0, SEEK_END);
	const long size = ftell(file);
	fseek(file, 0, SEEK_SET);

	/* A module is a few hundred kilobytes at most; anything far larger is not
	   one, and reading it would only waste the memory. */
	if (size > 0 && size < 8 * 1024 * 1024) {
		bytes.resize(static_cast<size_t>(size));
		if (fread(bytes.data(), 1, bytes.size(), file) != bytes.size())
			bytes.clear();
	}
	fclose(file);
	return bytes;
}

} // namespace

bool music_player_play(const char* path)
{
	if (!path || !*path)
		return false;

	const std::vector<uint8_t> bytes = read_file(path);
	if (bytes.empty()) {
		write_log("music: could not read %s\n", path);
		return false;
	}

	ProTracker* loaded = protracker_load(bytes.data(), bytes.size());
	if (!loaded) {
		write_log("music: %s is not a module\n", path);
		return false;
	}
	protracker_start(loaded, kSampleRate);

	if (!ensure_stream()) {
		protracker_free(loaded);
		return false;
	}

	ProTracker* previous = nullptr;
	{
		std::lock_guard<std::mutex> guard(g_lock);
		previous = g_module;
		g_module = loaded;
		g_title = protracker_title(loaded);
		g_paused = false;
	}
	/* Freed outside the lock: the audio thread is done with it by now, and
	   freeing under the lock would hold up the next callback. */
	protracker_free(previous);

	write_log("music: playing %s\n", g_title.empty() ? path : g_title.c_str());
	return true;
}

void music_player_stop()
{
	ProTracker* previous = nullptr;
	{
		std::lock_guard<std::mutex> guard(g_lock);
		previous = g_module;
		g_module = nullptr;
		g_title.clear();
		g_paused = false;
	}
	protracker_free(previous);
}

void music_player_set_paused(bool paused)
{
	std::lock_guard<std::mutex> guard(g_lock);
	g_paused = paused;
}

bool music_player_is_paused()
{
	std::lock_guard<std::mutex> guard(g_lock);
	return g_paused;
}

bool music_player_is_playing()
{
	std::lock_guard<std::mutex> guard(g_lock);
	return g_module != nullptr;
}

const char* music_player_title()
{
	/* Copied into a buffer rather than returning g_title.c_str(): the lock is
	   gone by the time the caller reads it, and a play() on another thread
	   would reallocate the string underneath them. */
	static char buffer[64];
	std::lock_guard<std::mutex> guard(g_lock);
	snprintf(buffer, sizeof(buffer), "%s", g_title.c_str());
	return buffer;
}

float music_player_level()
{
	std::lock_guard<std::mutex> guard(g_lock);
	return g_module && !g_paused ? protracker_level(g_module) : 0.0f;
}

void music_player_set_volume(float volume)
{
	std::lock_guard<std::mutex> guard(g_lock);
	g_volume = volume < 0 ? 0 : (volume > 1 ? 1 : volume);
}

float music_player_get_volume()
{
	std::lock_guard<std::mutex> guard(g_lock);
	return g_volume;
}
