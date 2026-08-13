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
