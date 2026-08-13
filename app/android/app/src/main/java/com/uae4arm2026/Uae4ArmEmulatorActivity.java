package com.uae4arm2026;

import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.ImageButton;
import android.window.OnBackInvokedCallback;
import android.window.OnBackInvokedDispatcher;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;
import org.libsdl.app.SDLActivity;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

import android.view.MotionEvent;
import android.view.View;
import android.widget.LinearLayout;
import android.os.Handler;
import android.os.Looper;

public class Uae4ArmEmulatorActivity extends SDLActivity {
	public static boolean isRunning = false;
	private final Handler uiHandler = new Handler(Looper.getMainLooper());
	private final Runnable hideOverlaysRunnable = this::hideOverlays;
	private LinearLayout overlayContainer;
	// dispatchTouchEvent() fires for every MotionEvent - including every ACTION_MOVE while
	// dragging the on-screen joystick, which can be dozens of events per second. Re-arming the
	// Handler and touching View visibility on each one forces a layout/invalidate pass on the UI
	// thread for every sample, competing with the SDL render thread and visibly slowing the
	// emulation while a finger is down. Throttle so the timer is only actually reset at most
	// once per this window; the 3s auto-hide delay makes the lost precision unnoticeable.
	private static final long AUTO_HIDE_RESET_THROTTLE_MS = 500;
	private long lastAutoHideResetUptimeMs = 0;

	private OnBackInvokedCallback backCallback;
	private Uae4ArmVirtualKeyboard virtualKeyboard;
	private ImageButton keyboardButton;
	private ImageButton pauseButton;
	private ImageButton controllerButton;
	private ImageButton aspectButton;
	private ImageButton floppyButton;
	private ImageButton editConfigButton;
	private ImageButton rebootButton;
	private ImageButton quitButton;
	private boolean pauseMenuPausedEmulation = false;
	private final List<ParcelFileDescriptor> openFileDescriptors = new ArrayList<>();

	private static final String HINT_TRAP_BACK = "SDL_ANDROID_TRAP_BACK_BUTTON";
	public static final String EXTRA_CONFIG_PATH = "com.uae4arm2026.CONFIG_PATH";

	/**
	 * Where the on-screen controls sit, and any buttons the player added.
	 *
	 * A file in the app's own directory rather than preferences, because the
	 * launcher designs the pad and the launcher is a DIFFERENT PROCESS to this
	 * one - SDL owns a surface here, which is why the emulator runs on its
	 * own. SharedPreferences is per-process and caches, so a layout saved by
	 * the designer would not be seen here until something evicted it.
	 * getFilesDir() is the same directory the launcher calls its app support
	 * directory, so both ends agree on the path without passing it about.
	 */
	private static final String PAD_LAYOUT_FILE = "pad_layout.json";

	private String currentConfigPath;

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		isRunning = true;
		cleanCache();
		super.onCreate(savedInstanceState);
		currentConfigPath = extractConfigPath(getIntent());
		HostSupport.writeSessionMarker(this, currentConfigPath);
		// The overlay can be switched off from adb - `--ez noOverlay true` -
		// so a display problem can be bisected on the device without two
		// builds. It is a second Flutter engine and a second SurfaceView over
		// SDL's, which is a lot of machinery to have to rule out by guesswork.
		if (!getIntent().getBooleanExtra("noOverlay", false)) {
			attachFlutterOverlay();
		}
		setupOverlayContainer();
		ensureVirtualKeyboardOverlay();

		// Only what is worth reaching for mid-game, in the order it is wanted.
		//
		// The column used to hold eight buttons - keyboard, controller, aspect,
		// floppy, pause, edit config, reboot, quit - which is a menu pretending
		// to be a toolbar. Aspect, reboot and edit belong to the setup that
		// launched the game: changing them here means changing them again next
		// time, in the place they are actually stored.
		//
		// What is left is what a session needs: the pad, the keyboard, a disk
		// swap when there is more than one disk, and a way out.
		// No Java buttons: the Flutter overlay draws the strip, with the same
		// Material icons the launcher uses. They are only built when the
		// overlay could not start, so a session is never left with no way to
		// pause or get out.
		if (flutterOverlay == null) {
			ensureControllerButtonOverlay();
			if (shouldShowKeyboardButton()) {
				ensureKeyboardButtonOverlay();
			}
			if (configHasFloppyDrive(0)) {
				ensureFloppyButtonOverlay();
			}
			ensurePauseButtonOverlay();
			ensureQuitButtonOverlay();
		}
		// No quit icon: back leaves the game and returns to the shelf, which
		// is one way of doing it rather than two. The four that remain are the
		// ones that change something about the session in progress - pad,
		// keyboard, disk, pause - and nothing here opens a menu.
		enterImmersiveMode();
		registerBackHandler();
		applyControllerMappingsFromPrefs();
	}

	private void cleanCache() {
		File cacheDir = getCacheDir();
		File[] files = cacheDir.listFiles();
		if (files != null) {
			for (File f : files) {
				if (f.isDirectory() && f.getName().startsWith("fd_")) {
					deleteRecursive(f);
				} else if (f.getName().startsWith("bridge_") || f.getName().contains(".translated")) {
					f.delete();
				}
			}
		}
	}

	private void deleteRecursive(File f) {
		if (f.isDirectory()) {
			File[] children = f.listFiles();
			if (children != null) {
				for (File child : children) deleteRecursive(child);
			}
		}
		f.delete();
	}

	@Override
	public void onWindowFocusChanged(boolean hasFocus) {
		super.onWindowFocusChanged(hasFocus);
		if (hasFocus) {
			enterImmersiveMode();
		}
	}

	@Override
	protected String[] getLibraries() {
		return new String[] { "uae4arm" };
	}

	@Override
	protected String[] getArguments() {
		Intent intent = getIntent();
		if (intent != null) {
			String[] args = intent.getStringArrayExtra("SDL_ARGS");
			if (args != null) {
				android.util.Log.d("Uae4Arm-SDL", "Original args: " + java.util.Arrays.toString(args));
				String[] translated = translateArguments(args);
				android.util.Log.d("Uae4Arm-SDL", "Final translated args: " + java.util.Arrays.toString(translated));
				return translated;
			}
		}
		return new String[0];
	}

	private String[] translateArguments(String[] args) {
		String[] result = new String[args.length];
		for (int i = 0; i < args.length; i++) {
			String arg = args[i];
			if ("--config".equals(arg) && i + 1 < args.length) {
				result[i] = arg;
				result[i + 1] = translateConfigFile(args[i + 1]);
				i++;
				continue;
			}

			if (arg.contains("=") && !arg.startsWith("-")) {
				int eq = arg.indexOf('=');
				String key = arg.substring(0, eq);
				String value = arg.substring(eq + 1);

				if (isDirectoryKey(key)) {
					result[i] = arg;
					continue;
				}

				String translatedValue = translateStructuredValue(value);
				if (translatedValue != null) {
					result[i] = key + "=" + translatedValue;
				} else {
					result[i] = arg;
				}
			} else if (isExternalPath(arg)) {
				result[i] = translatePathToFd(arg);
			} else {
				result[i] = arg;
			}
		}
		return result;
	}

	private static final class ParsedPathValue {
		final String pathPart;
		final String suffix;

		ParsedPathValue(String pathPart, String suffix) {
			this.pathPart = pathPart;
			this.suffix = suffix;
		}
	}

	private ParsedPathValue parsePathValue(String value) {
		if (value.startsWith("\"")) {
			int start = 0;
			while (start < value.length() && value.charAt(start) == '"') {
				start++;
			}

			int endQuote = value.indexOf('"', start);
			if (endQuote >= start) {
				int suffixStart = endQuote;
				while (suffixStart < value.length() && value.charAt(suffixStart) == '"') {
					suffixStart++;
				}
				return new ParsedPathValue(value.substring(start, endQuote), value.substring(suffixStart));
			}

			return new ParsedPathValue(value.substring(start), "");
		}

		if (value.contains(",")) {
			int comma = value.lastIndexOf(',');
			return new ParsedPathValue(value.substring(0, comma), value.substring(comma));
		}

		return new ParsedPathValue(value, "");
	}

	private String translateStructuredValue(String value) {
		int firstQuote = value.indexOf('"');
		if (firstQuote >= 0) {
			int secondQuote = value.indexOf('"', firstQuote + 1);
			if (secondQuote > firstQuote + 1) {
				String pathPart = value.substring(firstQuote + 1, secondQuote);
				if (isExternalPath(pathPart)) {
					String translated = translatePathToFd(pathPart);
					return value.substring(0, firstQuote + 1) + translated + value.substring(secondQuote);
				}
			}
		}

		ParsedPathValue parsedValue = parsePathValue(value);
		if (isExternalPath(parsedValue.pathPart)) {
			String translated = translatePathToFd(parsedValue.pathPart);
			return translated + parsedValue.suffix;
		}

		return null;
	}

	private boolean isDirectoryKey(String key) {
		return key.endsWith("_path") || 
			   key.equals("whdload_arch_path") || 
			   key.equals("config_path") ||
			   key.equals("path_rom") ||
			   key.equals("filesystem") ||
			   key.equals("filesystem2");
	}

	private boolean isExternalPath(String path) {
		if (path == null || path.isEmpty()) return false;
		if (path.startsWith("content://")) return true;
		if (path.startsWith("/") && !HostSupport.isAppOwnedPath(this, path)) return true;
		return false;
	}

	private String translateConfigFile(String configPath) {
		File original = new File(configPath);
		if (!original.exists()) return configPath;

		try {
			List<String> lines = java.nio.file.Files.readAllLines(original.toPath());
			List<String> translatedLines = new ArrayList<>();
			boolean changed = false;

			for (String line : lines) {
				String trimmed = line.trim();
				if (trimmed.isEmpty() || trimmed.startsWith(";") || !trimmed.contains("=")) {
					translatedLines.add(line);
					continue;
				}

				int eq = line.indexOf('=');
				String key = line.substring(0, eq).trim();
				String value = line.substring(eq + 1).trim();

				if (isDirectoryKey(key)) {
					translatedLines.add(line);
					continue;
				}

				String translatedValue = translateStructuredValue(value);
				if (translatedValue != null) {
					translatedLines.add(key + "=" + translatedValue);
					changed = true;
				} else {
					translatedLines.add(line);
				}
			}

			if (changed) {
				File translatedFile = new File(getCacheDir(), ".translated.uae");
				java.nio.file.Files.write(translatedFile.toPath(), translatedLines);
				return translatedFile.getAbsolutePath();
			}
		} catch (IOException e) {
			android.util.Log.e("Uae4Arm-SDL", "Failed to translate config: " + configPath, e);
		}
		return configPath;
	}

	private String translatePathToFd(String path) {
		if (path.startsWith("/proc/self/fd/") || path.startsWith(getCacheDir().getAbsolutePath())) return path;
		
		try {
			Uri contentUri = path.startsWith("content://") ? Uri.parse(path) : HostSupport.findContentUriForPath(this, path);
			if (contentUri == null) return path;

			ParcelFileDescriptor pfd;
			try {
				pfd = getContentResolver().openFileDescriptor(contentUri, "rw");
			} catch (Exception e) {
				try {
					pfd = getContentResolver().openFileDescriptor(contentUri, "r");
				} catch (Exception e2) {
					return path;
				}
			}

			if (pfd == null) {
				return path;
			}

			openFileDescriptors.add(pfd);
			int fd = pfd.getFd();
			String fileName = getRealFileName(contentUri, path);
			File bridgeDir = new File(getCacheDir(), "fd_" + fd);
			if (!bridgeDir.exists() && !bridgeDir.mkdirs()) {
				return path;
			}

			File bridgedFile = new File(bridgeDir, fileName);
			if (bridgedFile.exists()) bridgedFile.delete();
			android.system.Os.symlink("/proc/self/fd/" + fd, bridgedFile.getAbsolutePath());
			return bridgedFile.getAbsolutePath();
		} catch (Exception e) {
			android.util.Log.e("Uae4Arm-SDL", "Error bridging " + path, e);
		}
		return path;
	}

	private String getRealFileName(Uri uri, String fallback) {
		try (android.database.Cursor c = getContentResolver().query(uri, null, null, null, null)) {
			if (c != null && c.moveToFirst()) {
				int i = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME);
				if (i >= 0) return c.getString(i);
			}
		} catch (Exception ignored) {}
		int lastSlash = fallback.lastIndexOf('/');
		return lastSlash >= 0 ? fallback.substring(lastSlash + 1) : fallback;
	}

	private boolean isBackTrapped() {
		return SDLActivity.nativeGetHintBoolean(HINT_TRAP_BACK, false);
	}

	private void handleBackPress() {
		if (virtualKeyboard != null && virtualKeyboard.isKeyboardVisible()) {
			hideVirtualKeyboardFromNative();
			return;
		}
		if (isBackTrapped()) {
			showPauseMenu();
		} else {
			// Back out of a game the same way the X does: to the launcher.
			returnToLauncher();
		}
	}

	// Kept as "showPauseMenu" (rather than renamed) since native code invokes this exact method
	// name by reflection (android_show_pause_menu() in android_keyboard_bridge.cpp, wired to the
	// three-finger-tap gesture) and handleBackPress() below also calls it directly.
	// There's no dialog/menu anymore — every action (keyboard, joypad, aspect, disk swap, pause)
	// is its own always-available overlay icon, so this just toggles pause/resume.
	public void showPauseMenu() {
		togglePause();
	}

	private void togglePause() {
		pauseMenuPausedEmulation = !pauseMenuPausedEmulation;
		nativeSetPause(pauseMenuPausedEmulation);
		runOnUiThread(() -> {
			if (pauseButton != null) {
				pauseButton.setImageResource(pauseMenuPausedEmulation
					? android.R.drawable.ic_media_play
					: android.R.drawable.ic_media_pause);
			}
			enterImmersiveMode();
		});
	}

	private void showFloppyPicker(int drive) {
		String title = getString(drive == 0 ? R.string.pause_menu_pick_df0 : R.string.pause_menu_pick_df1);
		List<String> floppies = HostSupport.scanForFloppies(this);
		if (floppies.isEmpty()) {
			showEmptyMediaDialog(title, getString(R.string.quick_start_no_floppy_images));
			return;
		}

		String[] labels = new String[floppies.size()];
		for (int i = 0; i < floppies.size(); i++) {
			labels[i] = new java.io.File(floppies.get(i)).getName();
		}

		new AlertDialog.Builder(this)
			.setTitle(title)
			.setItems(labels, (dialog, which) -> {
				String path = floppies.get(which);
				String translated = translatePathToFd(path);
				nativeInsertFloppy(drive, translated);
			})
			.setNeutralButton(R.string.action_eject, (dialog, which) -> nativeEjectFloppy(drive))
			.setNegativeButton(android.R.string.cancel, null)
			.setOnDismissListener(d -> enterImmersiveMode())
			.show();
	}

	private void showEmptyMediaDialog(String title, String message) {
		new AlertDialog.Builder(this)
			.setTitle(title)
			.setMessage(message)
			.setPositiveButton(android.R.string.ok, null)
			.setNegativeButton(R.string.pause_menu_detailed_settings, (dialog, which) -> openDetailedSettings())
			.setOnDismissListener(d -> enterImmersiveMode())
			.show();
	}

	private final java.util.HashMap<Integer, Integer> kbButtonMap = new java.util.HashMap<>();

	@Override
	protected void onActivityResult(int requestCode, int resultCode, Intent data) {
		super.onActivityResult(requestCode, resultCode, data);
		if (requestCode == 1001) {
			applyControllerMappingsFromPrefs();
		}
	}

	private void applyControllerMappingsFromPrefs() {
		SharedPreferences prefs = getSharedPreferences("controller_map", MODE_PRIVATE);
		int[] sdlToTarget = new int[21];
		java.util.Arrays.fill(sdlToTarget, -1);
		for (int t = 0; t < 7; t++) {
			int androidKeycode = prefs.getInt("cd32_" + t, -1);
			if (androidKeycode >= 0) {
				int sdlBtn = ControllerMapActivity.androidToSdlButton(androidKeycode);
				if (sdlBtn >= 0 && sdlBtn < sdlToTarget.length) {
					sdlToTarget[sdlBtn] = t;
				}
			}
		}
		nativeApplyControllerMapping(sdlToTarget);

		// The machine decides the port, not the mapping. A CD32 config gets a
		// seven-button pad so an external controller's X and Y reach green and
		// yellow; anything else gets a joystick, where the same pad's A and B
		// are fire one and two.
		nativeSetExternalControllerMode(configIsCd32() ? 7 : 3);

		int oscMode = prefs.getInt("onscreen_mode", 0);
		nativeSetOnScreenController(oscMode);

		kbButtonMap.clear();
		int[] extraButtons = {
			KeyEvent.KEYCODE_BUTTON_SELECT,
			KeyEvent.KEYCODE_BUTTON_L2,
			KeyEvent.KEYCODE_BUTTON_R2,
			KeyEvent.KEYCODE_BUTTON_THUMBL,
			KeyEvent.KEYCODE_BUTTON_THUMBR
		};
		for (int i = 0; i < extraButtons.length; i++) {
			int amigaKey = prefs.getInt("key_" + i, -1);
			if (amigaKey >= 0) {
				kbButtonMap.put(extraButtons[i], amigaKey);
			}
		}
	}

	@Override
	public boolean dispatchKeyEvent(KeyEvent event) {
		int keyCode = event.getKeyCode();
		if (kbButtonMap.containsKey(keyCode)) {
			int amigaKey = kbButtonMap.get(keyCode);
			if (event.getAction() == KeyEvent.ACTION_DOWN && event.getRepeatCount() == 0) {
				nativeSendAmigaKey(amigaKey, 1);
			} else if (event.getAction() == KeyEvent.ACTION_UP) {
				nativeSendAmigaKey(amigaKey, 0);
			}
			return true;
		}
		return super.dispatchKeyEvent(event);
	}

	private void resumeFromPauseMenuIfNeeded() {
		if (pauseMenuPausedEmulation) {
			nativeSetPause(false);
			pauseMenuPausedEmulation = false;
		}
	}

	/**
	 * Ends the session and puts the launcher back on screen.
	 *
	 * finish() alone is not enough. The emulator runs in its own :sdl process
	 * and SDL exits that process on the way out; if the launcher's process is
	 * not brought forward first, the task goes with it and the user lands on
	 * the home screen. Closing a game should return to where the game was
	 * started from, not close the app.
	 */
	/**
	 * Writes a save state for the session being left, so it can be picked up
	 * again from the launcher.
	 *
	 * The core captures on its next frame rather than immediately, so this
	 * gives it a moment before the activity goes away. Half a second is
	 * generous for one frame and short enough not to be felt.
	 */
	private void captureSaveState() {
		if (currentConfigPath == null) return;
		try {
			final File states = new File(getFilesDir(), "states");
			if (!states.exists() && !states.mkdirs()) return;

			String name = new File(currentConfigPath).getName();
			if (name.endsWith(".uae")) name = name.substring(0, name.length() - 4);
			final File state = new File(states, name + ".uss");

			nativeSaveState(state.getAbsolutePath());
			// The state is written on the emulation thread; wait for the file
			// rather than assume, but never for long.
			for (int i = 0; i < 10 && !state.exists(); i++) {
				try {
					Thread.sleep(50);
				} catch (InterruptedException ignored) {
					Thread.currentThread().interrupt();
					break;
				}
			}
			HostSupport.recordSaveState(this, name, state.getAbsolutePath(), currentConfigPath);
		} catch (Exception e) {
			android.util.Log.w("Uae4Arm", "could not save state", e);
		}
	}

	private void returnToLauncher() {
		captureSaveState();
		HostSupport.writeCleanExitMarker(this);
		// The session is over, so the launcher should stop offering to resume
		// it. Leaving the marker is what a kill looks like, and that is worth
		// telling apart from quitting.
		HostSupport.clearSessionMarker(this);
		Intent intent = new Intent(this, MainActivity.class);
		intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
		startActivity(intent);
		finish();
	}

	private void openDetailedSettings() {
		hideVirtualKeyboardFromNative();
		HostSupport.writeCleanExitMarker(this);
		// TODO: ask the Flutter launcher to open its settings route over the
		// emulator MethodChannel; for now it returns to wherever it left off.
		Intent intent = new Intent(this, MainActivity.class);
		intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
		startActivity(intent);
	}

	private void openEditConfig() {
		// Deliberately NOT writeCleanExitMarker() / FLAG_ACTIVITY_CLEAR_TOP here: this is a detour
		// to edit the running game's config, not an exit. CLEAR_TOP would finish this activity
		// (onDestroy() sets isRunning = false), which broke two things downstream: the "Reboot
		// System" save button in the edit wizard couldn't tell the game was still running, and
		// there was no live emulator instance left underneath to return to on back-press. Leaving
		// this activity alive (just backgrounded) is what makes both of those work.
		Intent intent = new Intent(this, MainActivity.class);
		intent.putExtra(EXTRA_CONFIG_PATH, currentConfigPath);
		intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
		startActivity(intent);
	}

	private static String extractConfigPath(Intent intent) {
		if (intent == null) return null;
		String[] args = intent.getStringArrayExtra("SDL_ARGS");
		if (args == null) return null;
		for (int i = 0; i < args.length - 1; i++) {
			if ("--config".equals(args[i])) {
				return args[i + 1];
			}
		}
		return null;
	}

	private int currentOnScreenMode = 0; // 0=None, 1=Joystick, 2=CD32 Pad

	private void toggleOnScreenController() {
		currentOnScreenMode = (currentOnScreenMode + 1) % 3;
		nativeSetOnScreenController(currentOnScreenMode);
		getSharedPreferences("controller_map", MODE_PRIVATE).edit().putInt("onscreen_mode", currentOnScreenMode).apply();
	}

	private void ensureVirtualKeyboardOverlay() {
		if (virtualKeyboard != null) {
			return;
		}
		virtualKeyboard = new Uae4ArmVirtualKeyboard(this);
		FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
		params.gravity = Gravity.BOTTOM;
		addContentView(virtualKeyboard, params);
	}

	private boolean shouldShowKeyboardButton() {
		String[] args = getArguments();
		String configPath = null;
		for (int i = 0; i < args.length - 1; i++) {
			if ("--config".equals(args[i])) {
				configPath = args[i + 1];
				break;
			}
		}
		if (configPath == null || configPath.isEmpty()) {
			return true;
		}

		File configFile = new File(configPath);
		if (!configFile.exists()) {
			return true;
		}

		try {
			List<String> lines = java.nio.file.Files.readAllLines(configFile.toPath());
			Boolean androidKeyboardButtonEnabled = null;
			Boolean nativeKeyboardEnabled = null;
			for (String line : lines) {
				String trimmed = line.trim();
				if (trimmed.isEmpty() || trimmed.startsWith(";") || !trimmed.contains("=")) {
					continue;
				}
				int eq = trimmed.indexOf('=');
				String key = trimmed.substring(0, eq).trim();
				String value = trimmed.substring(eq + 1).trim();
				if (HostSupport.KEY_SHOW_ANDROID_KEYBOARD_BUTTON.equals(key)) {
					androidKeyboardButtonEnabled = parseConfigBoolean(value, true);
					continue;
				}
				if (HostSupport.KEY_DEFAULT_OSK.equals(key) || HostSupport.KEY_VIRTUAL_KEYBOARD_ENABLED.equals(key)) {
					nativeKeyboardEnabled = parseConfigBoolean(value, true);
				}
			}
			if (androidKeyboardButtonEnabled != null) {
				return androidKeyboardButtonEnabled;
			}
			if (nativeKeyboardEnabled != null) {
				return nativeKeyboardEnabled;
			}
		} catch (IOException ignored) {
			return true;
		}

		return true;
	}

	private boolean parseConfigBoolean(String value, boolean defaultValue) {
		if (value == null) {
			return defaultValue;
		}
		if ("true".equalsIgnoreCase(value) || "yes".equalsIgnoreCase(value) || "1".equals(value)) {
			return true;
		}
		if ("false".equalsIgnoreCase(value) || "no".equalsIgnoreCase(value) || "0".equals(value)) {
			return false;
		}
		return defaultValue;
	}

	private void setupOverlayContainer() {
		final float density = getResources().getDisplayMetrics().density;
		overlayContainer = new LinearLayout(this);
		overlayContainer.setOrientation(LinearLayout.VERTICAL);
		overlayContainer.setPadding((int)(8 * density), (int)(8 * density), (int)(8 * density), (int)(8 * density));
		
		FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
			ViewGroup.LayoutParams.WRAP_CONTENT,
			ViewGroup.LayoutParams.WRAP_CONTENT
		);
		params.gravity = Gravity.TOP | Gravity.END;
		addContentView(overlayContainer, params);

		// Hide overlays initially after a delay
		resetAutoHideTimer();
	}

	/**
	 * Cheap line-scan of the currently loaded .uae config for floppy drive presence, used to
	 * decide whether to show the overlay disk-swap icon at all. This runs at onCreate time,
	 * before the native core has necessarily parsed the config, so we can't rely on
	 * nativeGetFloppyCount() yet (that's only safe once gameplay has actually started, e.g. from
	 * the pause menu).
	 */
	/**
	 * Whether the config we launched is a CD32.
	 *
	 * Same cheap line scan as configHasFloppyDrive, and for the same reason:
	 * this is asked while the overlay is starting, which can be before the
	 * core has parsed anything. The answer only picks which pad is DRAWN by
	 * default, so reading the file the launcher wrote is enough.
	 */
	/**
	 * Whether a real controller is attached.
	 *
	 * Both flags are required rather than either: a touchscreen reports
	 * SOURCE_JOYSTICK on some devices, and an accelerometer reports axes, so
	 * asking for a joystick alone finds hardware nobody can press a button on.
	 * Virtual devices are skipped for the same reason - the emulator registers
	 * its own on-screen pad with the input layer, and finding that would mean
	 * the drawn pad hides itself because it exists.
	 */
	private boolean realControllerConnected() {
		for (int id : android.view.InputDevice.getDeviceIds()) {
			android.view.InputDevice device = android.view.InputDevice.getDevice(id);
			if (device == null || device.isVirtual()) continue;
			int sources = device.getSources();
			boolean gamepad = (sources & android.view.InputDevice.SOURCE_GAMEPAD)
				== android.view.InputDevice.SOURCE_GAMEPAD;
			boolean joystick = (sources & android.view.InputDevice.SOURCE_JOYSTICK)
				== android.view.InputDevice.SOURCE_JOYSTICK;
			if (gamepad && joystick) return true;
		}
		return false;
	}

	private String readPadLayout() {
		File file = new File(getFilesDir(), PAD_LAYOUT_FILE);
		if (!file.exists()) return null;
		try (java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.FileReader(file))) {
			StringBuilder text = new StringBuilder();
			String line;
			while ((line = reader.readLine()) != null) text.append(line);
			return text.toString();
		} catch (IOException e) {
			// No layout is survivable - the defaults are a usable pad. A
			// half-read one is not, so it is not returned.
			return null;
		}
	}

	private void writePadLayout(String json) {
		if (json == null) return;
		File file = new File(getFilesDir(), PAD_LAYOUT_FILE);
		try (java.io.FileWriter writer = new java.io.FileWriter(file)) {
			writer.write(json);
		} catch (IOException ignored) {
		}
	}

	private boolean configIsCd32() {
		if (currentConfigPath == null) return false;
		try {
			File file = new File(currentConfigPath);
			if (!file.exists()) return false;
			try (java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.FileReader(file))) {
				String line;
				while ((line = reader.readLine()) != null) {
					if (line.startsWith("cd32cd=")) {
						return parseConfigBoolean(line.substring("cd32cd=".length()).trim(), false);
					}
				}
			}
		} catch (IOException ignored) {
		}
		return false;
	}

	private boolean configHasFloppyDrive(int drive) {
		if (currentConfigPath == null) {
			// No explicit config (e.g. quickstart floppy launch) - assume a floppy drive exists.
			return true;
		}
		try {
			File file = new File(currentConfigPath);
			if (!file.exists()) return true;
			String key = "floppy" + drive + "type=";
			try (java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.FileReader(file))) {
				String line;
				while ((line = reader.readLine()) != null) {
					if (line.startsWith(key)) {
						String value = line.substring(key.length()).trim();
						return !value.equals("-1");
					}
				}
			}
		} catch (IOException ignored) {
		}
		// floppy0type defaults to enabled (0) when unspecified; higher drives default to off.
		return drive == 0;
	}

	private void resetAutoHideTimer() {
		long now = android.os.SystemClock.uptimeMillis();
		if (now - lastAutoHideResetUptimeMs < AUTO_HIDE_RESET_THROTTLE_MS) {
			// Already reset recently (e.g. mid-drag on the on-screen joystick) - skip the UI-thread
			// work below rather than doing it for every single MotionEvent.
			return;
		}
		lastAutoHideResetUptimeMs = now;
		uiHandler.removeCallbacks(hideOverlaysRunnable);
		showOverlays();
		uiHandler.postDelayed(hideOverlaysRunnable, 3000);
	}

	private void showOverlays() {
		if (overlayContainer != null && overlayContainer.getVisibility() != View.VISIBLE) {
			overlayContainer.setVisibility(View.VISIBLE);
		}
	}

	private void hideOverlays() {
		if (overlayContainer != null) overlayContainer.setVisibility(View.GONE);
	}

	@Override
	public boolean onGenericMotionEvent(MotionEvent event) {
		resetAutoHideTimer();
		return super.onGenericMotionEvent(event);
	}

	@Override
	public boolean onTouchEvent(MotionEvent event) {
		resetAutoHideTimer();
		return super.onTouchEvent(event);
	}

	// SDLActivity's game surface consumes touch events for gameplay input before they'd ever
	// reach onTouchEvent() above, so relying on onTouchEvent alone means the overlay icons show
	// once at startup and never come back once the auto-hide timer fires. dispatchTouchEvent()
	// runs for every touch before any view gets a chance to consume it, so hook the timer here
	// too (without altering dispatch) to keep the icons reachable throughout gameplay.
	@Override
	public boolean dispatchTouchEvent(MotionEvent event) {
		resetAutoHideTimer();
		return super.dispatchTouchEvent(event);
	}

	/**
	 * Shared factory for overlay icon buttons: consistent (and touch-friendly) sizing, a
	 * generous padded tap target well beyond the visible glyph, and vertical spacing suited to
	 * the now-vertical overlay stack.
	 */
	private ImageButton addOverlayIconButton(int drawableRes, boolean isFirst, View.OnClickListener listener) {
		final float density = getResources().getDisplayMetrics().density;
		ImageButton button = new ImageButton(this);
		button.setImageResource(drawableRes);
		button.setColorFilter(0xFFFFFFFF);
		button.setBackground(null);
		button.setAlpha(0.75f);
		int iconSize = (int) (28 * density);
		int padding = (int) (10 * density);
		button.setPadding(padding, padding, padding, padding);
		button.setOnClickListener(v -> {
			resetAutoHideTimer();
			listener.onClick(v);
		});

		LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(iconSize + padding * 2, iconSize + padding * 2);
		lp.setMargins(0, isFirst ? 0 : (int) (4 * density), 0, 0);
		overlayContainer.addView(button, lp);
		return button;
	}

	private void ensureKeyboardButtonOverlay() {
		if (keyboardButton != null) return;
		keyboardButton = addOverlayIconButton(android.R.drawable.ic_menu_edit, overlayContainer.getChildCount() == 0,
			v -> toggleVirtualKeyboardFromNative());
	}

	private void ensureControllerButtonOverlay() {
		if (controllerButton != null) return;
		// Just toggles the on-screen joystick/CD32-pad overlay on/off (cycling None -> Joystick
		// -> CD32 Pad), same as the pause menu's joypad entry. Port/device assignment (real
		// mouse, external controller, or the touch joystick/mouse) now lives in the main
		// Settings screen's "Controller Ports" section, not behind an in-game mapping screen.
		controllerButton = addOverlayIconButton(R.drawable.ic_gamepad, overlayContainer.getChildCount() == 0,
			v -> toggleOnScreenController());
	}

	private void ensureAspectButtonOverlay() {
		if (aspectButton != null) return;
		aspectButton = addOverlayIconButton(android.R.drawable.ic_menu_zoom, overlayContainer.getChildCount() == 0,
			v -> nativeSetCorrectAspect(!nativeGetCorrectAspect()));
	}

	private void ensureFloppyButtonOverlay() {
		if (floppyButton != null) return;
		floppyButton = addOverlayIconButton(android.R.drawable.ic_menu_save, overlayContainer.getChildCount() == 0,
			v -> showFloppySwapEntry());
		floppyButton.setOnLongClickListener(v -> {
			showSecondFloppy();
			return true;
		});
	}

	/**
	 * Opens the disk picker for DF0 straight away.
	 *
	 * It used to ask which drive first, through a dialog still titled "Pause
	 * menu" - a menu in a strip of toggles, for a choice that is DF0 almost
	 * every time. A second drive is reached by holding the icon instead.
	 */
	private void showFloppySwapEntry() {
		showFloppyPicker(0);
	}

	/** The second drive, when there is one. */
	private void showSecondFloppy() {
		int floppyCount = nativeGetFloppyCount();
		if (floppyCount <= 0) {
			floppyCount = configHasFloppyDrive(1) ? 2 : 1;
		}
		showFloppyPicker(floppyCount >= 2 ? 1 : 0);
	}

	private void showFloppySwapEntryOld() {
		// Prefer the live native drive count (accurate once the core has actually booted);
		// fall back to the config-file scan used at startup if it isn't available yet.
		int floppyCount = nativeGetFloppyCount();
		if (floppyCount <= 0) {
			floppyCount = configHasFloppyDrive(1) ? 2 : (configHasFloppyDrive(0) ? 1 : 0);
		}
		if (floppyCount >= 2) {
			new AlertDialog.Builder(this)
				.setTitle(R.string.pause_menu_title)
				.setItems(new String[]{
					getString(R.string.pause_menu_swap_df0),
					getString(R.string.pause_menu_swap_df1)
				}, (dialog, which) -> showFloppyPicker(which))
				.setNegativeButton(android.R.string.cancel, null)
				.show();
		} else {
			showFloppyPicker(0);
		}
	}

	private void ensurePauseButtonOverlay() {
		if (pauseButton != null) return;
		pauseButton = addOverlayIconButton(android.R.drawable.ic_media_pause, overlayContainer.getChildCount() == 0,
			v -> showPauseMenu());
	}

	private void ensureEditConfigButtonOverlay() {
		if (editConfigButton != null) return;
		editConfigButton = addOverlayIconButton(android.R.drawable.ic_menu_preferences,
			overlayContainer.getChildCount() == 0, v -> openEditConfig());
	}

	private void ensureRebootButtonOverlay() {
		if (rebootButton != null) return;
		rebootButton = addOverlayIconButton(android.R.drawable.ic_menu_revert,
			overlayContainer.getChildCount() == 0, v -> nativeRestart());
	}

	private void ensureQuitButtonOverlay() {
		if (quitButton != null) return;
		quitButton = addOverlayIconButton(android.R.drawable.ic_menu_close_clear_cancel,
			overlayContainer.getChildCount() == 0, v -> returnToLauncher());
	}

	public void toggleVirtualKeyboardFromNative() {
		runOnUiThread(() -> {
			ensureVirtualKeyboardOverlay();
			virtualKeyboard.toggle();
			enterImmersiveMode();
		});
	}

	public void hideVirtualKeyboardFromNative() {
		runOnUiThread(() -> {
			if (virtualKeyboard != null) {
				virtualKeyboard.hide();
			}
			enterImmersiveMode();
		});
	}

	public static native void nativeSendAmigaKey(int keycode, int pressed);
	public static native void nativeSetPause(boolean paused);
	/** Relative mouse motion, in Amiga pixels. */
	public static native void nativeMouseMove(int dx, int dy);
	/** 0 left, 1 right, 2 middle. */
	public static native void nativeMouseButton(int button, boolean pressed);
	public static native void nativeSaveState(String path);
	public static native void nativeRestart();
	public static native void nativeInsertFloppy(int drive, String path);
	public static native void nativeEjectFloppy(int drive);
	public static native void nativeSetOnScreenController(int mode);
	public static native void nativeSetCorrectAspect(boolean enabled);
	public static native boolean nativeGetCorrectAspect();
	public static native int nativeGetFloppyCount();
	public static native void nativeSetExternalControllerMode(int mode);
	public static native void nativeApplyControllerMapping(int[] sdlToTarget);

	// Host-drawn touch controls, fed by the Flutter overlay.
	public static native void nativePadAttach(int pad);
	public static native void nativePadDirection(int pad, boolean left, boolean right, boolean up, boolean down);
	public static native void nativePadButton(int pad, int button, boolean pressed);
	public static native void nativePadReleaseAll(int pad);

	private void registerBackHandler() {
		if (Build.VERSION.SDK_INT >= 33) {
			backCallback = this::handleBackPress;
			getOnBackInvokedDispatcher().registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, backCallback);
		}
	}

	@SuppressWarnings("deprecation")
	@Override
	public void onBackPressed() {
		handleBackPress();
	}

	private EmulatorOverlay flutterOverlay;

	/** Stacks the Flutter-drawn controls over SDL's surface. */
	private void attachFlutterOverlay() {
		final EmulatorOverlay overlay = new EmulatorOverlay(this);
		final boolean started = overlay.attach(new EmulatorOverlay.PadListener() {
			@Override public void onAttach(int pad) { nativePadAttach(pad); }

			@Override public void onDirection(int pad, boolean left, boolean right, boolean up, boolean down) {
				nativePadDirection(pad, left, right, up, down);
			}

			@Override public void onButton(int pad, int button, boolean pressed) {
				nativePadButton(pad, button, pressed);
			}

			@Override public void onReleaseAll(int pad) { nativePadReleaseAll(pad); }

			// Each of these is the action the Java button used to run; the
			// icons moved to Flutter, the behaviour did not.
			// Pause means "stop playing", so it goes back to the workbench.
			// returnToLauncher writes a save state on the way out, which is
			// what makes Resume put the game back exactly here - a pause in
			// the only sense anyone wants one.
			@Override public void onPauseToWorkbench() {
				runOnUiThread(Uae4ArmEmulatorActivity.this::returnToLauncher);
			}

			@Override public boolean onToggleKeyboard() {
				// Done inline rather than posted: the caller wants the state
				// that results, and the channel already runs on the UI thread.
				ensureVirtualKeyboardOverlay();
				virtualKeyboard.toggle();
				enterImmersiveMode();
				return virtualKeyboard.isKeyboardVisible();
			}

			@Override public void onInsertDisk(int drive) {
				runOnUiThread(() -> showFloppyPicker(drive));
			}

			@Override public void onMouseMove(int dx, int dy) {
				nativeMouseMove(dx, dy);
			}

			@Override public void onMouseButton(int button, boolean pressed) {
				nativeMouseButton(button, pressed);
			}

			@Override public void onKey(int code, boolean pressed) {
				nativeSendAmigaKey(code, pressed ? 1 : 0);
			}

			@Override public int floppyCount() {
				// The live count is right once the core has booted; before
				// that, and for a machine whose config the core has not read
				// yet, fall back to what the config says. One is the floor:
				// a swap button that reports no drives could never be used.
				int drives = nativeGetFloppyCount();
				if (drives <= 0) drives = configHasFloppyDrive(1) ? 2 : 1;
				return drives;
			}

			@Override public void onPortMode(int mode) {
				nativeSetExternalControllerMode(mode);
			}

			@Override public boolean isCd32() {
				return configIsCd32();
			}

			@Override public boolean hasGamepad() {
				return realControllerConnected();
			}

			@Override public String loadLayout() {
				return readPadLayout();
			}

			@Override public void saveLayout(String json) {
				writePadLayout(json);
			}

			@Override public void onMenuRequested() { runOnUiThread(() -> showPauseMenu()); }
		});

		// Only kept if it actually started. Leaving the field set after a
		// failure would mean no strip at all: neither the Flutter one, which
		// is not running, nor the Java fallback, which checks this field.
		flutterOverlay = started ? overlay : null;
	}

	@Override
	protected void onDestroy() {
		if (flutterOverlay != null) {
			flutterOverlay.detach();
			flutterOverlay = null;
		}
		isRunning = false;
		resumeFromPauseMenuIfNeeded();
		if (Build.VERSION.SDK_INT >= 33 && backCallback != null) {
			getOnBackInvokedDispatcher().unregisterOnBackInvokedCallback(backCallback);
			backCallback = null;
		}
		final boolean finishing = isFinishing();
		if (finishing) {
			HostSupport.writeCleanExitMarker(this);
			HostSupport.clearSessionMarker(this);
		}
		super.onDestroy();
		for (ParcelFileDescriptor pfd : openFileDescriptors) {
			try {
				pfd.close();
			} catch (IOException ignored) {}
		}
		openFileDescriptors.clear();
		if (finishing) {
			android.os.Process.killProcess(android.os.Process.myPid());
		}
	}

	private void enterImmersiveMode() {
		WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
		WindowInsetsControllerCompat controller = WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView());
		controller.hide(WindowInsetsCompat.Type.statusBars() | WindowInsetsCompat.Type.navigationBars());
		controller.setSystemBarsBehavior(WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
		getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
	}
}
