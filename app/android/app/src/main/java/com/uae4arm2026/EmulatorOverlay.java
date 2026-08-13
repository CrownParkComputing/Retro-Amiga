package com.uae4arm2026;

import android.app.Activity;
import android.util.Log;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import io.flutter.embedding.android.FlutterSurfaceView;
import io.flutter.embedding.android.FlutterView;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.MethodChannel;

/**
 * The in-game controls, drawn by Flutter on top of the emulator.
 *
 * SDL renders straight into its own SurfaceView, which is what keeps the
 * emulation path zero-copy, so the controls cannot be part of the launcher's
 * widget tree. Instead a second Flutter engine runs a transparent FlutterView
 * stacked over that SurfaceView in the same Activity: Flutter draws the pad,
 * SDL draws the Amiga, and neither has to know about the other.
 *
 * Touches on the pad come back over a MethodChannel and go straight into the
 * emulated joystick through the native pad API, so a drawn pad is
 * indistinguishable from a physical one.
 */
final class EmulatorOverlay {

	private static final String TAG = "Uae4Arm-Overlay";
	private static final String CHANNEL = "uae4arm2026/overlay";

	/** Dart entry point, annotated @pragma('vm:entry-point') in overlay_main.dart. */
	private static final String ENTRYPOINT = "emulatorOverlayMain";

	/**
	 * The library that entry point lives in.
	 *
	 * Not optional. The two-argument DartEntrypoint looks for the function in
	 * lib/main.dart and nowhere else, so leaving this out fails with "Could not
	 * resolve main entrypoint function" - and the failure is quiet in the worst
	 * way: the engine does not start, the FlutterView is left stacked over
	 * SDL's surface drawing nothing, and the emulator runs invisibly behind an
	 * overlay that never paints.
	 */
	private static final String ENTRYPOINT_LIBRARY =
		"package:uae4arm2026/overlay_main.dart";

	private final Activity activity;
	private FlutterEngine engine;
	private FlutterView view;

	interface PadListener {
		void onAttach(int pad);
		void onDirection(int pad, boolean left, boolean right, boolean up, boolean down);
		void onButton(int pad, int button, boolean pressed);
		void onReleaseAll(int pad);
		void onMenuRequested();

		/** The session strip, drawn by Flutter so the icons match the launcher.
		 *  Returns whether the keyboard is now up, so the pad can stand aside
		 *  rather than sitting on top of it. */
		boolean onToggleKeyboard();
		void onInsertDisk(int drive);

		/** Pause means "stop playing": save where we are and go back. */
		void onPauseToWorkbench();

		/** Raw Amiga key code, for the buttons the player added themselves. */
		void onKey(int code, boolean pressed);

		/** How many floppy drives the running machine has. */
		int floppyCount();

		/** JSEM_MODE for port 1: 3 is a joystick, 7 is a CD32 pad. The core
		 *  has to be told which, or a seven-button pad reports into a port
		 *  that understands two of them. */
		void onPortMode(int mode);

		/** Whether the running config is a CD32, which picks the pad that is
		 *  drawn before the player has chosen one. */
		boolean isCd32();

		/** Whether a real controller is plugged in or paired. */
		boolean hasGamepad();

		/** Where the on-screen controls sit, as JSON. Kept by the Activity
		 *  because the overlay engine is built by hand and so has no plugins -
		 *  shared_preferences does not exist on the Dart side of it. */
		String loadLayout();
		void saveLayout(String json);
	}

	EmulatorOverlay(Activity activity) {
		this.activity = activity;
	}

	/** Builds the engine and stacks a transparent FlutterView over the emulator.
	 *  Returns false if it could not start, so the caller can fall back. */
	boolean attach(PadListener listener) {
		try {
			engine = new FlutterEngine(activity);
			engine.getDartExecutor().executeDartEntrypoint(
				new DartExecutor.DartEntrypoint(
					io.flutter.FlutterInjector.instance().flutterLoader().findAppBundlePath(),
					ENTRYPOINT_LIBRARY,
					ENTRYPOINT));

			// If Dart did not start there is nothing to show, and an attached
			// view would hide the emulator rather than decorate it.
			if (!engine.getDartExecutor().isExecutingDart()) {
				Log.e(TAG, "the overlay engine did not start; running without it");
				detach();
				return false;
			}

			new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL)
				.setMethodCallHandler((call, result) -> {
					switch (call.method) {
						case "padAttach":
							listener.onAttach(arg(call.argument("pad"), 1));
							result.success(true);
							break;
						case "padDirection":
							listener.onDirection(
								arg(call.argument("pad"), 1),
								Boolean.TRUE.equals(call.argument("left")),
								Boolean.TRUE.equals(call.argument("right")),
								Boolean.TRUE.equals(call.argument("up")),
								Boolean.TRUE.equals(call.argument("down")));
							result.success(true);
							break;
						case "padButton":
							listener.onButton(
								arg(call.argument("pad"), 1),
								arg(call.argument("button"), 0),
								Boolean.TRUE.equals(call.argument("pressed")));
							result.success(true);
							break;
						case "padReleaseAll":
							listener.onReleaseAll(arg(call.argument("pad"), 1));
							result.success(true);
							break;
						case "openMenu":
							listener.onMenuRequested();
							result.success(true);
							break;
						case "pauseToWorkbench":
							listener.onPauseToWorkbench();
							result.success(true);
							break;
						case "toggleKeyboard":
							result.success(listener.onToggleKeyboard());
							break;
						case "insertDisk":
							listener.onInsertDisk(arg(call.argument("drive"), 0));
							result.success(true);
							break;
						case "sendKey":
							listener.onKey(arg(call.argument("code"), 0),
								Boolean.TRUE.equals(call.argument("pressed")));
							result.success(true);
							break;
						case "floppyCount":
							result.success(listener.floppyCount());
							break;
						case "portMode":
							listener.onPortMode(arg(call.argument("mode"), 3));
							result.success(true);
							break;
						case "isCd32":
							result.success(listener.isCd32());
							break;
						case "hasGamepad":
							result.success(listener.hasGamepad());
							break;
						case "layoutLoad":
							result.success(listener.loadLayout());
							break;
						case "layoutSave":
							listener.saveLayout(call.argument("layout"));
							result.success(true);
							break;
						default:
							result.notImplemented();
					}
				});

			// renderTransparently=true is the whole trick: without it the
			// FlutterView paints an opaque background and hides the emulator.
			final FlutterSurfaceView surfaceView = new FlutterSurfaceView(activity, true);
			view = new FlutterView(activity, surfaceView);
			view.attachToFlutterEngine(engine);

			activity.addContentView(view, new FrameLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.MATCH_PARENT));

			engine.getLifecycleChannel().appIsResumed();
			return true;
		} catch (Exception e) {
			Log.e(TAG, "could not attach the Flutter overlay", e);
			detach();
			return false;
		}
	}

	private static int arg(Integer value, int fallback) {
		return value == null ? fallback : value;
	}

	void detach() {
		if (view != null) {
			view.detachFromFlutterEngine();
			view = null;
		}
		if (engine != null) {
			engine.destroy();
			engine = null;
		}
	}
}
