/*
 * Android host shim.
 *
 * Marshalling only: every JNI entry point forwards straight to the
 * platform-neutral surface in uae4arm_host.h, and the outbound callbacks call
 * back into the emulator Activity. No emulation logic lives here.
 */

#include "android_keyboard_bridge.h"
#include "uae4arm_host.h"

#ifdef __ANDROID__

#include <jni.h>

#include <SDL3/SDL_system.h>

static void call_activity_void_method(const char* method_name)
{
	JNIEnv* env = static_cast<JNIEnv*>(SDL_GetAndroidJNIEnv());
	if (!env) {
		return;
	}

	jobject activity = static_cast<jobject>(SDL_GetAndroidActivity());
	if (!activity) {
		return;
	}

	jclass activity_class = env->GetObjectClass(activity);
	if (!activity_class) {
		env->DeleteLocalRef(activity);
		return;
	}

	jmethodID method = env->GetMethodID(activity_class, method_name, "()V");
	if (method) {
		env->CallVoidMethod(activity, method);
	}

	env->DeleteLocalRef(activity_class);
	env->DeleteLocalRef(activity);
}

static void android_show_menu(int shortcut)
{
	/* The Activity presents one pause menu; disk requesters (shortcut >= 0) are
	   reached from inside it rather than as a separate host surface. */
	if (shortcut == UAE4ARM_HOST_MENU_MAIN) {
		call_activity_void_method("showPauseMenu");
	}
}

static void android_toggle_vkbd()
{
	call_activity_void_method("toggleVirtualKeyboardFromNative");
}

static void android_hide_vkbd()
{
	call_activity_void_method("hideVirtualKeyboardFromNative");
}

void android_install_host_callbacks()
{
	const uae4arm_host_callbacks callbacks = {
		android_show_menu,
		android_toggle_vkbd,
		android_hide_vkbd,
	};
	uae4arm_host_set_callbacks(&callbacks);
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeSendAmigaKey(JNIEnv*, jclass, jint keycode, jint pressed)
{
	uae4arm_host_send_key(static_cast<int>(keycode), pressed != 0);
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeMouseMove(JNIEnv*, jclass, jint dx, jint dy)
{
	uae4arm_host_mouse_move(static_cast<int>(dx), static_cast<int>(dy));
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeMouseButton(JNIEnv*, jclass, jint button, jboolean pressed)
{
	uae4arm_host_mouse_button(static_cast<int>(button), pressed != 0);
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeSetPause(JNIEnv*, jclass, jboolean paused)
{
	uae4arm_host_set_pause(paused != 0);
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeRestart(JNIEnv*, jclass)
{
	uae4arm_host_restart();
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeInsertFloppy(JNIEnv* env, jclass, jint drive, jstring path)
{
	if (!path) {
		return;
	}
	const char* utf_path = env->GetStringUTFChars(path, nullptr);
	uae4arm_host_insert_floppy(static_cast<int>(drive), utf_path);
	env->ReleaseStringUTFChars(path, utf_path);
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeEjectFloppy(JNIEnv*, jclass, jint drive)
{
	uae4arm_host_eject_floppy(static_cast<int>(drive));
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeSetOnScreenController(JNIEnv*, jclass, jint mode)
{
	uae4arm_host_set_onscreen_controller(static_cast<int>(mode));
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeSetCorrectAspect(JNIEnv*, jclass, jboolean enabled)
{
	uae4arm_host_set_correct_aspect(enabled != 0);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeGetCorrectAspect(JNIEnv*, jclass)
{
	return uae4arm_host_get_correct_aspect();
}

extern "C" JNIEXPORT jint JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeGetFloppyCount(JNIEnv*, jclass)
{
	return uae4arm_host_get_floppy_count();
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeSetExternalControllerMode(JNIEnv*, jclass, jint mode)
{
	uae4arm_host_set_external_controller_mode(static_cast<int>(mode));
}

/* Host-drawn touch controls. The Flutter overlay owns the pad and feeds the
   emulated one through these; see uae4arm_host.h. */

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativePadAttach(JNIEnv*, jclass, jint pad)
{
	uae4arm_host_pad_attach(static_cast<int>(pad));
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativePadDirection(JNIEnv*, jclass, jint pad,
	jboolean left, jboolean right, jboolean up, jboolean down)
{
	uae4arm_host_pad_direction(static_cast<int>(pad), left, right, up, down);
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativePadButton(JNIEnv*, jclass, jint pad,
	jint button, jboolean pressed)
{
	uae4arm_host_pad_button(static_cast<int>(pad), static_cast<int>(button), pressed);
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativePadReleaseAll(JNIEnv*, jclass, jint pad)
{
	uae4arm_host_pad_release_all(static_cast<int>(pad));
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeApplyControllerMapping(JNIEnv* env, jclass, jintArray sdlToTarget)
{
	if (!sdlToTarget) return;
	int len = env->GetArrayLength(sdlToTarget);
	jint* data = env->GetIntArrayElements(sdlToTarget, nullptr);
	if (data) {
		uae4arm_host_apply_controller_mapping(data, len);
		env->ReleaseIntArrayElements(sdlToTarget, data, JNI_ABORT);
	}
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeSaveState(JNIEnv* env, jclass, jstring path)
{
	if (!path) return;
	const char* utf = env->GetStringUTFChars(path, nullptr);
	if (utf) {
		uae4arm_host_save_state(utf);
		env->ReleaseStringUTFChars(path, utf);
	}
}

/* ---- music -------------------------------------------------------------
 *
 * Bound to MainActivity, not the emulator activity: on Android the emulator
 * runs in its own :sdl process, and the launcher's music has to play in the
 * Flutter process while nothing is emulating. Both processes load the same
 * .so, and the player's state is per-process, which is what we want - the
 * launcher's music stops mattering the moment the emulator takes over.
 */

extern "C" JNIEXPORT jboolean JNICALL
Java_com_uae4arm2026_MainActivity_nativeMusicPlay(JNIEnv* env, jclass, jstring path)
{
	if (!path) return JNI_FALSE;
	const char* utf = env->GetStringUTFChars(path, nullptr);
	const bool ok = utf && uae4arm_host_music_play(utf);
	if (utf) env->ReleaseStringUTFChars(path, utf);
	return ok ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_MainActivity_nativeMusicStop(JNIEnv*, jclass)
{
	uae4arm_host_music_stop();
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_MainActivity_nativeMusicSetPaused(JNIEnv*, jclass, jboolean paused)
{
	uae4arm_host_music_set_paused(paused != JNI_FALSE);
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_MainActivity_nativeMusicReleaseAudio(JNIEnv*, jclass)
{
	uae4arm_host_music_release_audio();
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_uae4arm2026_MainActivity_nativeMusicIsPlaying(JNIEnv*, jclass)
{
	return uae4arm_host_music_is_playing() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_uae4arm2026_MainActivity_nativeMusicIsPaused(JNIEnv*, jclass)
{
	return uae4arm_host_music_is_paused() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_uae4arm2026_MainActivity_nativeMusicTitle(JNIEnv* env, jclass)
{
	return env->NewStringUTF(uae4arm_host_music_title());
}

extern "C" JNIEXPORT jfloat JNICALL
Java_com_uae4arm2026_MainActivity_nativeMusicLevel(JNIEnv*, jclass)
{
	return uae4arm_host_music_level();
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_MainActivity_nativeMusicSetVolume(JNIEnv*, jclass, jfloat volume)
{
	uae4arm_host_music_set_volume(volume);
}

#else

void android_install_host_callbacks() {}

#endif
