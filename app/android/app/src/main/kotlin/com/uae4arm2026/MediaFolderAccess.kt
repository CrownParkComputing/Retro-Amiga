package com.uae4arm2026

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import java.io.File

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
 * What SAF hands back is a content:// document tree, not a path. The emulator
 * core opens Kickstarts and disk images with plain POSIX file calls and cannot
 * be given a URI, so the tree is used as an import SOURCE: it is enumerated
 * here, and [copyDocument] writes the bytes into the app's own media folder,
 * where every existing path in the app and the core keeps working unchanged.
 */
object MediaFolderAccess {

	const val REQUEST_PICK_FOLDER = 0x5AF0

	/**
	 * The persisted tree, or null if the user has not granted one.
	 *
	 * Read back from the system rather than from our own preferences: a grant
	 * can be revoked in Settings, and the app must notice that rather than
	 * carry on with a URI it can no longer read.
	 */
	fun grantedTree(activity: Activity): Uri? =
		activity.contentResolver.persistedUriPermissions
			.firstOrNull { it.isReadPermission }
			?.uri

	fun pickFolder(activity: Activity) {
		val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
			addFlags(
				Intent.FLAG_GRANT_READ_URI_PERMISSION or
					Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
			)
		}
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
	}

	fun release(activity: Activity) {
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
	fun enumerate(resolver: ContentResolver, tree: Uri, fileLimit: Int): List<Entry> {
		val rootId = DocumentsContract.getTreeDocumentId(tree)
		val found = ArrayList<Entry>()
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
					}
				}
			}
		}
		return found
	}

	/**
	 * Copies one document out of [tree] to [destination].
	 *
	 * Written to a .part file and renamed on success, so an import killed
	 * halfway - a phone that sleeps mid-copy on a 700MB hard drive image -
	 * cannot leave a truncated ADF that the core will happily try to boot.
	 */
	fun copyDocument(
		resolver: ContentResolver,
		tree: Uri,
		documentId: String,
		destination: String,
	): Boolean {
		val uri = DocumentsContract.buildDocumentUriUsingTree(tree, documentId)
		val target = File(destination)
		target.parentFile?.mkdirs()
		val partial = File("$destination.part")
		return try {
			resolver.openInputStream(uri).use { input ->
				if (input == null) return false
				partial.outputStream().use { output -> input.copyTo(output, 1 shl 16) }
			}
			if (target.exists()) target.delete()
			partial.renameTo(target)
		} catch (e: Exception) {
			partial.delete()
			false
		}
	}
}
