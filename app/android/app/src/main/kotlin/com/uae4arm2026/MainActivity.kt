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
					"platformName" -> result.success("android")

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
					else -> result.notImplemented()
				}
			}
	}

	private fun hasAllFilesAccess(): Boolean {
		// Below Android 11 there is no such thing: the legacy storage
		// permission covers it, and a scan just works.
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return true
		return Environment.isExternalStorageManager()
	}

	private fun openAllFilesAccessSettings(): Boolean {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return true
		return try {
			startActivity(
				Intent(
					Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
					Uri.parse("package:$packageName")
				)
			)
			// Sent, not granted: the caller has to re-check on return.
			false
		} catch (e: Exception) {
			// Some builds lack the per-app screen; fall back to the list.
			try {
				startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
				false
			} catch (e2: Exception) {
				false
			}
		}
	}

	private fun launchEmulator(args: Array<String>) {
		val intent = Intent(this, Uae4ArmEmulatorActivity::class.java)
		intent.putExtra("SDL_ARGS", args)
		startActivity(intent)
	}
}
