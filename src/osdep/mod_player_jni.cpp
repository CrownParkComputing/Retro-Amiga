// JNI bridge for the in-app MOD/XM/S3M/IT tracker player (Configurations screen's music picker
// and the boot intro's soundtrack). Deliberately self-contained and independent of the main
// Amiga emulation core/audio pipeline in sounddep/sound.cpp - this just decodes a bundled tracker
// module to PCM on request; the Kotlin side owns actually pushing that PCM to an AudioTrack.
#ifdef __ANDROID__

#include <jni.h>
#include <android/log.h>
#include <cstdint>
#include <cstring>

#include <libopenmpt/libopenmpt.h>

namespace {

	// openmpt logs go to logcat via write_log-style stderr for now; kept minimal since this is a
	// best-effort playback feature, not something the emulation core depends on.
	void openmpt_log(const char* message, void*)
	{
		if (message) {
			__android_log_print(ANDROID_LOG_INFO, "Uae4Arm-ModPlayer", "%s", message);
		}
	}

} // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_com_uae4arm2026_data_ModPlayer_nativeOpen(JNIEnv* env, jclass, jbyteArray data)
{
	if (!data) {
		return 0;
	}
	const jsize length = env->GetArrayLength(data);
	if (length <= 0) {
		return 0;
	}
	jbyte* bytes = env->GetByteArrayElements(data, nullptr);
	if (!bytes) {
		return 0;
	}

	openmpt_module* mod = openmpt_module_create_from_memory2(
		bytes, static_cast<size_t>(length),
		openmpt_log, nullptr,
		nullptr, nullptr,
		nullptr, nullptr, nullptr);

	env->ReleaseByteArrayElements(data, bytes, JNI_ABORT);

	return reinterpret_cast<jlong>(mod);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_uae4arm2026_data_ModPlayer_nativeReadStereo(JNIEnv* env, jclass, jlong handle, jshortArray buffer, jint frames)
{
	auto* mod = reinterpret_cast<openmpt_module*>(handle);
	if (!mod || !buffer || frames <= 0) {
		return 0;
	}
	jshort* out = env->GetShortArrayElements(buffer, nullptr);
	if (!out) {
		return 0;
	}
	const size_t rendered = openmpt_module_read_interleaved_stereo(
		mod, 44100, static_cast<size_t>(frames), reinterpret_cast<int16_t*>(out));
	env->ReleaseShortArrayElements(buffer, out, 0);
	return static_cast<jint>(rendered);
}

extern "C" JNIEXPORT jdouble JNICALL
Java_com_uae4arm2026_data_ModPlayer_nativeGetDurationSeconds(JNIEnv*, jclass, jlong handle)
{
	auto* mod = reinterpret_cast<openmpt_module*>(handle);
	if (!mod) {
		return 0.0;
	}
	return openmpt_module_get_duration_seconds(mod);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_uae4arm2026_data_ModPlayer_nativeGetTitle(JNIEnv* env, jclass, jlong handle)
{
	auto* mod = reinterpret_cast<openmpt_module*>(handle);
	if (!mod) {
		return env->NewStringUTF("");
	}
	const char* title = openmpt_module_get_metadata(mod, "title");
	jstring result = env->NewStringUTF(title ? title : "");
	if (title) {
		openmpt_free_string(title);
	}
	return result;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_uae4arm2026_data_ModPlayer_nativeGetArtist(JNIEnv* env, jclass, jlong handle)
{
	auto* mod = reinterpret_cast<openmpt_module*>(handle);
	if (!mod) {
		return env->NewStringUTF("");
	}
	// Most ProTracker-era .mod files have no artist field at all; the composer is traditionally
	// signed into the sample names / song message instead. Fall back to the message so the
	// scroller can still credit the author where the format allows it.
	const char* artist = openmpt_module_get_metadata(mod, "artist");
	if (!artist || !*artist) {
		if (artist) {
			openmpt_free_string(artist);
		}
		artist = openmpt_module_get_metadata(mod, "message_raw");
	}
	jstring result = env->NewStringUTF(artist ? artist : "");
	if (artist) {
		openmpt_free_string(artist);
	}
	return result;
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_data_ModPlayer_nativeSetPositionSeconds(JNIEnv*, jclass, jlong handle, jdouble seconds)
{
	auto* mod = reinterpret_cast<openmpt_module*>(handle);
	if (!mod) {
		return;
	}
	openmpt_module_set_position_seconds(mod, seconds);
}

extern "C" JNIEXPORT void JNICALL
Java_com_uae4arm2026_data_ModPlayer_nativeClose(JNIEnv*, jclass, jlong handle)
{
	auto* mod = reinterpret_cast<openmpt_module*>(handle);
	if (mod) {
		openmpt_module_destroy(mod);
	}
}

#endif // __ANDROID__
