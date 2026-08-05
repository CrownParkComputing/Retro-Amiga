package com.uae4arm2026.data

import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import com.uae4arm2026.data.model.FileCategory
import java.io.File

/**
 * Detects an AGS_UAE installation on the device and generates a ready-to-run
 * .uae config for it — zero user setup required.
 *
 * Detection looks for an `AGS_UAE/` folder containing the minimum set of HDF
 * files under several common storage locations.
 */
object AgsDetector {

    private const val BOOTPRI_NOAUTOBOOT = -128
    private const val AGS_SHARED_DEVICE = "DH10"
    const val AGS_WIDESCREEN_RTG_WIDTH = 1920
    const val AGS_WIDESCREEN_RTG_HEIGHT = 1080

	private fun normalizeAgsRtgResolution(width: Int, height: Int): Pair<Int, Int> {
		return when {
			width <= 0 || height <= 0 -> AGS_WIDESCREEN_RTG_WIDTH to AGS_WIDESCREEN_RTG_HEIGHT
			else -> width to height
		}
	}

    /** Minimum HDF files required to consider a folder a valid AGS install. */
    private val REQUIRED_HDFS = listOf("Workbench.hdf", "AGS_Drive.hdf", "Games.hdf")

    private fun exists(context: Context, parent: File, filename: String): Boolean {
        if (File(parent, filename).exists()) return true
        
        // Try all category URIs as any of them might be the root for this AGS install
        FileCategory.entries.forEach { cat ->
            try {
                val uriString = FileManager.getCategoryLibraryUri(context, cat)
                if (uriString != null) {
                    val treeUri = Uri.parse(uriString)
                    val root = androidx.documentfile.provider.DocumentFile.fromTreeUri(context, treeUri)
                    if (root != null) {
                        // If the tree root is the parent, check directly
                        val treeId = DocumentsContract.getTreeDocumentId(treeUri)
                        val treePath = docIdToPath(treeId)
                        if (treePath != null && parent.absolutePath.startsWith(treePath)) {
                             if (root.findFile(filename)?.exists() == true) return true
                        }
                    }
                }
            } catch (_: Exception) {}
        }
        return false
    }

    private fun docIdToPath(docId: String): String? {
        val idx = docId.indexOf(':')
        if (idx < 0) return null
        val type = docId.substring(0, idx)
        val relative = docId.substring(idx + 1)
        val base = when (type) {
            "primary" -> Environment.getExternalStorageDirectory().absolutePath
            else -> "/storage/$type"
        }
        return if (relative.isEmpty()) base else "$base/$relative"
    }

    /** Full ordered list of HDF mounts (device label → filename). Only files
     *  present on disk are included in the generated config.
     *
     *  This matches the known-good AGS layout used by the original AGS_UAE
     *  configs so guest-side startup expects the same drive mapping. */
    private val ALL_HDF_MOUNTS = listOf(
        "DH0" to "Workbench.hdf",
        "DH1" to "Work.hdf",
        "DH2" to "Music.hdf",
        "DH3" to "Media.hdf",
        "DH4" to "AGS_Drive.hdf",
        "DH5" to "Games.hdf",
        "DH6" to "Premium.hdf",
        "DH7" to "Emulators2.hdf",
        "DH8" to "WHD_Demos.hdf",
        "DH9" to "WHD_Games.hdf",
    )
    private val AGS_DRIVE_SLOTS = ALL_HDF_MOUNTS.map { (dev, _) -> dev }
    private val AGS_DRIVE_IMAGE_EXTENSIONS = setOf("hdf", "hdi", "vhd", "hdz")

    data class AgsInstall(
        /** The `AGS_UAE/` directory. */
        val agsDir: File,
        /** Absolute path to the A1200 3.1 ROM, or null if not found. */
        val romFile: String?,
    )

    // ── Detection ────────────────────────────────────────────────────────────

    /**
     * Scan common storage roots for an AGS_UAE folder.
     * Returns the first valid install found, or null.
     *
     * Should be called from a background coroutine — involves file I/O.
     */
    fun detect(context: Context): AgsInstall? {
        val roots = buildList {
            // Primary: /storage/emulated/0/
            add(Environment.getExternalStorageDirectory())
            // Common WinUAE-style subfolder
            add(File(Environment.getExternalStorageDirectory(), "WinUAE"))
            // Any configured library folder's parent (user may preserve folder structure)
            FileCategory.entries.forEach { cat ->
                FileManager.getCategoryLibraryPath(context, cat)?.let { path ->
                    try {
                        File(path).parentFile?.let { add(it) }
                    } catch (_: Exception) {}
                }
            }
        }.filterNotNull().distinctBy { it.absolutePath }

        for (root in roots) {
            val candidate = File(root, "AGS_UAE")
            if (isValidAgsDir(context, candidate)) {
                return AgsInstall(
                    agsDir  = candidate,
                    romFile = findRom(context, candidate),
                )
            }
        }
        return null
    }

    /**
     * Resolve an AGS install from the persisted library path.
     */
    fun detectFromAgsLibraryPath(context: Context): AgsInstall? {
        val paths = listOfNotNull(
            FileManager.getCategoryLibraryPath(context, FileCategory.HARD_DRIVES),
            FileManager.getCategoryLibraryPath(context, FileCategory.WHDLOAD_GAMES),
        )
        return paths.firstNotNullOfOrNull { path -> detectFromPath(context, path) }
    }

    /**
     * Resolve an AGS install from a user-selected directory.
     * Accepts either the AGS_UAE directory itself or a parent directory that contains it.
     */
    fun detectFromPath(context: Context, path: String): AgsInstall? {
        android.util.Log.d("AgsDetector", "Checking path: $path")
        val selected = File(path)
        val candidates = buildList {
            add(selected)
            add(File(selected, "AGS_UAE"))
        }.distinctBy { it.absolutePath }

        val agsDir = candidates.firstOrNull { dir ->
            REQUIRED_HDFS.any { exists(context, dir, it) }
        } ?: return null

        android.util.Log.i("AgsDetector", "Detected AGS at: ${agsDir.absolutePath}")
        return AgsInstall(
            agsDir = agsDir,
            romFile = findRom(context, agsDir),
        )
    }

    /**
     * Reconstruct an AGS install from already-mounted HDF paths persisted in settings.
     * This is used after app reload so AGS launches continue to use the dedicated AGS config
     * without forcing the user to remount.
     */
    fun detectFromMountedDrives(context: Context, paths: List<String>): AgsInstall? {
        val nonEmpty = paths.filter { it.isNotBlank() }
        if (nonEmpty.isEmpty()) return null

        val files = nonEmpty.map { File(it) }.filterNot { it.isDirectory }
        if (files.isEmpty()) return null

        val parent = files.firstOrNull()?.parentFile ?: return null
        
        val requiredPresent = REQUIRED_HDFS.any { name -> exists(context, parent, name) }
        if (!requiredPresent) return null

        return AgsInstall(
            agsDir = parent,
            romFile = findRom(context, parent),
        )
    }

    private fun isValidAgsDir(context: Context, dir: File): Boolean {
        val exists = dir.exists() || dir.path.contains("/storage/") // Trust storage paths if check fails
        return exists && REQUIRED_HDFS.all { exists(context, dir, it) }
    }

    private fun agsDriveAssignments(context: Context, agsDir: File): List<Pair<String, File>> {
        val knownByFilename = ALL_HDF_MOUNTS.associateBy(
            keySelector = { (_, filename) -> filename.lowercase() },
            valueTransform = { (dev, _) -> dev },
        )

        val knownPresentByDevice = linkedMapOf<String, File>()
        val extraImages = mutableListOf<File>()

        // Check for Workbench.hdf or any file starting with 'Workbench' that is an HDF
        val files = try { agsDir.listFiles() } catch (_: Exception) { null }
        if (files != null) {
            files.forEach { file ->
                val nameLower = file.name.lowercase()
                val ext = file.extension.lowercase()
                if (ext !in AGS_DRIVE_IMAGE_EXTENSIONS) return@forEach

                if (nameLower.startsWith("workbench")) {
                    knownPresentByDevice["DH0"] = file
                } else {
                    val mappedDevice = knownByFilename[nameLower]
                    if (mappedDevice != null) {
                        knownPresentByDevice[mappedDevice] = file
                    } else {
                        extraImages += file
                    }
                }
            }
        }

        // If listFiles was empty or failed, fallback to explicit existence checks for core drives
        if (knownPresentByDevice.isEmpty()) {
            ALL_HDF_MOUNTS.forEach { (dev, filename) ->
                if (exists(context, agsDir, filename)) {
                    knownPresentByDevice[dev] = File(agsDir, filename)
                }
            }
        }

        val ordered = mutableListOf<Pair<String, File>>()
        AGS_DRIVE_SLOTS.forEach { dev ->
            knownPresentByDevice[dev]?.let { file ->
                ordered += dev to file
            }
        }

        val usedSlots = ordered.map { (dev, _) -> dev }.toSet()
        val freeSlots = AGS_DRIVE_SLOTS.filterNot { it in usedSlots }
        val sortedExtras = extraImages.sortedBy { it.name.lowercase() }
        freeSlots.zip(sortedExtras).forEach { (dev, file) ->
            ordered += dev to file
        }

        return ordered
    }

    private fun findRom(context: Context, agsDir: File): String? {
        val parent = try { agsDir.parentFile } catch (_: Exception) { null } ?: return null
        val candidates = listOf(
            "kick31.rom",
            "kick310.rom",
            "amiga-os-310-a1200.rom",
            "roms/AmigaForever/amiga-os-310-a1200.rom",
            "roms/amiga-os-310-a1200.rom",
            "roms/kick31.rom",
            "roms/kick310.rom",
            "Kickstarts/amiga-os-310-a1200.rom",
            "Kickstarts/kick31.rom",
            "AGS_UAE/roms/amiga-os-310-a1200.rom",
            "AGS_UAE/roms/kick31.rom",
            "AGS_UAE/kick31.rom",
            "AGS_UAE/kick310.rom"
        )
        
        candidates.forEach { relPath ->
            val parts = relPath.split('/')
            var current = parent
            var found = true
            for (part in parts) {
                if (!exists(context, current, part)) {
                    found = false
                    break
                }
                current = File(current, part)
            }
            if (found) return current.absolutePath
        }

        // Also check app-internal roms folder
        val internalRomsDir = File(FileManager.getAppStoragePath(context), "roms")
        val internalCandidates = listOf("kick31.rom", "kick310.rom", "amiga-os-310-a1200.rom")
        internalCandidates.forEach { name ->
            val f = File(internalRomsDir, name)
            if (f.exists()) return f.absolutePath
        }

        return null
    }

    /**
     * Return the ordered list of AGS HDFs present on disk so the Android HDF UI
     * can mount them directly into DH0.. slots.
     */
    fun mountableHardDrives(context: Context, install: AgsInstall): List<String> {
        val drives = agsDriveAssignments(context, install.agsDir).map { (_, file) -> file.absolutePath }.toMutableList()
        
        val sharedDir = getAgsSharedDir(install.agsDir)
        if (sharedDir != null) {
            while (drives.size < 11) {
                drives.add("")
            }
            drives[10] = sharedDir.absolutePath
        }
        
        return drives
    }

    private fun getAgsSharedDir(agsDir: File): File? {
        val candidates = listOf(
            File(agsDir, "SHARED"),
            File(agsDir, "Shared"),
            File(agsDir.parentFile, "SHARED"),
            File(agsDir.parentFile, "Shared")
        )
        return candidates.firstOrNull { it.isDirectory }
    }

    // ── Config generation ────────────────────────────────────────────────────

    /**
     * Generate a .uae config string for the given AGS install.
     * Only mounts HDF files that are actually present on disk.
     */
    fun generateConfig(
        context: Context,
        install: AgsInstall,
        fallbackRomFile: String? = null,
        rtgWidth: Int = 1920,
        rtgHeight: Int = 1080,
    ): String {
		val (effectiveRtgWidth, effectiveRtgHeight) = normalizeAgsRtgResolution(rtgWidth, rtgHeight)
        var mountIndex = 0
        val sb = StringBuilder()
        sb.appendLine("; Auto-generated AGS_UAE config")
        sb.appendLine()

        // CPU — A1200 with JIT
        sb.appendLine("cpu_model=68020")
        sb.appendLine("cpu_compatible=false")
        sb.appendLine("cpu_24bit_addressing=false")
        sb.appendLine("cpu_speed=max")
        sb.appendLine("fpu_model=68882")
        sb.appendLine("cachesize=16384")
        sb.appendLine("compfpu=false")

        // Chipset
        sb.appendLine("chipset=aga")
        sb.appendLine("chipset_compatible=A1200")
        sb.appendLine("immediate_blits=false")
        sb.appendLine("collision_level=playfields")
        sb.appendLine("cycle_exact=false")
        sb.appendLine("ntsc=false")

        // Memory
        sb.appendLine("chipmem_size=4")
        sb.appendLine("bogomem_size=0")
        sb.appendLine("fastmem_size=0")
        sb.appendLine("z3mem_size=512")

        // RTG (Picasso96 / UAEGFX)
        sb.appendLine("gfxcard_type=ZorroIII")
        sb.appendLine("gfxcard_size=8")
        sb.appendLine("rtg_nocustom=true")
        sb.appendLine("rtg_noautomodes=false")

        // Kickstart ROM
        val romFile = install.romFile ?: fallbackRomFile
        if (!romFile.isNullOrBlank()) {
            sb.appendLine("kickstart_rom_file=$romFile")
        }

        // Floppy (none inserted)
        sb.appendLine("floppy0=")
        sb.appendLine("floppy1=")
        sb.appendLine("floppy1type=-1")
        sb.appendLine("nr_floppies=1")
        sb.appendLine("floppy_speed=0")

        // Hard drives
        agsDriveAssignments(context, install.agsDir).forEach { (dev, file) ->
            val bootPri = if (dev == "DH0") 5 else BOOTPRI_NOAUTOBOOT
            val path = file.absolutePath
            val controller = "ide$mountIndex"
            sb.appendLine("hardfile2=rw,$dev:\"$path\",0,0,0,512,$bootPri,uaehf.device,$controller")
            mountIndex++
        }

        getAgsSharedDir(install.agsDir)?.let { shared ->
            val path = shared.absolutePath
            sb.appendLine("filesystem2=rw,$AGS_SHARED_DEVICE:SHARED:\"$path\",$BOOTPRI_NOAUTOBOOT")
            sb.appendLine("uaehf${mountIndex}_bootpri=$BOOTPRI_NOAUTOBOOT")
        }

        // Sound
        sb.appendLine("sound_output=exact")
        sb.appendLine("sound_channels=stereo")
        sb.appendLine("sound_stereo_separation=1")
        sb.appendLine("sound_frequency=48000")
        sb.appendLine("sound_interpol=none")

        // Display
        sb.appendLine("gfx_width=$effectiveRtgWidth")
        sb.appendLine("gfx_height=$effectiveRtgHeight")
        sb.appendLine("gfx_width_windowed=$effectiveRtgWidth")
        sb.appendLine("gfx_height_windowed=$effectiveRtgHeight")
        sb.appendLine("gfx_width_fullscreen=$effectiveRtgWidth")
        sb.appendLine("gfx_height_fullscreen=$effectiveRtgHeight")
        sb.appendLine("gfx_fullscreen_amiga=fullwindow")
        sb.appendLine("gfx_fullscreen_picasso=fullwindow")
        sb.appendLine("gfx_correct_aspect=false")
        sb.appendLine("gfx_auto_crop=false")
        sb.appendLine("show_leds=false")

        // Input
        sb.appendLine("joyport0=mouse")
        sb.appendLine("joyport1=joy1")
        sb.appendLine("amiberry.android_joyport1=joy1")
        sb.appendLine("amiberry.touch_settings_version=1")
        
        // Force native on-screen joystick and keyboard OFF. We use our own Android overlays.
        sb.appendLine("onscreen_joystick=false")
        sb.appendLine("amiberry.onscreen_joystick=false")
        sb.appendLine("onscreen_cd32pad=false")
        sb.appendLine("amiberry.onscreen_cd32pad=false")
        sb.appendLine("vkbd_enabled=false")
        sb.appendLine("input.default_osk=false")
        sb.appendLine("amiberry.show_android_keyboard_button=true")

        // Misc
        sb.appendLine("use_gui=no")
        sb.appendLine("bsdsocket_emu=true")

        return sb.toString()
    }

    /**
     * Write the config to `conf/ags_auto.uae` under the app's external files
     * directory and return the absolute path.
     */
    fun writeConfig(
        context: Context,
        install: AgsInstall,
        fallbackRomFile: String? = null,
        rtgWidth: Int = 1920,
        rtgHeight: Int = 1080,
    ): String {
        val confDir = File(context.getExternalFilesDir(null), "conf")
        confDir.mkdirs()
        val file = File(confDir, "ags_auto.uae")
        file.writeText(generateConfig(context, install, fallbackRomFile, rtgWidth, rtgHeight))
        return file.absolutePath
    }
}
