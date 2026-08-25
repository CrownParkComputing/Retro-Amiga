/*
 * The platform half of host_texture.h.
 *
 * Android only. On Apple the sink is written in Swift, against CVPixelBuffer
 * and FlutterTexture, and installs itself through the same plain-C
 * uae4arm_host_texture_set_sink() -- so there is nothing to compile here for
 * it. Everywhere else the file is deliberately empty and the launcher falls
 * back to copy-and-decode.
 */

#include "sysconfig.h"
#include "sysdeps.h"

#include "host_texture.h"

#ifdef __ANDROID__

#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <jni.h>

#include <mutex>

#include "host_framebuffer.h"

namespace {

/*
 * Guards the window pointer, not the pixels.
 *
 * present() runs on the Dart UI thread once per vsync; attach and detach run
 * on the platform thread whenever Flutter recreates the surface -- a rotation,
 * a return from the background. Without this, a detach landing between the
 * null check and the lock is a use-after-free on a pointer the compositor has
 * already released.
 */
std::mutex g_window_mutex;
ANativeWindow* g_window = nullptr;

bool fill_window(void* /*context*/)
{
	std::lock_guard<std::mutex> lock(g_window_mutex);
	if (g_window == nullptr)
		return false;

	int want_width = 0;
	int want_height = 0;
	uae4arm_host_framebuffer_size(&want_width, &want_height);
	if (want_width <= 0 || want_height <= 0)
		return false;

	/*
	 * The surface's size is not ours to change.
	 *
	 * Flutter's SurfaceProducer is backed by an ImageReader, whose Surface has
	 * the size the reader was created with; ANativeWindow_setBuffersGeometry
	 * on it is either ignored or refused, depending on the device. So the Java
	 * side resizes the producer when the Amiga changes mode, and this waits
	 * for the surface to catch up rather than writing a 752-wide picture into
	 * a 720-wide buffer -- or, worse, writing a smaller one into a larger
	 * buffer and leaving the margin full of whatever was there before.
	 *
	 * A mode change therefore drops a frame or two. The Amiga changes mode at
	 * a screen boundary, where there is nothing to see anyway.
	 */
	if (want_width != ANativeWindow_getWidth(g_window) ||
	    want_height != ANativeWindow_getHeight(g_window))
		return false;

	ANativeWindow_Buffer buffer;
	if (ANativeWindow_lock(g_window, &buffer, nullptr) != 0)
		return false;

	/*
	 * The one copy the whole texture path costs: emulator front buffer to
	 * compositor buffer, strided, under the framebuffer lock and nothing
	 * else. The buffer we are writing into is not the one being scanned out,
	 * so the lock is held for a memcpy and no longer.
	 */
	const int written = uae4arm_host_copy_framebuffer_strided(
		static_cast<uint32_t*>(buffer.bits), buffer.stride, buffer.height,
		nullptr, nullptr, nullptr);

	/* Post either way. Unlocking without posting leaves the buffer dequeued
	 * and the next lock fails, which turns one refused frame into a dead
	 * picture. */
	ANativeWindow_unlockAndPost(g_window);
	return written > 0;
}

void detach_locked()
{
	if (g_window != nullptr) {
		ANativeWindow_release(g_window);
		g_window = nullptr;
	}
}

}  // namespace

extern "C" {

JNIEXPORT jboolean JNICALL
Java_com_uae4arm2026_AmigaTexturePlugin_nativeAttachSurface(
	JNIEnv* env, jclass /*clazz*/, jobject surface)
{
	ANativeWindow* window =
		surface != nullptr ? ANativeWindow_fromSurface(env, surface) : nullptr;
	{
		std::lock_guard<std::mutex> lock(g_window_mutex);
		detach_locked();
		g_window = window;
	}
	if (window == nullptr) {
		uae4arm_host_texture_set_sink(nullptr, nullptr);
		return JNI_FALSE;
	}
	uae4arm_host_texture_set_sink(fill_window, nullptr);
	return JNI_TRUE;
}

/*
 * The frame loop is driven from Java, not from Dart.
 *
 * A Choreographer callback on the platform thread is already running at the
 * display's rate, and from there a frame costs two JNI calls into this file
 * and one memcpy. Driving it from Dart instead would mean either a platform
 * channel message per frame or a second FFI surface, both to arrive at the
 * same place a vsync later.
 */
JNIEXPORT jboolean JNICALL
Java_com_uae4arm2026_AmigaTexturePlugin_nativePresent(
	JNIEnv* /*env*/, jclass /*clazz*/)
{
	return uae4arm_host_texture_present() ? JNI_TRUE : JNI_FALSE;
}

/** Packs the Amiga's current mode into one call: width in the high 32 bits. */
JNIEXPORT jlong JNICALL
Java_com_uae4arm2026_AmigaTexturePlugin_nativeFrameSize(
	JNIEnv* /*env*/, jclass /*clazz*/)
{
	int width = 0;
	int height = 0;
	uae4arm_host_framebuffer_size(&width, &height);
	return (static_cast<jlong>(width) << 32) |
		(static_cast<jlong>(height) & 0xFFFFFFFFLL);
}

JNIEXPORT void JNICALL
Java_com_uae4arm2026_AmigaTexturePlugin_nativeDetachSurface(
	JNIEnv* /*env*/, jclass /*clazz*/)
{
	/* Sink first: present() must stop before the window it would write to is
	 * released, not after. */
	uae4arm_host_texture_set_sink(nullptr, nullptr);
	std::lock_guard<std::mutex> lock(g_window_mutex);
	detach_locked();
}

}  // extern "C"

#else

/* ISO C++ forbids an empty translation unit. */
extern "C" void uae4arm_host_texture_platform_unused(void);
void uae4arm_host_texture_platform_unused(void) {}

#endif  /* __ANDROID__ */
