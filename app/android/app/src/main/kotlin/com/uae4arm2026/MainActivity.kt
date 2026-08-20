package com.uae4arm2026

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The Flutter launcher. It owns every screen the user configures things on;
 * running a game hands off full-screen to Uae4ArmEmulatorActivity, which lives
 * in its own :sdl process.
 */
class MainActivity : FlutterActivity() {

	private companion object {
		const val CHANNEL = "uae4arm2026/emulator"

		/**
		 * The launcher's ProTracker player, which lives in the same native
		 * library as the emulator but is independent of it: it opens its own
		 * audio device and plays while nothing is emulating.
		 *
		 * Loaded lazily, on the first music call. The library is tens of
		 * megabytes and the launcher may never play anything; loading it at
		 * startup would slow every cold start for a feature most sessions do
		 * not touch. The emulator process loads its own copy separately.
		 */
		private var musicLibraryLoaded = false

		fun ensureMusicLibrary(activity: android.app.Activity): Boolean {
			if (musicLibraryLoaded) return true
			return try {
				System.loadLibrary("uae4arm")

				// SDL's Android audio backend calls back into Java from its
				// audio thread, and aborts the process if the Java side was
				// never wired up - which it is not here, because SDL's own
				// activity lives in the :sdl process and this is the Flutter
				// one. setupJNI registers the native methods; setContext gives
				// SDL the activity it needs to attach that thread. Without
				// both, the first tune crashes in Android_AudioThreadInit.
				org.libsdl.app.SDL.setupJNI()
				org.libsdl.app.SDL.setContext(activity)

				musicLibraryLoaded = true
				true
			} catch (e: UnsatisfiedLinkError) {
				false
			}
		}

		@JvmStatic external fun nativeMusicPlay(path: String): Boolean
		@JvmStatic external fun nativeMusicStop()
		@JvmStatic external fun nativeMusicSetPaused(paused: Boolean)
		@JvmStatic external fun nativeMusicIsPlaying(): Boolean
		@JvmStatic external fun nativeMusicIsPaused(): Boolean
		@JvmStatic external fun nativeMusicTitle(): String
		@JvmStatic external fun nativeMusicLevel(): Float
		@JvmStatic external fun nativeMusicSetVolume(volume: Float)
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"launch" -> {
						val args = call.argument<List<String>>("args")
						if (args == null) {
							result.error("no_args", "launch requires an args list", null)
						} else {
							launchEmulator(args.toTypedArray())
							result.success(true)
						}
					}
					"openControllerMapping" -> {
						// Learning a pad means reading raw controller key
						// events, which is the Activity's job rather than
						// Flutter's - so this hands over to the native screen.
						startActivity(android.content.Intent(this, ControllerMapActivity::class.java))
						result.success(true)
					}
					"appBuildStamp" -> {
						// Changes on every install, which is what tells the launcher a
						// new build has been deployed - no version number to bump.
						val info = packageManager.getPackageInfo(packageName, 0)
						result.success(info.lastUpdateTime.toString())
					}
					"platformName" -> result.success("android")

					// Served here rather than by path_provider, whose iOS
					// implementation pulls in an FFI package the iosbox build
					// cannot link. Keeping both platforms on the same channel
					// keeps the Dart side identical.
					"appSupportDirectory" -> result.success(filesDir.absolutePath)

					"documentsDirectory" -> result.success(filesDir.absolutePath)

					// Where the core keeps WHDBoot/, Kickstarts/ and the rest.
					// It must match what the core computes for itself, which on
					// Android is SDL_GetAndroidExternalStoragePath - the same
					// directory getExternalFilesDir(null) returns. Guessing a
					// different one would leave the boot archive somewhere the
					// booter never looks.
					"emulatorHomeDirectory" ->
						result.success(getExternalFilesDir(null)?.absolutePath)

					// Scanning for media means walking folders, which scoped
					// storage cannot do - it hands back one file at a time
					// through a picker. All-files access is the only way to
					// offer a library, and it is granted on a system screen
					// rather than in a dialog, so this can only send the user
					// there and let them come back.
					"hasAllFilesAccess" -> result.success(hasAllFilesAccess())

					"requestAllFilesAccess" -> {
						if (hasAllFilesAccess()) {
							result.success(true)
						} else {
							result.success(openAllFilesAccessSettings())
						}
					}
					"musicPlay" -> {
						val path = call.argument<String>("path")
						result.success(
							path != null && ensureMusicLibrary(this) && nativeMusicPlay(path)
						)
					}
					"musicStop" -> {
						if (ensureMusicLibrary(this)) nativeMusicStop()
						result.success(null)
					}
					"musicSetPaused" -> {
						if (ensureMusicLibrary(this)) {
							nativeMusicSetPaused(call.argument<Boolean>("paused") ?: false)
						}
						result.success(null)
					}
					"musicSetVolume" -> {
						if (ensureMusicLibrary(this)) {
							nativeMusicSetVolume(
								(call.argument<Double>("volume") ?: 1.0).toFloat()
							)
						}
						result.success(null)
					}
					// One call rather than four: the music UI polls this
					// several times a second.
					"musicState" -> {
						if (!musicLibraryLoaded) {
							// Not loaded means nothing can be playing, and
							// loading it just to answer would defeat the point
							// of loading it lazily.
							result.success(
								mapOf(
									"playing" to false,
									"paused" to false,
									"title" to "",
									"level" to 0.0,
								)
							)
						} else {
							result.success(
								mapOf(
									"playing" to nativeMusicIsPlaying(),
									"paused" to nativeMusicIsPaused(),
									"title" to nativeMusicTitle(),
									"level" to nativeMusicLevel().toDouble(),
								)
							)
						}
					}
					else -> result.notImplemented()
				}
			}
	}

	private fun hasAllFilesAccess(): Boolean {
		// Below Android 11 there is no such thing: the legacy storage
		// permission covers it, and a scan just works.
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return true
		// On Android 11 and above this is always false now: the app no longer
		// declares MANAGE_EXTERNAL_STORAGE, because an undeclared sensitive
		// permission blocks a Play release and declaring it means passing a
		// review aimed at file managers. Callers already handle false by
		// steering the user to Browse, so answering honestly is the whole fix.
		return false
	}

	private fun openAllFilesAccessSettings(): Boolean {
		// Nothing to open. Without MANAGE_EXTERNAL_STORAGE in the manifest the
		// system's all-files screen does not list this app, so sending the user
		// there was a dead end: a settings page they cannot act on. Report
		// "not granted" and let the caller show the Browse route instead.
		return false
	}

	private fun launchEmulator(args: Array<String>) {
		val intent = Intent(this, Uae4ArmEmulatorActivity::class.java)
		intent.putExtra("SDL_ARGS", args)
		startActivity(intent)
	}
}
