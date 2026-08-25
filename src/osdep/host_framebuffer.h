#pragma once

#include <stdbool.h>
#include <stdint.h>

struct SDL_Surface;

/*
 * Frame output without a window.
 *
 * The Android app used to be forced into a second, full-screen Activity for
 * every game, because SDL owns its window and SDL's window owns the screen.
 * The launcher's UI vanished the moment you pressed play, and what replaced it
 * was a lookalike drawn by a second Flutter engine.
 *
 * This is the way out, and it is not a new idea in this tree: the libretro
 * platform already takes each finished Amiga frame out of
 * gfx_platform_present_frame() and hands it to its own video callback instead
 * of presenting to a window (see osdep/libretro/gfx_platform_internal.h). The
 * same tap, for the host build, gives the launcher the picture as pixels --
 * which it can draw in a panel, alongside its own chrome, on one screen.
 *
 * Disabled by default. With it off, gfx_platform_present_frame() returns false
 * and SDL presents to its window exactly as before, so the existing Activity
 * path is untouched.
 */

#ifdef __cplusplus
extern "C" {
#endif

/** Turns the tap on. Call before starting the core. */
void uae4arm_host_set_framebuffer_output(bool enabled);
bool uae4arm_host_framebuffer_output(void);

/** Cheap change check for polling hosts. No pixel buffer is locked or copied. */
uint64_t uae4arm_host_framebuffer_serial(void);

/**
 * The most recent frame, as tightly packed 32-bit pixels, or NULL before the
 * first one.
 *
 * The buffer belongs to the emulator and is swapped between two allocations,
 * so a caller that copies it out immediately never reads a half-written
 * frame. [out_width]/[out_height] receive the Amiga's current resolution,
 * which changes when a game switches mode.
 *
 * [out_serial] receives a counter that increments per published frame, so a
 * UI can skip work when nothing new has arrived rather than repainting at its
 * own refresh rate.
 */
const uint32_t* uae4arm_host_get_framebuffer(int* out_width, int* out_height,
                                             uint64_t* out_serial);

/**
 * Copies the most recent frame into [dst], atomically with respect to the
 * publisher. Returns the number of pixels written (width*height), or 0 if
 * there is no frame yet or [dst_capacity] is too small -- in which case
 * out_width/out_height still report the size that would be needed.
 *
 * Prefer this over uae4arm_host_get_framebuffer() + a copy in the caller:
 * the Amiga changes display mode at will (752x576 one frame, 756x574 the
 * next), and a caller that reads width, then height, then the pixels is
 * racing the swap between each of those reads. A tight copy made with the
 * wrong width is a picture smeared diagonally across the panel.
 */
int uae4arm_host_copy_framebuffer(uint32_t* dst, int dst_capacity,
                                  int* out_width, int* out_height,
                                  uint64_t* out_serial);

#ifdef __cplusplus
}

/** Publishes one finished frame. Called from the emulation thread. */
void uae4arm_host_publish_frame(const SDL_Surface* surface);

/**
 * Publishes the part of [surface] the Amiga is actually drawing.
 *
 * Headless allocates a 1920x1080 surface whatever the machine's real
 * resolution is, so publishing all of it would hand the app a mostly-empty
 * frame with a 720x568 picture in one corner. Width or height of zero, or
 * anything larger than the surface, falls back to the whole thing.
 */
void uae4arm_host_publish_frame_region(const SDL_Surface* surface,
                                       int used_width, int used_height);

/**
 * Publishes straight from a buffer the emulation drew into.
 *
 * Headless does NOT render into amiga_surface: doInit allocates soft buffers
 * and points avidinfo->outbuffer at one of them, so the surface stays the
 * black rectangle it was created as. Frames were being published and every
 * pixel of them was zero. The draw buffer is where the picture actually is.
 */
void uae4arm_host_publish_frame_pixels(const void* pixels, int width,
                                       int height, int pitch);
#endif
