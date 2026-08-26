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

/* The geometry this file last asked the window for. ANativeWindow_getWidth
 * reports the CURRENT buffer's size, which lags a geometry change by a frame,
 * so asking it whether a resize is needed re-requests the same size every
 * frame until the queue turns over. */
int g_geometry_width = 0;
int g_geometry_height = 0;

/* Why the picture went missing, once, rather than every frame. */
bool g_lock_failed_logged = false;

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
	 * The size IS ours to change here, and that is the point of the surface
	 * this now runs on.
	 *
	 * The first version drove a Flutter SurfaceProducer, whose surface is an
	 * ImageReader's: fixed size, ImageFormat.PRIVATE, GPU-sampled usage. A
	 * geometry request on one is refused, and -- fatally -- so is
	 * ANativeWindow_lock, because there is no CPU-writable buffer behind it to
	 * hand back. Every present failed, silently, and the panel stayed black
	 * while the audio played on. A SurfaceTexture's surface is an ordinary
	 * BufferQueue: it hands out CPU-writable buffers and it takes its geometry
	 * from whoever is producing, which is us.
	 *
	 * So a mode change is a geometry request rather than a wait, and it costs
	 * at most the frames already queued at the old size.
	 */
	if (want_width != g_geometry_width || want_height != g_geometry_height) {
		/* RGBX, not RGBA: the alpha byte is ignored by definition, so the
		 * publisher does not have to walk two million pixels a frame forcing
		 * it opaque. See the note in host_framebuffer.cpp. */
		if (ANativeWindow_setBuffersGeometry(g_window, want_width, want_height,
				WINDOW_FORMAT_RGBX_8888) != 0)
			return false;
		g_geometry_width = want_width;
		g_geometry_height = want_height;
	}

	ANativeWindow_Buffer buffer;
	if (ANativeWindow_lock(g_window, &buffer, nullptr) != 0) {
		if (!g_lock_failed_logged) {
			g_lock_failed_logged = true;
			write_log("host texture: ANativeWindow_lock refused (%dx%d); the "
				"launcher will fall back to copy-and-decode\n",
				want_width, want_height);
		}
		return false;
	}

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
	/* A new window is a new buffer queue at whatever size it was created
	 * with, so the geometry we asked the old one for says nothing about it. */
	g_geometry_width = 0;
	g_geometry_height = 0;
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
