#include "android_keyboard_bridge.h"

#ifdef __ANDROID__

#include <jni.h>

#include <SDL3/SDL_system.h>

#include "sysconfig.h"
#include "sysdeps.h"
#include "disk.h"
#include "options.h"
#include "target.h"
#include "inputdevice.h"

static constexpr int ANDROID_DEFAULT_CD_SLOT_TYPE = 0;

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

void android_toggle_virtual_keyboard()
{
	call_activity_void_method("toggleVirtualKeyboardFromNative");
}

void android_hide_virtual_keyboard()
{
	call_activity_void_method("hideVirtualKeyboardFromNative");
}

void android_show_pause_menu()
{
	call_activity_void_method("showPauseMenu");
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeSendAmigaKey(JNIEnv*, jclass, jint keycode, jint pressed)
{
	inputdevice_do_keyboard(static_cast<int>(keycode), pressed != 0 ? 1 : 0);
}

extern "C" void android_set_pause(bool paused)
{
	if (paused) {
		setpaused(1);
	} else {
		resumepaused(1);
	}
}

extern "C" void android_insert_floppy(int drive, const char* path)
{
	if (drive < 0 || drive > 3 || !path || !*path) {
		return;
	}
	disk_insert(drive, path);
}

extern "C" void android_eject_floppy(int drive)
{
	if (drive < 0 || drive > 3) {
		return;
	}
	disk_eject(drive);
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeSetPause(JNIEnv*, jclass, jboolean paused)
{
	android_set_pause(paused != 0);
}

extern void uae_restart(struct uae_prefs* p, int opengui, const TCHAR* cfgfile);

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeRestart(JNIEnv*, jclass)
{
	// opengui: 0 = normal (respects the "-G" no-gui launch flag -> restart_program=2 ->
	// no_gui=true), 1 = force nogui, -1 = force-disable nogui (i.e. force the native ImGui
	// menu open) which is NOT what an in-game "Reboot" action should do.
	uae_restart(&currprefs, 0, nullptr);
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeInsertFloppy(JNIEnv* env, jclass, jint drive, jstring path)
{
	if (!path) {
		return;
	}
	const char* utf_path = env->GetStringUTFChars(path, nullptr);
	android_insert_floppy(static_cast<int>(drive), utf_path);
	env->ReleaseStringUTFChars(path, utf_path);
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeEjectFloppy(JNIEnv*, jclass, jint drive)
{
	android_eject_floppy(static_cast<int>(drive));
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeSetOnScreenController(JNIEnv*, jclass, jint mode)
{
	// 0 = none, 1 = joystick, 2 = cd32 pad
	write_log("ANDROID_DEBUG: nativeSetOnScreenController mode=%d (was joy=%d cd32=%d)\n",
		mode, changed_prefs.onscreen_joystick, changed_prefs.onscreen_cd32pad);
	changed_prefs.onscreen_joystick = (mode == 1);
	changed_prefs.onscreen_cd32pad = (mode == 2);
	set_config_changed();
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeSetCorrectAspect(JNIEnv*, jclass, jboolean enabled)
{
	// Toggle 4:3 aspect correction (16:9/stretched native pixels when off) live,
	// same mechanism used by the AKS_AUTO_CROP_IMAGE hotkey and every ImGui panel.
	write_log("ANDROID_DEBUG: nativeSetCorrectAspect enabled=%d (currprefs was %d, changed_prefs was %d)\n",
		(int)enabled, currprefs.gfx_correct_aspect, changed_prefs.gfx_correct_aspect);
	changed_prefs.gfx_correct_aspect = enabled != 0 ? 1 : 0;
	set_config_changed();
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeGetCorrectAspect(JNIEnv*, jclass)
{
	return currprefs.gfx_correct_aspect != 0;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeGetFloppyCount(JNIEnv*, jclass)
{
	return currprefs.nr_floppies;
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeSetExternalControllerMode(JNIEnv*, jclass, jint mode)
{
	// mode = JSEM_MODE constant (3 = joystick, 7 = cd32)
	// Set port 1 (the primary joystick port) to the requested mode
	changed_prefs.jports[1].mode = mode;
	set_config_changed();
}

extern void apply_android_controller_remap(const int* sdl_to_target, int count);

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_Uae4ArmEmulatorActivity_nativeApplyControllerMapping(JNIEnv* env, jclass, jintArray sdlToTarget)
{
	if (!sdlToTarget) return;
	int len = env->GetArrayLength(sdlToTarget);
	jint* data = env->GetIntArrayElements(sdlToTarget, nullptr);
	if (data) {
		apply_android_controller_remap(data, len);
		env->ReleaseIntArrayElements(sdlToTarget, data, JNI_ABORT);
	}
}

#else

void android_toggle_virtual_keyboard() {}
void android_hide_virtual_keyboard() {}
extern "C" void android_set_pause(bool) {}
extern "C" void android_insert_floppy(int, const char*) {}
extern "C" void android_eject_floppy(int) {}

#endif