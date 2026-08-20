package com.uae4arm2026;

import android.content.Context;
import android.net.Uri;
import android.util.Log;

import java.io.File;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/**
 * The small amount of host support the emulator activity needs on its own.
 *
 * Everything the user configures now lives in the Flutter launcher, but the
 * emulator activity still has to answer a few questions while a game is
 * running: where its own storage is, which floppies it can offer for a disk
 * swap, and how to record that it exited cleanly. Those used to come from the
 * Kotlin launcher; keeping them here means the activity depends only on code
 * that survives the move to Flutter.
 */
public final class HostSupport {

	private static final String TAG = "Uae4Arm-HostSupport";

	/**
	 * Whether a real controller is attached.
	 *
	 * Virtual devices are skipped deliberately: the core registers its own
	 * on-screen pad with the input layer, so counting that would mean the
	 * drawn pad hides itself because it exists.
	 *
	 * GAMEPAD or JOYSTICK, not both. Android handhelds - the Retroid among
	 * them - commonly advertise their built-in controls as only one of the
	 * two, and requiring both leaves a device with real sticks showing touch
	 * controls over them.
	 *
	 * This lives here rather than in the emulator activity because the
	 * launcher needs the same answer: the in-process panel draws its own pad
	 * and had no way to ask.
	 */
	public static boolean realControllerConnected() {
		for (int id : android.view.InputDevice.getDeviceIds()) {
			android.view.InputDevice device = android.view.InputDevice.getDevice(id);
			if (device == null || device.isVirtual()) continue;
			int sources = device.getSources();
			boolean gamepad = (sources & android.view.InputDevice.SOURCE_GAMEPAD)
				== android.view.InputDevice.SOURCE_GAMEPAD;
			boolean joystick = (sources & android.view.InputDevice.SOURCE_JOYSTICK)
				== android.view.InputDevice.SOURCE_JOYSTICK;
			if (gamepad || joystick) return true;
		}
		return false;
	}

	/** Config keys shared with the core's .uae files. */
	public static final String KEY_SHOW_ANDROID_KEYBOARD_BUTTON = "show_android_keyboard_button";
	public static final String KEY_DEFAULT_OSK = "default_osk";
	public static final String KEY_VIRTUAL_KEYBOARD_ENABLED = "virtual_keyboard_enabled";

	private static final String[] FLOPPY_EXTENSIONS = {
		".adf", ".adz", ".dms", ".ipf", ".fdi", ".zip"
	};

	private HostSupport() {
	}

	/** Roots this app can read without going through the storage framework. */
	private static List<File> appOwnedRoots(Context context) {
		final List<File> roots = new ArrayList<>();
		if (context.getFilesDir() != null) roots.add(context.getFilesDir());
		if (context.getCacheDir() != null) roots.add(context.getCacheDir());
		final File external = context.getExternalFilesDir(null);
		if (external != null) roots.add(external);
		return roots;
	}

	/**
	 * True when the path sits inside this app's own storage, so it can be
	 * opened directly rather than through a content URI.
	 */
	public static boolean isAppOwnedPath(Context context, String path) {
		if (path == null || path.isEmpty()) return false;
		try {
			final String canonical = new File(path).getCanonicalPath();
			for (File root : appOwnedRoots(context)) {
				if (canonical.startsWith(root.getCanonicalPath())) return true;
			}
		} catch (Exception e) {
			Log.w(TAG, "isAppOwnedPath failed for " + path, e);
		}
		return false;
	}

	/**
	 * Resolve a plain path back to a content URI.
	 *
	 * Not implemented yet: the launcher's storage-framework bookkeeping moves
	 * to Dart, and this will call back into it. Returning null makes callers
	 * fall back to opening the path directly, which is correct for everything
	 * under app-owned storage.
	 */
	public static Uri findContentUriForPath(Context context, String path) {
		return null;
	}

	/** Floppy images in this app's own storage, for the in-game disk swap. */
	public static List<String> scanForFloppies(Context context) {
		final List<String> found = new ArrayList<>();
		for (File root : appOwnedRoots(context)) {
			collectFloppies(root, found, 0);
		}
		Collections.sort(found);
		return found;
	}

	private static void collectFloppies(File dir, List<String> out, int depth) {
		if (dir == null || !dir.isDirectory() || depth > 4 || out.size() > 500) return;
		final File[] entries = dir.listFiles();
		if (entries == null) return;
		for (File entry : entries) {
			if (entry.isDirectory()) {
				collectFloppies(entry, out, depth + 1);
				continue;
			}
			final String name = entry.getName().toLowerCase(Locale.ROOT);
			for (String extension : FLOPPY_EXTENSIONS) {
				if (name.endsWith(extension)) {
					out.add(entry.getAbsolutePath());
					break;
				}
			}
		}
	}

	/**
	 * Records that emulation ended on purpose, so the launcher does not treat
	 * the next start as a recovery from a crash.
	 */
	/**
	 * Which workbench panel to open when the launcher comes back.
	 *
	 * The in-game rail runs in the overlay's own Flutter engine, which has no
	 * way to reach into the launcher's -- they are two engines in one process.
	 * A file is how everything else here crosses that gap (see the clean-exit
	 * and session markers), and it survives the launcher being killed while a
	 * game ran, which a static field would not.
	 */
	public static void writeSectionRequest(Context context, String section) {
		if (section == null || section.isEmpty()) return;
		try {
			final File request = new File(context.getFilesDir(), "workbench_section");
			try (java.io.FileOutputStream out = new java.io.FileOutputStream(request)) {
				out.write(section.getBytes(java.nio.charset.StandardCharsets.UTF_8));
			}
		} catch (Exception e) {
			// Not fatal: the launcher opens where it last was instead.
			Log.w(TAG, "could not record the requested workbench section", e);
		}
	}

	public static void writeCleanExitMarker(Context context) {
		try {
			final File marker = new File(context.getFilesDir(), "clean_exit");
			if (!marker.exists() && !marker.createNewFile()) {
				Log.w(TAG, "could not create clean exit marker");
			}
		} catch (Exception e) {
			Log.w(TAG, "writeCleanExitMarker failed", e);
		}
	}

	/**
	 * Records that a game is running, so the launcher can offer to go back to
	 * it. Cleared when emulation ends; left behind if the process is killed,
	 * which is exactly the case worth offering a way back from.
	 */
	public static void writeSessionMarker(Context context, String configPath) {
		try {
			final File marker = new File(context.getFilesDir(), "session_active");
			try (java.io.FileWriter writer = new java.io.FileWriter(marker, false)) {
				writer.write(configPath == null ? "" : configPath);
			}
		} catch (Exception e) {
			Log.w(TAG, "writeSessionMarker failed", e);
		}
	}

	/**
	 * Records a save state in the recent list, newest first, and keeps five.
	 *
	 * A flat text file rather than JSON: four fields per line, written by one
	 * process and read by another, and a format that can be read with cat is
	 * worth more here than one that needs a parser on both sides.
	 *
	 * Dropping the sixth deletes its .uss too, or the states directory grows
	 * without bound for a list nothing shows.
	 */
	public static void recordSaveState(Context context, String title, String statePath, String configPath) {
		try {
			final File index = new File(context.getFilesDir(), "states/recent.txt");
			final List<String> lines = new ArrayList<>();
			lines.add(System.currentTimeMillis() + "\t" + title + "\t" + statePath + "\t" + configPath);

			if (index.exists()) {
				try (java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.FileReader(index))) {
					String line;
					while ((line = reader.readLine()) != null) {
						final String[] parts = line.split("\t");
						// Drop any earlier entry for the same game: one save
						// per config, the most recent.
						if (parts.length >= 3 && !parts[2].equals(statePath)) {
							lines.add(line);
						}
					}
				}
			}

			while (lines.size() > 5) {
				final String dropped = lines.remove(lines.size() - 1);
				final String[] parts = dropped.split("\t");
				if (parts.length >= 3) {
					final File old = new File(parts[2]);
					if (old.exists() && !old.delete()) {
						Log.w(TAG, "could not delete " + old);
					}
				}
			}

			try (java.io.FileWriter writer = new java.io.FileWriter(index, false)) {
				for (String line : lines) {
					writer.write(line);
					writer.write("\n");
				}
			}
		} catch (Exception e) {
			Log.w(TAG, "recordSaveState failed", e);
		}
	}

	/** Clears the marker showing a session is in progress. */
	public static void clearSessionMarker(Context context) {
		try {
			final File marker = new File(context.getFilesDir(), "session_active");
			if (marker.exists() && !marker.delete()) {
				Log.w(TAG, "could not delete session marker");
			}
		} catch (Exception e) {
			Log.w(TAG, "clearSessionMarker failed", e);
		}
	}
}
