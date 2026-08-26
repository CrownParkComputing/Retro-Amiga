package com.uae4arm2026

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract

/**
 * Access to a folder the user picked, through the Storage Access Framework.
 *
 * This exists because scoped storage will not let the app walk /sdcard/Amiga.
 * The obvious permission for that is MANAGE_EXTERNAL_STORAGE, which Play
 * treats as a sensitive permission: an undeclared one blocks the release
 * outright, and declaring it means passing a review aimed at file managers,
 * backup and antivirus apps. Rather than gate every future update on that
 * review, the user grants one folder through the system picker and the grant
 * is persisted across reboots and app restarts.
 *
 * The tree grant supplies a friendly picker and remembers the chosen folder.
 * All-files access separately lets Dart and the native POSIX core use its real
 * shared-storage path in place; this class never copies media to Android/data.
 */
object MediaFolderAccess {

	const val REQUEST_PICK_FOLDER = 0x5AF0

	/**
	 * The shared Retro-Applications layout used across the handheld builds.
	 *
	 * "primary" is Android's stable Storage Access Framework name for internal
	 * shared storage. The Files UI may label that volume "Odin2", but baking
	 * the marketing name into a filesystem path would only work on one device.
	 * A missing folder is harmless: the system picker falls back to its normal
	 * location and the user can still select an SD-card collection instead.
	 */
	private const val preferredAmigaPath = "Retro-Applications/Amiga"

	private const val PREFS = "media_folder_access"
	private const val KEY_CHOSEN = "chosen_tree_uri"

	/**
	 * The tree the user actually chose, or null if they have not chosen one.
	 *
	 * The grant is still verified against the system on every call, because it
	 * can be revoked in Settings and the app has to notice rather than carry
	 * on with a URI it can no longer read. What is NOT taken from the system
	 * is WHICH grant to use.
	 *
	 * That used to be `persistedUriPermissions.firstOrNull { isReadPermission }`,
	 * and persistedUriPermissions has no defined order. With more than one
	 * grant held -- which happens whenever a release fails quietly, and the
	 * failure is a swallowed SecurityException -- successive calls could
	 * answer with different folders. The symptom was the wizard finding a
	 * card full of games, then "Scan again" reporting the same library as
	 * empty, because the second scan had silently switched back to the
	 * internal folder picked earlier.
	 *
	 * So the choice is remembered explicitly and only falls back to whatever
	 * the system lists if the remembered one is gone.
	 */
	fun grantedTree(activity: Activity): Uri? {
		val held = activity.contentResolver.persistedUriPermissions
			.filter { it.isReadPermission }
			.map { it.uri }
		if (held.isEmpty()) return null

		val prefs = activity.getSharedPreferences(PREFS, Activity.MODE_PRIVATE)
		val chosen = prefs.getString(KEY_CHOSEN, null)?.let(Uri::parse)
		if (chosen != null && held.contains(chosen)) return chosen

		// Remembered grant revoked, or a grant taken by an older build that
		// never recorded one. Adopt what is there and record it, so the next
		// call cannot answer differently.
		val fallback = held.first()
		prefs.edit().putString(KEY_CHOSEN, fallback.toString()).apply()
		return fallback
	}

	/**
	 * @param startDocumentId where to open, as "volume:path" -- see
	 *   MainActivity.documentIdFor. Null falls back to the internal volume,
	 *   which is only the right answer when there is nothing on a card.
	 */
	fun pickFolder(
		activity: Activity,
		initialSubfolder: String? = null,
		startDocumentId: String? = null,
	) {
		val safeSubfolder = initialSubfolder
			?.replace('\\', '/')
			?.split('/')
			?.filter { it.isNotBlank() && it != "." && it != ".." }
			?.joinToString("/")
			.orEmpty()
		val initialPath = if (safeSubfolder.isEmpty()) {
			preferredAmigaPath
		} else {
			"$preferredAmigaPath/$safeSubfolder"
		}
		val documentId = startDocumentId ?: "primary:$initialPath"
		val initialTree = Uri.parse(
			"content://com.android.externalstorage.documents/document/" +
				Uri.encode(documentId)
		)
		val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
			addFlags(
				Intent.FLAG_GRANT_READ_URI_PERMISSION or
					Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
			)
			// Open directly on the canonical Odin2/internal-storage collection.
			// This is only a starting location; ACTION_OPEN_DOCUMENT_TREE still
			// requires the user to grant the folder explicitly under scoped
			// storage, as required by Play policy.
			putExtra(DocumentsContract.EXTRA_INITIAL_URI, initialTree)
		}
		android.util.Log.i("RetroAmiga", "opening picker at $initialTree")
		activity.startActivityForResult(intent, REQUEST_PICK_FOLDER)
	}

	/**
	 * Takes the grant returned by the picker and makes it survive a restart.
	 *
	 * Without takePersistableUriPermission the URI works until the process
	 * dies and then reads fail, which looks exactly like the folder having
	 * been emptied.
	 */
	fun persist(activity: Activity, uri: Uri) {
		// Drop every earlier grant first. Grants accumulate, and grantedTree
		// answers with the first one the system lists - so picking a second
		// folder to correct a wrong first choice would silently keep reading
		// the wrong folder. Exactly one grant is held at a time.
		for (permission in activity.contentResolver.persistedUriPermissions) {
			if (permission.uri == uri) continue
			try {
				activity.contentResolver.releasePersistableUriPermission(
					permission.uri,
					Intent.FLAG_GRANT_READ_URI_PERMISSION
				)
			} catch (e: SecurityException) {
				// Already gone.
			}
		}
		activity.contentResolver.takePersistableUriPermission(
			uri,
			Intent.FLAG_GRANT_READ_URI_PERMISSION
		)
		// Recorded rather than inferred. See grantedTree.
		activity.getSharedPreferences(PREFS, Activity.MODE_PRIVATE)
			.edit()
			.putString(KEY_CHOSEN, uri.toString())
			.apply()
	}

	fun release(activity: Activity) {
		activity.getSharedPreferences(PREFS, Activity.MODE_PRIVATE)
			.edit()
			.remove(KEY_CHOSEN)
			.apply()
		for (permission in activity.contentResolver.persistedUriPermissions) {
			try {
				activity.contentResolver.releasePersistableUriPermission(
					permission.uri,
					Intent.FLAG_GRANT_READ_URI_PERMISSION
				)
			} catch (e: SecurityException) {
				// Already gone: nothing to release.
			}
		}
	}

	/** One file found under the tree. */
	data class Entry(
		val documentId: String,
		val name: String,
		/** Folders between the picked root and this file, "" at the top. */
		val relativeDirectory: String,
		val size: Long,
	)

	/**
	 * Every file under [tree], depth first.
	 *
	 * Queried through ContentResolver rather than DocumentFile.listFiles():
	 * listFiles builds an object per entry and issues a query per file for
	 * each attribute, which on a ten-thousand-file Amiga collection takes
	 * minutes. One projection per directory is the difference between a scan
	 * that finishes and one the user kills.
	 */
	/**
	 * How many files the walk in progress has seen, for a caller that wants to
	 * show it moving.
	 *
	 * The enumeration is one call that returns everything at once, so until
	 * now the only honest thing the UI could say while it ran was nothing --
	 * and on a card holding a big collection that is a counter sitting at zero
	 * for a minute or more, which reads as a hang. Dart polls this while it
	 * waits.
	 */
	val scanned = java.util.concurrent.atomic.AtomicInteger(0)

	fun enumerate(resolver: ContentResolver, tree: Uri, fileLimit: Int): List<Entry> {
		val rootId = DocumentsContract.getTreeDocumentId(tree)
		val found = ArrayList<Entry>()
		scanned.set(0)
		// Directories still to visit, as (documentId, relative path).
		val pending = ArrayDeque<Pair<String, String>>()
		pending.add(rootId to "")

		val projection = arrayOf(
			DocumentsContract.Document.COLUMN_DOCUMENT_ID,
			DocumentsContract.Document.COLUMN_DISPLAY_NAME,
			DocumentsContract.Document.COLUMN_MIME_TYPE,
			DocumentsContract.Document.COLUMN_SIZE,
		)

		while (pending.isNotEmpty() && found.size < fileLimit) {
			val (parentId, parentPath) = pending.removeFirst()
			val childrenUri =
				DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)

			val cursor = try {
				resolver.query(childrenUri, projection, null, null, null)
			} catch (e: Exception) {
				// A folder that vanished or a provider that refused: skip it
				// rather than lose every file found so far.
				null
			} ?: continue

			cursor.use {
				while (it.moveToNext() && found.size < fileLimit) {
					val id = it.getString(0) ?: continue
					val name = it.getString(1) ?: continue
					val mime = it.getString(2)
					val size = if (it.isNull(3)) 0L else it.getLong(3)

					if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
						val childPath =
							if (parentPath.isEmpty()) name else "$parentPath/$name"
						pending.add(id to childPath)
					} else {
						found.add(Entry(id, name, parentPath, size))
						scanned.lazySet(found.size)
					}
				}
			}
		}
		return found
	}
}
