#pragma once

#include <stdbool.h>
#include <stdint.h>

/*
 * The picture, straight to the compositor.
 *
 * host_framebuffer.h gives the launcher each finished frame as pixels, and
 * the first version of the in-process panel took them the obvious way: copy
 * into Dart, hand to decodeImageFromPixels, paint the resulting image. At
 * 752x576 that is four copies of 1.7MB per frame -- the native staging copy,
 * the Dart allocation, the decoder's copy, and the texture upload -- which is
 * why the Android panel had to be throttled to 30fps to keep the audio
 * callback fed.
 *
 * This is the way round it. Flutter can composite an external texture: a
 * surface the platform owns, which the app fills and the compositor draws
 * without the pixels ever entering the Dart heap. The launcher registers one,
 * hands the platform handle down here, and from then on a frame costs a
 * single strided memcpy from the emulator's front buffer into the buffer the
 * compositor is about to read.
 *
 * The launcher drives it: uae4arm_host_texture_present() is called once per
 * vsync from Dart through FFI, so there is no per-frame platform channel
 * traffic either. A host with no texture support leaves the sink unset, every
 * call here returns false, and the app falls back to the copy-and-decode path
 * with nothing to configure.
 */

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Fills the platform's buffer with the frame the emulator has published.
 *
 * The sink is called with no emulator lock held: it takes the framebuffer
 * lock itself, for the memcpy only, via uae4arm_host_copy_framebuffer_strided.
 * That matters because acquiring a compositor buffer can block for a whole
 * refresh, and doing so under the publisher's lock would stall the emulation
 * thread at every frame swap.
 *
 * Returns true if a frame was posted.
 */
typedef bool (*uae4arm_texture_sink)(void* context);

/** Installs the platform's sink. Passing NULL detaches. */
void uae4arm_host_texture_set_sink(uae4arm_texture_sink sink, void* context);

/** Whether a sink is installed, i.e. whether the texture path is live. */
bool uae4arm_host_texture_attached(void);

/**
 * Posts the current frame, if it is newer than the one already posted.
 *
 * Safe and cheap to call every vsync: with nothing new it is one atomic load.
 * Returns true if a frame was posted.
 */
bool uae4arm_host_texture_present(void);

/**
 * The serial of the last frame the platform actually accepted, or 0 if none
 * ever has.
 *
 * The launcher watches this. An attached sink that never posts is not a
 * theoretical case: Flutter's SurfaceProducer hands out an ImageReader surface
 * in ImageFormat.PRIVATE with GPU-sampled usage only, which ANativeWindow_lock
 * cannot write to, so every present fails and the panel stays black while the
 * audio plays on. Rather than trust any one platform to be honest about what
 * it supports, the app gives the texture path a second to prove itself and
 * drops back to copy-and-decode if nothing lands.
 */
uint64_t uae4arm_host_texture_posted(void);

#ifdef __cplusplus
}
#endif
