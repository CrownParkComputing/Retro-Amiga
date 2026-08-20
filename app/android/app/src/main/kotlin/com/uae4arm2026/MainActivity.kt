package com.uae4arm2026

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
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

	/**
	 * The Dart call waiting on the folder picker.
	 *
	 * ACTION_OPEN_DOCUMENT_TREE answers through onActivityResult, which has no
	 * way back to the MethodChannel result on its own, so it is parked here for
	 * the callback to complete. Cleared on every outcome, including the user
	 * backing out, or a second attempt would be refused as "busy" forever.
	 */
	private var pendingFolderPick: MethodChannel.Result? = null

	override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
		super.onActivityResult(requestCode, resultCode, data)
		if (requestCode != MediaFolderAccess.REQUEST_PICK_FOLDER) return

		val pending = pendingFolderPick
		pendingFolderPick = null
		if (pending == null) return

		val uri: Uri? = if (resultCode == RESULT_OK) data?.data else null
		if (uri == null) {
			// Backed out of the picker: not an error, just no folder.
			pending.success(null)
			return
		}
		try {
			MediaFolderAccess.persist(this, uri)
			pending.success(uri.toString())
		} catch (e: SecurityException) {
			pending.error("not_persistable", "the folder grant could not be kept", null)
		}
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

					// Scoped storage will not let the app walk a folder like
					// /sdcard/Amiga, and the permission that would - all-files
					// access - is one Play gates behind a review aimed at file
					// managers. Instead the user grants one folder through the
					// system picker and the grant is persisted. See
					// MediaFolderAccess.
					"mediaFolderUri" ->
						result.success(MediaFolderAccess.grantedTree(this)?.toString())

					"pickMediaFolder" -> {
						// The answer arrives in onActivityResult, not here.
						// Held so that callback can complete the same Dart
						// future the user is waiting on.
						if (pendingFolderPick != null) {
							result.error(
								"busy",
								"a folder picker is already open",
								null,
							)
						} else {
							pendingFolderPick = result
							MediaFolderAccess.pickFolder(this)
						}
					}

					"forgetMediaFolder" -> {
						MediaFolderAccess.release(this)
						result.success(true)
					}

					"listMediaFolder" -> {
						val limit = call.argument<Int>("fileLimit") ?: 20000
						val tree = MediaFolderAccess.grantedTree(this)
						if (tree == null) {
							result.error("no_folder", "no folder has been granted", null)
						} else {
							// Off the main thread: a large collection is tens
							// of thousands of provider rows, and doing that on
							// the UI thread is an ANR, not a slow scan.
							Thread {
								val entries = MediaFolderAccess.enumerate(
									contentResolver,
									tree,
									limit,
								)
								val payload = entries.map {
									mapOf(
										"documentId" to it.documentId,
										"name" to it.name,
										"directory" to it.relativeDirectory,
										"size" to it.size,
									)
								}
								Handler(Looper.getMainLooper()).post {
									result.success(payload)
								}
							}.start()
						}
					}

					"copyFromMediaFolder" -> {
						val documentId = call.argument<String>("documentId")
						val destination = call.argument<String>("destination")
						val tree = MediaFolderAccess.grantedTree(this)
						if (documentId == null || destination == null) {
							result.error(
								"bad_args",
								"copyFromMediaFolder needs documentId and destination",
								null,
							)
						} else if (tree == null) {
							result.error("no_folder", "no folder has been granted", null)
						} else {
							Thread {
								val ok = MediaFolderAccess.copyDocument(
									contentResolver,
									tree,
									documentId,
									destination,
								)
								Handler(Looper.getMainLooper()).post { result.success(ok) }
							}.start()
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

	private fun launchEmulator(args: Array<String>) {
		val intent = Intent(this, Uae4ArmEmulatorActivity::class.java)
		intent.putExtra("SDL_ARGS", args)
		startActivity(intent)
	}
}
