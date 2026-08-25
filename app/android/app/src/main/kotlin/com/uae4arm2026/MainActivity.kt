package com.uae4arm2026

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.hardware.input.InputManager
import android.media.AudioManager
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * The Flutter launcher. It owns every screen the user configures things on;
 * running a game hands off full-screen to Uae4ArmEmulatorActivity, which lives
 * in its own :sdl process.
 */
class MainActivity : FlutterActivity() {

	private companion object {
		const val CHANNEL = "uae4arm2026/emulator"
		private val mediaIoExecutor = Executors.newSingleThreadExecutor()

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
		@JvmStatic external fun nativeMusicReleaseAudio()
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

	/// Set once the engine is up, so controller changes can be pushed to Dart.
	private var channel: MethodChannel? = null

	/**
	 * Controllers arrive and leave while the app is running - a Bluetooth pad
	 * connects a few seconds after the app opens, a USB one is unplugged
	 * mid-game. Asking once at startup means the pad shown in the first frame
	 * is the pad shown forever, so the launcher is told when the answer
	 * changes rather than polling for it.
	 */
	private val inputDeviceListener = object : InputManager.InputDeviceListener {
		private fun notifyChanged() {
			channel?.invokeMethod(
				"gamepadChanged",
				HostSupport.realControllerConnected(),
			)
		}

		override fun onInputDeviceAdded(deviceId: Int) = notifyChanged()
		override fun onInputDeviceRemoved(deviceId: Int) = notifyChanged()
		override fun onInputDeviceChanged(deviceId: Int) = notifyChanged()
	}

	/**
	 * True while a game is running in the in-process panel.
	 *
	 * Gamepad events are only swallowed while that is the case. Outside a
	 * game the same buttons drive the launcher's own navigation, and eating
	 * them would leave a handheld unable to move around its own menus.
	 */
	private var gameRunning = false

	private val audioFocusListener = AudioManager.OnAudioFocusChangeListener { change ->
		channel?.invokeMethod(
			"audioFocusChanged",
			change == AudioManager.AUDIOFOCUS_GAIN,
		)
	}

	private fun setGameAudioFocus(running: Boolean) {
		val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
		if (running) {
			audio.requestAudioFocus(
				audioFocusListener,
				AudioManager.STREAM_MUSIC,
				AudioManager.AUDIOFOCUS_GAIN,
			)
		} else {
			audio.abandonAudioFocus(audioFocusListener)
		}
	}

	/** Last direction sent, so a repeat is not pushed on every motion event. */
	private var lastDirection = 0

	/**
	 * Feeds a physical controller into the core.
	 *
	 * SDL's Android backend learns about controllers through SDLActivity's own
	 * callbacks, and the in-process panel is not an SDLActivity: the core runs
	 * as a thread inside this Flutter activity, so it never sees the hardware
	 * and no SDL joystick is registered for it. Port 1 is bound to the first
	 * joystick, which is the virtual pad the launcher attaches - so without
	 * this, a real controller does nothing at all and hiding the on-screen pad
	 * leaves the port with no device driving it.
	 *
	 * The events are forwarded to Dart, which owns the core handle through FFI
	 * and pushes them into the same pad the on-screen controls use.
	 */
	private fun forwardDirection(left: Boolean, right: Boolean, up: Boolean, down: Boolean) {
		val packed = (if (left) 1 else 0) or (if (right) 2 else 0) or
			(if (up) 4 else 0) or (if (down) 8 else 0)
		if (packed == lastDirection) return
		lastDirection = packed
		channel?.invokeMethod(
			"physicalPadDirection",
			mapOf("left" to left, "right" to right, "up" to up, "down" to down),
		)
	}

	private fun isFromController(source: Int): Boolean =
		(source and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
			(source and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK

	override fun dispatchKeyEvent(event: KeyEvent): Boolean {
		// Forwarded whether or not a game is running, and only SWALLOWED while
		// one is. Gating the forwarding on gameRunning meant a single missed
		// setGameRunning call silently killed every button - which is exactly
		// what happened. Dart drops the event if no core is running, so a
		// stray press costs nothing.
		if (isFromController(event.source)) {
			val pressed = event.action == KeyEvent.ACTION_DOWN
			when (event.keyCode) {
				// Fire and second fire. B as well as A, because a handheld's
				// A is where a thumb rests and the Amiga only has two.
				// Fire on the whole right-hand cluster. The Amiga has two
				// buttons and a modern pad has four, and a player reaching for
				// X or Y - as a test on the Retroid immediately did - should
				// not find half the pad dead.
				KeyEvent.KEYCODE_BUTTON_A, KeyEvent.KEYCODE_DPAD_CENTER,
				KeyEvent.KEYCODE_BUTTON_X ->
					channel?.invokeMethod(
						"physicalPadButton", mapOf("button" to 0, "pressed" to pressed))
				KeyEvent.KEYCODE_BUTTON_B, KeyEvent.KEYCODE_BUTTON_Y ->
					channel?.invokeMethod(
						"physicalPadButton", mapOf("button" to 1, "pressed" to pressed))
				KeyEvent.KEYCODE_DPAD_LEFT -> forwardDirection(pressed, false, false, false)
				KeyEvent.KEYCODE_DPAD_RIGHT -> forwardDirection(false, pressed, false, false)
				KeyEvent.KEYCODE_DPAD_UP -> forwardDirection(false, false, pressed, false)
				KeyEvent.KEYCODE_DPAD_DOWN -> forwardDirection(false, false, false, pressed)
				// Anything else - Start, Select, shoulders - is left alone so
				// the system and the launcher keep working.
				else -> return super.dispatchKeyEvent(event)
			}
			// Consume only during a game. Outside one the launcher still needs
			// these to move around its own menus on a handheld.
			if (gameRunning) return true
		}
		return super.dispatchKeyEvent(event)
	}

	/**
	 * Also handled here, not only in dispatchGenericMotionEvent.
	 *
	 * A joystick's axes are delivered to the focused view first; the activity
	 * only sees what nothing else claimed. Flutter's view takes focus, so a
	 * stick can produce no dispatch at all - which is exactly what a device
	 * test showed: every button logged, not one motion event.
	 */
	override fun onGenericMotionEvent(event: MotionEvent): Boolean {
		if (handleControllerMotion(event)) return true
		return super.onGenericMotionEvent(event)
	}

	private fun handleControllerMotion(event: MotionEvent): Boolean {
		if (!isFromController(event.source) || event.action != MotionEvent.ACTION_MOVE) {
			return false
		}
		val x = event.getAxisValue(MotionEvent.AXIS_X) +
			event.getAxisValue(MotionEvent.AXIS_HAT_X)
		val y = event.getAxisValue(MotionEvent.AXIS_Y) +
			event.getAxisValue(MotionEvent.AXIS_HAT_Y)
		val threshold = 0.5f
		forwardDirection(x < -threshold, x > threshold, y < -threshold, y > threshold)
		return gameRunning
	}

	override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
		if (isFromController(event.source) &&
			event.action == MotionEvent.ACTION_MOVE
		) {
			// Stick and hat together: a handheld reports its d-pad as a hat on
			// some builds and as DPAD keys on others, and taking both means
			// the direction works either way.
			val x = event.getAxisValue(MotionEvent.AXIS_X) +
				event.getAxisValue(MotionEvent.AXIS_HAT_X)
			val y = event.getAxisValue(MotionEvent.AXIS_Y) +
				event.getAxisValue(MotionEvent.AXIS_HAT_Y)
			// Half travel, not a hair trigger: an Amiga joystick is a switch,
			// and a resting stick that drifts would walk the player into a wall.
			val threshold = 0.5f
			forwardDirection(x < -threshold, x > threshold, y < -threshold, y > threshold)
			if (gameRunning) return true
		}
		return super.dispatchGenericMotionEvent(event)
	}

	override fun onResume() {
		super.onResume()
		(getSystemService(INPUT_SERVICE) as? InputManager)
			?.registerInputDeviceListener(inputDeviceListener, Handler(Looper.getMainLooper()))
	}

	override fun onPause() {
		(getSystemService(INPUT_SERVICE) as? InputManager)
			?.unregisterInputDeviceListener(inputDeviceListener)
		super.onPause()
	}

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
			.also { channel = it }
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
					// The in-process panel draws its own pad and needs the same
					// answer the emulator activity already had: is there real
					// hardware to play on? Without this it always drew touch
					// controls, including over a handheld's own sticks.
					"hasGamepad" -> result.success(HostSupport.realControllerConnected())

					// Told by Dart, because only Dart knows whether the panel
					// is running a game. Controller events are forwarded to the
					// core only while it is.
					"setGameRunning" -> {
						gameRunning = call.argument<Boolean>("running") ?: false
						if (!gameRunning) lastDirection = 0
						setGameAudioFocus(gameRunning)
						result.success(true)
					}

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
							MediaFolderAccess.pickFolder(
								this,
								call.argument<String>("initialSubfolder"),
							)
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
							mediaIoExecutor.execute {
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
							}
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
							mediaIoExecutor.execute {
								val ok = MediaFolderAccess.copyDocument(
									contentResolver,
									tree,
									documentId,
									destination,
								)
								Handler(Looper.getMainLooper()).post { result.success(ok) }
							}
						}
					}

					"copyFromMediaFolderBatch" -> {
						val copies = call.argument<List<Map<String, Any?>>>("copies")
						val tree = MediaFolderAccess.grantedTree(this)
						if (copies == null) {
							result.error("bad_args", "copies are required", null)
						} else if (tree == null) {
							result.error("no_folder", "no folder has been granted", null)
						} else {
							mediaIoExecutor.execute {
								val copied = copies.map { copy ->
									val documentId = copy["documentId"] as? String
									val destination = copy["destination"] as? String
									documentId != null && destination != null &&
										MediaFolderAccess.copyDocument(
											contentResolver,
											tree,
											documentId,
											destination,
										)
								}
								Handler(Looper.getMainLooper()).post {
									result.success(copied)
								}
							}
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
					// Closes the audio device, which pausing does not. An open
					// stream holds an AudioMix wake lock, so a backgrounded
					// launcher kept the CPU awake at 0% CPU.
					"musicReleaseAudio" -> {
						if (ensureMusicLibrary(this)) nativeMusicReleaseAudio()
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
