package com.uae4arm2026.data

import android.content.Intent
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import com.uae4arm2026.data.model.AmigaFile
import com.uae4arm2026.data.model.FileCategory
import java.util.zip.CRC32
import java.util.zip.ZipInputStream
import java.io.File

object FileManager {

	private const val TAG = "Uae4Arm-FileManager"

	fun getAppStoragePath(context: Context): String {
		return context.getExternalFilesDir(null)?.absolutePath ?: ""
	}

	fun getCategoryDir(context: Context, category: FileCategory): File {
		return File(getAppStoragePath(context), category.dirName)
	}

	fun getScannableExtensions(category: FileCategory): Set<String> {
		return category.extensions + "zip"
	}

	fun acceptsImportExtension(category: FileCategory, extension: String): Boolean {
		return extension.lowercase() in getScannableExtensions(category)
	}

	fun acceptsImportName(category: FileCategory, fileName: String): Boolean {
		val extension = fileName.substringAfterLast('.', "").lowercase()
		return extension.isNotEmpty() && acceptsImportExtension(category, extension)
	}

	fun getEffectiveCategoryDir(context: Context, category: FileCategory): File {
		val configured = getCategoryLibraryPath(context, category)
		if (!configured.isNullOrBlank()) {
			val externalDir = File(configured)
			if (externalDir.isDirectory) {
				return externalDir
			}
		}
		return getCategoryDir(context, category)
	}

	fun resolveToFilePath(context: Context, uri: Uri): String? {
		val resolved = resolveDocumentPath(context, uri) ?: return null
		return resolved.takeIf { File(it).exists() }
	}

	fun resolveScopedStoragePath(context: Context, uri: Uri): String? {
		return resolveDocumentPath(context, uri)
	}

	/**
	 * Bridge a file from a SAF content:// URI or raw path.
	 * Never copies to internal storage unless it's a legacy scheme.
	 * This ensures large HDFs and CD images are used in-place.
	 */
	fun importFile(context: Context, uri: Uri, category: FileCategory): String? {
		resolveDocumentPath(context, uri)?.let { resolvedPath ->
			if (isAppOwnedPath(context, resolvedPath)) {
				return resolvedPath
			}
		}

		if (uri.scheme == "content") {
			Log.d(TAG, "Bridging content URI: $uri")
			val fileName = getFileName(context, uri) ?: return null
			if (!acceptsImportName(category, fileName)) {
				Log.w(TAG, "Rejected unsupported import for ${category.name}: $fileName")
				return null
			}
			persistFilePermission(context, uri)
			return MediaPathHelper.normalizeImportedPath(context, uri)
		}

		return uri.toString()
	}

	fun scanDirectory(
		dir: File,
		extensions: Set<String>,
		recursive: Boolean = false,
		forcedCategory: FileCategory? = null
	): List<AmigaFile> {
		if (!dir.exists() || !dir.isDirectory) return emptyList()
		val dirCategory = FileCategory.entries.firstOrNull { it.dirName.equals(dir.name, ignoreCase = true) }
		val requestedCategory = FileCategory.entries.firstOrNull { candidate ->
			extensions.isNotEmpty() && extensions.all { it in candidate.extensions }
		}
		val files = if (recursive) {
			dir.walkTopDown()
				.filter { file -> file.isFile && file.extension.lowercase() in extensions }
				.toList()
		} else {
			dir.listFiles()
				?.filter { file -> file.isFile && file.extension.lowercase() in extensions }
				?: emptyList()
		}

		return files.map { file ->
			val fileCategory = forcedCategory ?: dirCategory ?: FileCategory.fromExtension(file.extension) ?: requestedCategory ?: FileCategory.FLOPPIES
			val crc = if (fileCategory == FileCategory.ROMS) calculateRomCrc32(file) else null
			AmigaFile(
				path = file.absolutePath,
				name = file.name,
				extension = file.extension.lowercase(),
				size = file.length(),
				lastModified = file.lastModified(),
				category = fileCategory,
				crc32 = crc
			)
		}.sortedBy { it.name.lowercase() }
	}

	fun scanForCategory(context: Context, category: FileCategory): List<AmigaFile> {
		try {
			Log.d(TAG, "Scanning for category: ${category.name}")
			val results = mutableListOf<AmigaFile>()
			val seenPaths = mutableSetOf<String>()
			val extensions = getScannableExtensions(category)

			val categoryDir = getCategoryDir(context, category)
			for (file in scanDirectory(categoryDir, extensions, recursive = true, forcedCategory = category)) {
				if (seenPaths.add(file.path)) results.add(file)
			}

			val rootDir = File(getAppStoragePath(context))
			for (file in scanDirectory(rootDir, extensions, recursive = false, forcedCategory = category)) {
				if (seenPaths.add(file.path)) results.add(file)
			}

			if (category == FileCategory.ROMS) {
				val kickstartDirs = listOf(
					File(rootDir, "whdboot/game-data/Kickstarts"),
					File(rootDir, "whdboot/save-data/Kickstarts")
				)
				for (dir in kickstartDirs) {
					if (!dir.exists()) continue
					for (file in scanDirectory(dir, extensions, recursive = true, forcedCategory = category)) {
						if (seenPaths.add(file.path)) results.add(file)
					}
				}
			}

			val configuredDir = getCategoryLibraryPath(context, category)
			if (!configuredDir.isNullOrBlank()) {
				val externalDir = File(configuredDir)
				val uriString = getCategoryLibraryUri(context, category)
				if (!uriString.isNullOrBlank() && !isAppOwnedPath(context, configuredDir)) {
					for (file in scanDocumentDirectoryRecursive(context, Uri.parse(uriString), configuredDir, extensions, category)) {
						if (seenPaths.add(file.path)) results.add(file)
					}
				} else if (isAppOwnedPath(context, configuredDir)) {
					for (file in scanDirectory(externalDir, extensions, recursive = true, forcedCategory = category)) {
						if (seenPaths.add(file.path)) results.add(file)
					}
				}
			}
			return results.sortedBy { it.name.lowercase() }
		} catch (e: Exception) {
			Log.e(TAG, "Error scanning for category ${category.name}", e)
			return emptyList()
		}
	}

	private fun scanDocumentDirectoryRecursive(
		context: Context,
		treeUri: Uri,
		basePath: String,
		extensions: Set<String>,
		category: FileCategory
	): List<AmigaFile> {
		val results = mutableListOf<AmigaFile>()
		val rootId = try {
			DocumentsContract.getTreeDocumentId(treeUri)
		} catch (_: Exception) {
			DocumentsContract.getDocumentId(treeUri)
		}
		scanDocumentDirectoryInternal(context, treeUri, rootId, rootId, basePath, extensions, category, results)
		return results
	}

	private fun scanDocumentDirectoryInternal(
		context: Context,
		treeUri: Uri,
		rootId: String,
		parentId: String,
		basePath: String,
		extensions: Set<String>,
		category: FileCategory,
		results: MutableList<AmigaFile>
	) {
		val resolver = context.contentResolver
		val childrenUri = try {
			DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
		} catch (e: Exception) {
			return
		}

		val projection = arrayOf(
			DocumentsContract.Document.COLUMN_DOCUMENT_ID,
			DocumentsContract.Document.COLUMN_DISPLAY_NAME,
			DocumentsContract.Document.COLUMN_SIZE,
			DocumentsContract.Document.COLUMN_LAST_MODIFIED,
			DocumentsContract.Document.COLUMN_MIME_TYPE
		)

		val normBase = basePath.trimEnd('/')

		try {
			resolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
				val idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
				val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
				val sizeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
				val modIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
				val mimeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)

				while (cursor.moveToNext()) {
					val docId = cursor.getString(idIndex)
					val mime = cursor.getString(mimeIndex)
					val name = cursor.getString(nameIndex) ?: "unknown"

					if (DocumentsContract.Document.MIME_TYPE_DIR == mime) {
						if (!name.startsWith(".")) {
							val folderUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
							val folderPath = MediaPathHelper.normalizeImportedPath(context, folderUri).trimEnd('/')
							
							// Recurse if the folder is a parent of our target OR inside our target
							if (normBase.startsWith(folderPath, ignoreCase = true) || folderPath.startsWith(normBase, ignoreCase = true)) {
								scanDocumentDirectoryInternal(context, treeUri, rootId, docId, basePath, extensions, category, results)
							}
						}
						continue
					}

					val ext = name.substringAfterLast('.', "").lowercase()
					if (ext !in extensions) continue

					val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
					val storedPath = MediaPathHelper.normalizeImportedPath(context, docUri)
					
					// Ensure the file is actually inside the configured library folder
					if (!storedPath.startsWith(normBase, ignoreCase = true)) continue

					results.add(
						AmigaFile(
							path = storedPath,
							name = name,
							extension = ext,
							size = cursor.getLong(sizeIndex),
							lastModified = cursor.getLong(modIndex),
							category = category,
							crc32 = null
						)
					)
				}
			}
		} catch (e: Exception) {
			Log.e(TAG, "Error querying SAF children for $parentId", e)
		}
	}

	fun ensureDirectories(context: Context) {
		val base = context.getExternalFilesDir(null) ?: return
		FileCategory.entries.forEach { category ->
			File(base, category.dirName).let { if (!it.exists()) it.mkdirs() }
		}
		File(base, "conf").let { if (!it.exists()) it.mkdirs() }
	}

	fun getDisplayName(context: Context, uri: Uri): String? = getFileName(context, uri)

	fun getCategoryLibraryPath(context: Context, category: FileCategory): String? {
		val value = AppStorage.openPreferences(context).getString(getLibraryPathKey(category), null)?.trim()
		return value?.takeIf { it.isNotEmpty() }
	}

	fun setCategoryLibraryPath(context: Context, category: FileCategory, path: String?, treeUriString: String? = null) {
		val prefs = AppStorage.openPreferences(context)
		prefs.edit().apply {
			val normalized = path?.trim().orEmpty()
			if (normalized.isEmpty()) {
				remove(getLibraryPathKey(category))
				remove(getLibraryUriKey(category))
			} else {
				putString(getLibraryPathKey(category), normalized)
				if (treeUriString != null) {
					putString(getLibraryUriKey(category), treeUriString)
				}
			}
		}.apply()
	}

	fun persistDirectoryAccess(context: Context, uri: Uri) {
		if (!uri.scheme.equals("content", ignoreCase = true)) return
		if (!DocumentsContract.isTreeUri(uri)) {
			persistFilePermission(context, uri)
			return
		}
		val resolver = context.contentResolver
		try {
			resolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
		} catch (_: SecurityException) {
			try {
				resolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
			} catch (e: SecurityException) {
				Log.w(TAG, "Failed to persist directory access for $uri", e)
			}
		}
	}

	private fun persistFilePermission(context: Context, uri: Uri) {
		try {
			context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
		} catch (e: SecurityException) {
			Log.w(TAG, "Failed to persist file access for $uri", e)
		}
	}

	fun detectCategoryFolders(context: Context, treeUri: Uri): Map<FileCategory, String> {
		val rootPath = resolveDocumentPath(context, treeUri) ?: return emptyMap()
		val detected = detectCategoryFolders(rootPath)
		// On modern Android, we can't reliably use File.listFiles() on these detected paths
		// unless they are app-owned. We'll trust the path detection for now.
		return detected
	}

	fun countFilesInCategory(context: Context, category: FileCategory, path: String, treeUriString: String?): Int {
		if (path.isBlank()) return 0
		if (isAppOwnedPath(context, path)) {
			return File(path).listFiles()?.count { it.isFile && it.extension.lowercase() in category.extensions } ?: 0
		}
		
		val uri = treeUriString?.let { Uri.parse(it) } ?: return 0
		return try {
			val extensions = getScannableExtensions(category)
			val files = scanDocumentDirectoryRecursive(context, uri, path, extensions, category)
			files.size
		} catch (e: Exception) {
			0
		}
	}

	fun detectCategoryFolders(rootPath: String): Map<FileCategory, String> {
		val root = File(rootPath)
		if (!root.isDirectory) return emptyMap()
		val keywords = mapOf(
			FileCategory.ROMS to listOf("kickstart", "kick", "rom", "roms", "bios"),
			FileCategory.FLOPPIES to listOf("floppy", "floppies", "adf", "disk", "disks", "df0", "df1"),
			FileCategory.WHDLOAD_GAMES to listOf("whdload", "whd", "lha", "game", "games"),
			FileCategory.CD_IMAGES to listOf("cd", "cds", "cdrom", "cdroms", "iso", "disc", "discs"),
			FileCategory.HARD_DRIVES to listOf("hdf", "harddrive", "harddrives", "hdd")
		)
		val subdirs = root.listFiles()?.filter { it.isDirectory } ?: return emptyMap()
		val result = mutableMapOf<FileCategory, String>()
		val sortedPairs = keywords.entries.flatMap { (cat, kws) -> kws.map { kw -> cat to kw } }.sortedByDescending { it.second.length }
		for (dir in subdirs) {
			val nameLower = dir.name.lowercase()
			val nameNorm = nameLower.replace(Regex("[-_ ]+"), "")
			for ((category, kw) in sortedPairs) {
				if (category !in result && (nameLower.contains(kw) || nameNorm.contains(kw))) {
					result[category] = dir.absolutePath
					break
				}
			}
		}
		for (dir in subdirs) {
			val files = dir.listFiles()?.filter { it.isFile } ?: continue
			for ((category, _) in keywords) {
				if (category in result) continue
				if (files.any { it.extension.lowercase() in category.extensions }) {
					result[category] = dir.absolutePath
				}
			}
		}
		if (FileCategory.ROMS !in result) {
			val rootFiles = root.listFiles()?.filter { it.isFile } ?: emptyList()
			if (rootFiles.any { it.extension.lowercase() in FileCategory.ROMS.extensions }) {
				result[FileCategory.ROMS] = rootPath
			}
		}
		return result
	}

	fun resolveDirectoryPath(context: Context, uri: Uri): String? {
		val resolved = resolveDocumentPath(context, uri) ?: return null
		return resolved.takeIf { File(it).exists() && File(it).isDirectory }
	}

	fun isAppOwnedPath(context: Context, path: String): Boolean {
		val appRoot = getAppStoragePath(context).trim()
		if (appRoot.isEmpty()) return false
		if (path.startsWith("/proc/self/fd/", ignoreCase = true)) return true
		if (path.startsWith(context.getCacheDir().getAbsolutePath(), ignoreCase = true)) return true
		return path.startsWith(appRoot, ignoreCase = true)
	}

	private fun getFileName(context: Context, uri: Uri): String? {
		context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
			val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
			if (nameIndex >= 0 && cursor.moveToFirst()) {
				val name = cursor.getString(nameIndex)
				if (!name.isNullOrBlank()) return name
			}
		}
		return uri.lastPathSegment?.substringAfterLast('/')
	}

	fun getCategoryLibraryUri(context: Context, category: FileCategory): String? {
		return AppStorage.openPreferences(context).getString(getLibraryUriKey(category), null)
	}

	fun setCategoryLibraryUri(context: Context, category: FileCategory, uri: String?) {
		AppStorage.openPreferences(context).edit().apply {
			if (uri.isNullOrBlank()) remove(getLibraryUriKey(category))
			else putString(getLibraryUriKey(category), uri)
		}.apply()
	}

	private fun getLibraryPathKey(category: FileCategory): String = "library_path_${category.dirName}"
	fun getLibraryUriKey(category: FileCategory): String = "library_uri_${category.dirName}"

	fun treeUriToPath(uri: Uri): String? = try {
		val docId = DocumentsContract.getTreeDocumentId(uri)
		val split = docId.split(":")
		if (split.size >= 2) {
			if (split[0] == "primary") "${Environment.getExternalStorageDirectory()}/${split[1]}"
			else "/storage/${split[0]}/${split[1]}"
		} else {
			Environment.getExternalStorageDirectory().absolutePath
		}
	} catch (_: Exception) {
		null
	}

	private fun resolveDocumentPath(context: Context, uri: Uri): String? {
		if (uri.scheme.equals("file", ignoreCase = true)) return uri.path?.let { File(it).absolutePath }
		if (!uri.scheme.equals("content", ignoreCase = true)) return null
		val docId = resolveExternalStorageDocId(uri) ?: return null
		if (uri.authority != "com.android.externalstorage.documents") return null
		val parts = docId.split(':', limit = 2)
		if (parts.isEmpty()) return null
		val volume = parts[0]
		val relative = parts.getOrNull(1).orEmpty()
		val base = if (volume.equals("primary", ignoreCase = true)) Environment.getExternalStorageDirectory().absolutePath else "/storage/$volume"
		return if (relative.isBlank()) base else File(base, relative).absolutePath
	}

	private fun resolveExternalStorageDocId(uri: Uri): String? {
		return try { DocumentsContract.getDocumentId(uri) } catch (_: IllegalArgumentException) {
			try { DocumentsContract.getTreeDocumentId(uri) } catch (_: IllegalArgumentException) { null }
		}
	}

	private fun calculateRomCrc32(file: File): Long? {
		return if (file.extension.equals("zip", ignoreCase = true)) calculateZipEntryCrc32(file, FileCategory.ROMS.extensions) else calculateCrc32(file)
	}

	private fun calculateZipEntryCrc32(file: File, allowedExtensions: Set<String>): Long? {
		return try {
			var entryCount = 0
			var matchedCrc: Long? = null
			ZipInputStream(file.inputStream().buffered()).use { zip ->
				while (true) {
					val entry = zip.nextEntry ?: break
					if (entry.isDirectory) continue
					val ext = entry.name.substringAfterLast('.', "").lowercase()
					if (ext !in allowedExtensions) continue
					entryCount++
					if (entryCount > 1) return null
					val crc = CRC32()
					val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
					while (true) {
						val read = zip.read(buffer)
						if (read <= 0) break
						crc.update(buffer, 0, read)
					}
					matchedCrc = crc.value and 0xffffffffL
				}
			}
			matchedCrc
		} catch (e: Exception) {
			Log.w(TAG, "Failed to calculate ROM CRC32 inside zip ${file.absolutePath}", e)
			null
		}
	}

	private fun calculateCrc32(file: File): Long? {
		return try {
			val crc = CRC32()
			file.inputStream().use { input ->
				val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
				while (true) {
					val read = input.read(buffer)
					if (read <= 0) break
					crc.update(buffer, 0, read)
				}
			}
			crc.value and 0xffffffffL
		} catch (e: Exception) {
			Log.w(TAG, "Failed to calculate CRC32 for ${file.absolutePath}", e)
			null
		}
	}

	fun findContentUriForPath(context: Context, path: String): Uri? {
		if (path.isBlank() || path.startsWith("content://") || path.startsWith("/proc/")) return null
		var bestMatchCategory: FileCategory? = null
		var bestMatchLength = -1
		FileCategory.entries.forEach { category ->
			val libPath = getCategoryLibraryPath(context, category) ?: return@forEach
			val treeUriString = getCategoryLibraryUri(context, category) ?: return@forEach
			if (path.startsWith(libPath, ignoreCase = true)) {
				if (libPath.length > bestMatchLength) {
					bestMatchLength = libPath.length
					bestMatchCategory = category
				}
			}
		}
		val category = bestMatchCategory ?: return null
		run {
			val libPath = getCategoryLibraryPath(context, category)!!
			val treeUriString = getCategoryLibraryUri(context, category)!!
			val treeUri = Uri.parse(treeUriString)
			val rootId = try { DocumentsContract.getTreeDocumentId(treeUri) } catch(_: Exception) { null }
			if (rootId == null) return null
			val targetFile = File(path)
			val libFile = File(libPath)
			val treeRootPath = resolveDocumentPath(context, treeUri)
			val relativePath = when {
				treeRootPath != null && targetFile.absolutePath.equals(treeRootPath, ignoreCase = true) -> ""
				treeRootPath != null && targetFile.absolutePath.startsWith(treeRootPath, ignoreCase = true) ->
					targetFile.absolutePath.substring(treeRootPath.length).removePrefix("/").removePrefix("\\")
				libFile.absolutePath.equals(targetFile.absolutePath, ignoreCase = true) -> ""
				targetFile.absolutePath.startsWith(libFile.absolutePath, ignoreCase = true) ->
					targetFile.absolutePath.substring(libFile.absolutePath.length).removePrefix("/").removePrefix("\\")
				else -> null
			}
			if (relativePath == null) return null
			if (relativePath.isEmpty()) return treeUri
			val root = DocumentFile.fromTreeUri(context, treeUri) ?: return null
			var current: DocumentFile? = root
			val parts = relativePath.split(File.separator, "/")
			for (part in parts) {
				if (part.isEmpty()) continue
					current = current?.findFile(part)
				if (current == null) break
			}
			if (current != null) return current.uri
		}
		return null
	}
}
