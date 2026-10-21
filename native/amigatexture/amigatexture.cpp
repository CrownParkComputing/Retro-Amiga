/*
 * The Android texture path, disambiguated for a two-core process.
 *
 * What this replaces: the Java_...AmigaTexturePlugin_* exports used to live
 * inside libuae4arm.so (host_texture_platform.cpp), and JNI resolved them by
 * scanning every loaded library for the symbol name. That is fine with one
 * core in the process and a coin toss with two -- both export the same
 * uae4arm_host_* surface, so whichever copy of the JNI glue ART happened to
 * find first would drive the texture, and on a Copperline launch it could be
 * Amiberry's framebuffer it attached to.
 *
 * This library is therefore the only one that exports the JNI entry points,
 * and it is told explicitly which core to talk to. nativeUseCore() dlopens
 * the named library -- a second dlopen of an already-loaded library returns
 * the same handle in the same namespace, so this joins the copy Dart opened
 * rather than a second instance -- and every uae4arm_host_* call below goes
 * through pointers resolved from that handle.
 *
 * The window-management logic is the same code host_texture_platform.cpp
 * carried, with the calls made indirect. The comments that explain WHY it
 * works the way it does (ImageReader vs BufferQueue, the geometry dance,
 * lock-then-post) live with that file and are not repeated here.
 */

#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <dlfcn.h>
#include <jni.h>

#include <mutex>

namespace {

constexpr const char* kTag = "RetroAmiga";

/* The selected core and its published-frame contract. */
void* g_core = nullptr;

using SetSinkFn = void (*)(bool (*)(void*), void*);
using PresentFn = bool (*)();
using FrameSizeFn = void (*)(int*, int*);
using CopyStridedFn = int (*)(uint32_t*, int, int, int*, int*, int*);

SetSinkFn p_set_sink = nullptr;
PresentFn p_present = nullptr;
FrameSizeFn p_frame_size = nullptr;
CopyStridedFn p_copy_strided = nullptr;

/*
 * Guards the window pointer, not the pixels. present() runs on the platform
 * thread once per vsync; attach and detach run whenever Flutter recreates the
 * surface.
 */
std::mutex g_window_mutex;
ANativeWindow* g_window = nullptr;

/* The geometry this file last asked the window for; ANativeWindow_getWidth
 * lags a change by a frame, so asking it whether a resize is needed would
 * re-request the same size every frame until the queue turns over. */
int g_geometry_width = 0;
int g_geometry_height = 0;

bool g_lock_failed_logged = false;

bool fill_window(void* /*context*/)
{
	std::lock_guard<std::mutex> lock(g_window_mutex);
	if (g_window == nullptr || p_frame_size == nullptr ||
		p_copy_strided == nullptr)
		return false;

	int want_width = 0;
	int want_height = 0;
	p_frame_size(&want_width, &want_height);
	if (want_width <= 0 || want_height <= 0)
		return false;

	if (want_width != g_geometry_width || want_height != g_geometry_height) {
		/* RGBX: the alpha byte is ignored by definition, so the publisher
		 * does not have to force two million of them opaque a frame. */
		if (ANativeWindow_setBuffersGeometry(g_window, want_width,
				want_height, WINDOW_FORMAT_RGBX_8888) != 0)
			return false;
		g_geometry_width = want_width;
		g_geometry_height = want_height;
	}

	ANativeWindow_Buffer buffer;
	if (ANativeWindow_lock(g_window, &buffer, nullptr) != 0) {
		if (!g_lock_failed_logged) {
			g_lock_failed_logged = true;
			__android_log_write(
				ANDROID_LOG_WARN, kTag,
				"amigatexture: ANativeWindow_lock refused; the launcher "
				"will fall back to copy-and-decode");
		}
		return false;
	}

	const int written = p_copy_strided(
		static_cast<uint32_t*>(buffer.bits), buffer.stride, buffer.height,
		nullptr, nullptr, nullptr);

	/* Post either way: unlocking without posting leaves the buffer dequeued
	 * and the next lock fails, turning one refused frame into a dead
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
	 * with; the old geometry request says nothing about it. */
	g_geometry_width = 0;
	g_geometry_height = 0;
}

}  // namespace

extern "C" {

/*
 * Picks the core subsequent calls talk to. [library_name] is the soname the
 * app packages ("libuae4arm.so", "libcopperline_ffi.so"). dlopen returns the
 * existing handle because Dart's DynamicLibrary.open already mapped it; the
 * dlsyms then bind to the live copy.
 *
 * Called from create(), before any attach. Detaching first means a surface
 * that outlives one core's session cannot write into the other's buffers.
 */
JNIEXPORT jboolean JNICALL
Java_com_uae4arm2026_AmigaTexturePlugin_nativeUseCore(
	JNIEnv* env, jclass /*clazz*/, jstring library_name)
{
	const char* name = env->GetStringUTFChars(library_name, nullptr);
	void* handle = name != nullptr
		? dlopen(name, RTLD_NOW | RTLD_LOCAL)
		: nullptr;
	if (handle == nullptr) {
		__android_log_print(
			ANDROID_LOG_WARN, kTag,
			"amigatexture: dlopen(%s) failed: %s",
			name != nullptr ? name : "(null)", dlerror());
		env->ReleaseStringUTFChars(library_name, name);
		return JNI_FALSE;
	}
	env->ReleaseStringUTFChars(library_name, name);

	g_core = handle;
	p_set_sink = reinterpret_cast<SetSinkFn>(
		dlsym(handle, "uae4arm_host_texture_set_sink"));
	p_present = reinterpret_cast<PresentFn>(
		dlsym(handle, "uae4arm_host_texture_present"));
	p_frame_size = reinterpret_cast<FrameSizeFn>(
		dlsym(handle, "uae4arm_host_framebuffer_size"));
	p_copy_strided = reinterpret_cast<CopyStridedFn>(
		dlsym(handle, "uae4arm_host_copy_framebuffer_strided"));

	const bool complete = p_set_sink != nullptr && p_present != nullptr &&
		p_frame_size != nullptr && p_copy_strided != nullptr;
	if (!complete) {
		__android_log_write(
			ANDROID_LOG_WARN, kTag,
			"amigatexture: the selected core exports no texture contract");
		g_core = nullptr;
		return JNI_FALSE;
	}
	return JNI_TRUE;
}

JNIEXPORT jboolean JNICALL
Java_com_uae4arm2026_AmigaTexturePlugin_nativeAttachSurface(
	JNIEnv* env, jclass /*clazz*/, jobject surface)
{
	if (p_set_sink == nullptr)
		return JNI_FALSE;
	ANativeWindow* window =
		surface != nullptr ? ANativeWindow_fromSurface(env, surface) : nullptr;
	{
		std::lock_guard<std::mutex> lock(g_window_mutex);
		detach_locked();
		g_window = window;
	}
	if (window == nullptr) {
		p_set_sink(nullptr, nullptr);
		return JNI_FALSE;
	}
	p_set_sink(fill_window, nullptr);
	return JNI_TRUE;
}

/*
 * The frame loop is driven from Java, not from Dart: a Choreographer
 * callback on the platform thread is already running at the display's rate,
 * and from there a frame costs two JNI calls and one memcpy.
 */
JNIEXPORT jboolean JNICALL
Java_com_uae4arm2026_AmigaTexturePlugin_nativePresent(
	JNIEnv* /*env*/, jclass /*clazz*/)
{
	return p_present != nullptr && p_present() ? JNI_TRUE : JNI_FALSE;
}

/** Packs the Amiga's current mode into one call: width in the high 32 bits. */
JNIEXPORT jlong JNICALL
Java_com_uae4arm2026_AmigaTexturePlugin_nativeFrameSize(
	JNIEnv* /*env*/, jclass /*clazz*/)
{
	int width = 0;
	int height = 0;
	if (p_frame_size != nullptr)
		p_frame_size(&width, &height);
	return (static_cast<jlong>(width) << 32) |
		(static_cast<jlong>(height) & 0xFFFFFFFFLL);
}

JNIEXPORT void JNICALL
Java_com_uae4arm2026_AmigaTexturePlugin_nativeDetachSurface(
	JNIEnv* /*env*/, jclass /*clazz*/)
{
	/* Sink first: present() must stop before the window it writes to is
	 * released, not after. */
	if (p_set_sink != nullptr)
		p_set_sink(nullptr, nullptr);
	std::lock_guard<std::mutex> lock(g_window_mutex);
	detach_locked();
}

}  // extern "C"
