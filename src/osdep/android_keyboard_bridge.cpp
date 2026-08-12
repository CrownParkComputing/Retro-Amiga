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

#else

void android_install_host_callbacks() {}

#endif
