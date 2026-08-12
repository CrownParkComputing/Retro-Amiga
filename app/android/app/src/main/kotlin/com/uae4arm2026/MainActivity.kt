package com.uae4arm2026

import android.content.Intent
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
