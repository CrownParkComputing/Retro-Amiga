/*
 * protracker.h - a ProTracker replayer, and the player that drives it.
 *
 * Two layers, on purpose:
 *
 *   ProTracker      pure decode and mix. No audio device, no files, no
 *                   threads: give it bytes, ask it for samples. That is what
 *                   makes it testable on a desktop with no sound card.
 *   music_player_*  opens SDL audio and pushes those samples at it.
 */

#pragma once

#include <cstddef>
#include <cstdint>

struct ProTracker;

/* ---- the replayer ------------------------------------------------------ */

/* Parses a module. Returns null if the bytes are not one. The buffer is not
   retained; everything needed is copied. */
ProTracker* protracker_load(const void* bytes, size_t length);
void protracker_free(ProTracker* mod);

/* Rewinds to the start and sets the output rate. Call before rendering. */
void protracker_start(ProTracker* mod, int sample_rate);

/* Mixes [frames] stereo frames of signed 16-bit interleaved audio, replacing
   whatever is in [out]. Always fills the buffer; silence if there is nothing
   to play. */
void protracker_render(ProTracker* mod, int16_t* out, int frames);

/* The 20-character name the composer typed, or "". */
const char* protracker_title(const ProTracker* mod);

/* Peak level of the last block, 0..1, for a visualiser. */
float protracker_level(const ProTracker* mod);

bool protracker_finished(const ProTracker* mod);

/* ---- the player -------------------------------------------------------- */
/*
 * One tune at a time, on its own SDL audio stream. Independent of the
 * emulator's audio: the workbench plays music while nothing is emulating, and
 * the emulator's own sound is a separate device that opens later.
 */

/* Loads and plays [path]. Any tune already playing is stopped first. Returns
   false if the file could not be read or is not a module. */
bool music_player_play(const char* path);

void music_player_stop(void);

/* Pausing keeps the tune loaded, so resuming continues rather than restarts. */
void music_player_set_paused(bool paused);
bool music_player_is_paused(void);

/* True while a tune is loaded, whether or not it is paused. */
bool music_player_is_playing(void);

/* The playing tune's internal title, or "" when nothing is loaded. */
const char* music_player_title(void);

/* 0..1, for the workbench equaliser. */
float music_player_level(void);

/* 0..1. Applies immediately and persists across tunes. */
void music_player_set_volume(float volume);
float music_player_get_volume(void);
