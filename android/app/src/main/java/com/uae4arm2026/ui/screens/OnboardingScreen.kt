package com.uae4arm2026.ui.screens

import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.DrawableRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.FolderOff
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController
import com.uae4arm2026.R
import com.uae4arm2026.data.AgsDetector
import com.uae4arm2026.data.AppPreferences
import com.uae4arm2026.data.FileManager
import com.uae4arm2026.data.FileRepository
import com.uae4arm2026.data.model.AmigaModel
import com.uae4arm2026.data.model.FileCategory
import com.uae4arm2026.ui.findActivity
import com.uae4arm2026.ui.navigation.Screen
import com.uae4arm2026.ui.viewmodel.SettingsViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

@get:DrawableRes
private val FileCategory.onboardingDrawable: Int
	get() = when (this) {
		FileCategory.ROMS -> R.drawable.featured_kickstart_check
		FileCategory.FLOPPIES -> R.drawable.featured_floppy_inserted
		FileCategory.HARD_DRIVES -> R.drawable.featured_drive_dh0
		FileCategory.CD_IMAGES -> R.drawable.featured_cd32
		FileCategory.WHDLOAD_GAMES -> R.drawable.featured_a1200
	}

@DrawableRes
private fun artworkForModel(model: AmigaModel): Int = when (model) {
	AmigaModel.A1200 -> R.drawable.featured_a1200
	AmigaModel.A3000 -> R.drawable.featured_a3000
	AmigaModel.A4000 -> R.drawable.featured_a4000
	AmigaModel.CD32,
	AmigaModel.CDTV -> R.drawable.featured_cd32
	else -> R.drawable.featured_a500
}

private fun treeUriToPath(uri: Uri): String? = try {
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

@Composable
fun OnboardingScreen(navController: NavController) {
	val context = LocalContext.current
	val scope = rememberCoroutineScope()
	val prefs = remember { AppPreferences.getInstance(context) }
	val settingsViewModel: SettingsViewModel = viewModel(
		context.findActivity() as ComponentActivity
	)

	var rootPath by remember { mutableStateOf("") }
	var scanning by remember { mutableStateOf(false) }
	var scanned by remember { mutableStateOf(false) }
	var selectedModel by remember { mutableStateOf(AmigaModel.A1200) }
	var agsInstall by remember { mutableStateOf<AgsDetector.AgsInstall?>(null) }
	val detectedPaths = remember { mutableStateMapOf<FileCategory, String>() }
	val detectedUris = remember { mutableStateMapOf<FileCategory, Uri>() }
	val detectedCounts = remember { mutableStateMapOf<FileCategory, Int>() }

	var pickerCallback by remember { mutableStateOf<((Uri, String) -> Unit)?>(null) }
	val folderPickerLauncher = rememberLauncherForActivityResult(
		ActivityResultContracts.OpenDocumentTree()
	) { uri ->
		val path = uri?.let { treeUriToPath(it) }
		if (uri != null && path != null) {
			FileManager.persistDirectoryAccess(context, uri)
			pickerCallback?.invoke(uri, path)
		}
		pickerCallback = null
	}

	fun openPicker(onResult: (Uri, String) -> Unit) {
		pickerCallback = onResult
		folderPickerLauncher.launch(null)
	}

	fun scanFolder(uri: Uri, path: String) {
		rootPath = path
		scanning = true
		scanned = false
		scope.launch {
			val detected = withContext(Dispatchers.IO) {
				FileManager.detectCategoryFolders(context, uri)
			}
			detectedPaths.clear()
			detectedUris.clear()
			detectedCounts.clear()
			detected.forEach { (category, resolvedPath) ->
				detectedPaths[category] = resolvedPath
				detectedUris[category] = uri // Store the root tree URI
				detectedCounts[category] = withContext(Dispatchers.IO) {
					FileManager.countFilesInCategory(context, category, resolvedPath, uri.toString())
				}
			}

			scanning = false
			scanned = true
		}
	}

	fun finish() {
		scope.launch {
			try {
				// Save all detected library paths and their SAF URIs
				detectedPaths.forEach { (cat, path) ->
					if (path.isNotBlank()) {
						FileManager.setCategoryLibraryPath(context, cat, path, detectedUris[cat]?.toString())
					}
				}

				prefs.setHasCompletedSetup(true)
				prefs.setHasSeenWelcome(true)
				settingsViewModel.applyModel(selectedModel)
				val install = agsInstall
				if (install != null) {
					FileManager.setCategoryLibraryPath(context, FileCategory.HARD_DRIVES, install.agsDir.absolutePath)
				}
				navController.navigate(Screen.Configurations.route) {
					popUpTo(Screen.Onboarding.route) { inclusive = true }
				}
				launch(Dispatchers.IO) {
					try {
						FileRepository.getInstance(context).rescan()
					} catch (e: Exception) {
						android.util.Log.e("Onboarding", "Background rescan failed", e)
					}
				}
			} catch (e: Exception) {
				android.util.Log.e("Onboarding", "Finish setup failed", e)
				navController.navigate(Screen.Configurations.route) {
					popUpTo(Screen.Onboarding.route) { inclusive = true }
				}
			}
		}
	}

	val models = listOf(
		AmigaModel.A500,
		AmigaModel.A500_PLUS,
		AmigaModel.A600,
		AmigaModel.A1000,
		AmigaModel.A2000,
		AmigaModel.A1200,
		AmigaModel.A3000,
		AmigaModel.A4000,
		AmigaModel.CD32,
		AmigaModel.CDTV
	)

	val blueScheme = MaterialTheme.colorScheme.copy(
		primary = Color(0xFF1565C0),
		onPrimary = Color.White,
		primaryContainer = Color(0xFF1E3A6E),
		onPrimaryContainer = Color(0xFFBBDEFB)
	)

	MaterialTheme(colorScheme = blueScheme) {
		Scaffold { padding ->
			Column(
				modifier = Modifier
					.fillMaxSize()
					.padding(padding)
					.verticalScroll(rememberScrollState())
					.padding(horizontal = 20.dp),
				horizontalAlignment = Alignment.CenterHorizontally
			) {
				Spacer(Modifier.height(12.dp))
				Image(
					painter = painterResource(R.drawable.featured_default),
					contentDescription = "UAE4ARM",
					contentScale = ContentScale.Fit,
					modifier = Modifier
						.fillMaxWidth()
						.heightIn(min = 120.dp, max = 200.dp)
						.padding(horizontal = 24.dp, vertical = 8.dp)
				)
				Text("UAE4ARM", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
				Text(
					"Powered by Amiberry",
					style = MaterialTheme.typography.labelLarge,
					color = MaterialTheme.colorScheme.primary
				)
				Spacer(Modifier.height(16.dp))

				SectionHeader("1", "Choose Your Amiga Folder")
				Spacer(Modifier.height(8.dp))
				Text(
					"Pick the folder with your Kickstart ROMs, floppies, HDFs, WHDLoad games, or AGS_UAE install.",
					style = MaterialTheme.typography.bodySmall,
					textAlign = TextAlign.Center,
					color = MaterialTheme.colorScheme.onSurfaceVariant
				)
				Spacer(Modifier.height(12.dp))

				if (scanning) {
					CircularProgressIndicator(modifier = Modifier.size(40.dp), strokeWidth = 3.dp)
					Spacer(Modifier.height(8.dp))
					Text("Scanning...", style = MaterialTheme.typography.bodySmall)
				} else {
					OutlinedButton(
						onClick = { openPicker { uri, path -> scanFolder(uri, path) } },
						modifier = Modifier.fillMaxWidth().height(48.dp)
					) {
						Icon(Icons.Default.FolderOpen, contentDescription = null, modifier = Modifier.size(18.dp))
						Spacer(Modifier.width(8.dp))
						Text(if (scanned) "Pick Different Folder" else "Choose Folder")
					}
				}
				if (rootPath.isNotBlank()) {
					Spacer(Modifier.height(4.dp))
					Text(
						rootPath,
						style = MaterialTheme.typography.labelSmall,
						color = MaterialTheme.colorScheme.onSurfaceVariant,
						maxLines = 1,
						overflow = TextOverflow.Ellipsis,
						modifier = Modifier.fillMaxWidth(),
						textAlign = TextAlign.Center
					)
				}

				if (scanned) {
					Spacer(Modifier.height(16.dp))
					ScanResults(detectedPaths, detectedCounts) { category ->
						openPicker { uri, path ->
							FileManager.persistDirectoryAccess(context, uri)
							detectedPaths[category] = path
							detectedUris[category] = uri
							FileManager.setCategoryLibraryPath(context, category, path, uri.toString())
							scope.launch {
								detectedCounts[category] = withContext(Dispatchers.IO) {
									File(path).listFiles()?.count { it.isFile && it.extension.lowercase() in category.extensions } ?: 0
								}
							}
						}
					}
				}

				Spacer(Modifier.height(16.dp))
				HorizontalDivider()
				Spacer(Modifier.height(16.dp))
				SectionHeader("2", "AGS Setup")
				Spacer(Modifier.height(8.dp))
				AgsSetupCard(
					install = agsInstall,
					onPickAgs = {
						openPicker { _, path ->
							scope.launch {
								val ags = withContext(Dispatchers.IO) {
									AgsDetector.detectFromPath(context, path)
								}
								agsInstall = ags
							}
						}
					}
				)

				Spacer(Modifier.height(16.dp))
				HorizontalDivider()
				Spacer(Modifier.height(16.dp))
				SectionHeader("3", "Choose Your Amiga Model")
				Spacer(Modifier.height(10.dp))
				LazyRow(
					contentPadding = PaddingValues(horizontal = 4.dp),
					horizontalArrangement = Arrangement.spacedBy(10.dp)
				) {
					items(models) { model ->
						ModelCardCompact(
							model = model,
							selected = model == selectedModel,
							onClick = { selectedModel = model }
						)
					}
				}

				Spacer(Modifier.height(24.dp))
				Button(
					onClick = { finish() },
					modifier = Modifier.fillMaxWidth().height(56.dp)
				) {
					Text("Finish Setup", style = MaterialTheme.typography.titleMedium)
				}
				Spacer(Modifier.height(16.dp))
			}
		}
	}
}

@Composable
private fun SectionHeader(number: String, title: String) {
	Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
		Surface(color = MaterialTheme.colorScheme.primary, shape = RoundedCornerShape(50), modifier = Modifier.size(28.dp)) {
			Box(contentAlignment = Alignment.Center) {
				Text(number, color = MaterialTheme.colorScheme.onPrimary, fontWeight = FontWeight.Bold)
			}
		}
		Spacer(Modifier.width(10.dp))
		Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
	}
}

@Composable
private fun ScanResults(
	detectedPaths: Map<FileCategory, String>,
	detectedCounts: Map<FileCategory, Int>,
	onManualPick: (FileCategory) -> Unit
) {
	SectionHeader("✓", if (detectedPaths.isEmpty()) "Nothing Found" else "Found Files")
	Spacer(Modifier.height(8.dp))
	if (detectedPaths.isEmpty()) {
		OutlinedCard(
			modifier = Modifier.fillMaxWidth().clickable { onManualPick(FileCategory.ROMS) }
		) {
			Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
				Icon(Icons.Default.FolderOff, contentDescription = null, modifier = Modifier.size(24.dp))
				Spacer(Modifier.width(10.dp))
				Text("No Amiga folders detected. Tap here to pick your Kickstarts folder manually.", style = MaterialTheme.typography.bodySmall)
			}
		}
		return
	}
	detectedPaths.keys.chunked(2).forEach { rowCats ->
		Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
			rowCats.forEach { category ->
				CompactCategoryCard(
					category = category,
					fileCount = detectedCounts[category] ?: 0,
					modifier = Modifier.weight(1f).padding(vertical = 4.dp).clickable { onManualPick(category) }
				)
			}
			if (rowCats.size == 1) Spacer(Modifier.weight(1f))
		}
	}
}

@Composable
private fun CompactCategoryCard(category: FileCategory, fileCount: Int, modifier: Modifier = Modifier) {
	OutlinedCard(modifier = modifier) {
		Row(modifier = Modifier.padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
			Image(
				painter = painterResource(category.onboardingDrawable),
				contentDescription = null,
				contentScale = ContentScale.Fit,
				modifier = Modifier.size(24.dp).clip(RoundedCornerShape(4.dp))
			)
			Spacer(Modifier.width(8.dp))
			Column(modifier = Modifier.weight(1f)) {
				Text(category.displayName, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold, maxLines = 1)
				Text(
					if (fileCount > 0) "$fileCount files" else "folder set",
					style = MaterialTheme.typography.labelSmall,
					color = MaterialTheme.colorScheme.onSurfaceVariant
				)
			}
			Icon(Icons.Default.CheckCircle, contentDescription = null, modifier = Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
		}
	}
}

@Composable
private fun AgsSetupCard(
	install: AgsDetector.AgsInstall?,
	onPickAgs: () -> Unit
) {
	OutlinedCard(modifier = Modifier.fillMaxWidth().clickable(onClick = onPickAgs)) {
		Row(modifier = Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
			Image(
				painter = painterResource(R.drawable.featured_a1200),
				contentDescription = null,
				contentScale = ContentScale.Fit,
				modifier = Modifier.size(56.dp).clip(RoundedCornerShape(8.dp))
			)
			Spacer(Modifier.width(12.dp))
			Column(modifier = Modifier.weight(1f)) {
				Text(
					if (install == null) "Find AGS Amiga Game Selector" else "AGS Amiga Game Selector found",
					style = MaterialTheme.typography.bodyMedium,
					fontWeight = FontWeight.SemiBold
				)
				Text(
					install?.agsDir?.absolutePath ?: "Tap to point to your AGS_UAE folder",
					style = MaterialTheme.typography.labelSmall,
					color = MaterialTheme.colorScheme.onSurfaceVariant,
					maxLines = 1,
					overflow = TextOverflow.Ellipsis
				)
			}
			Icon(
				Icons.Default.FolderOpen,
				contentDescription = "Choose AGS folder",
				tint = MaterialTheme.colorScheme.primary,
				modifier = Modifier.size(28.dp)
			)
		}
	}
}

@Composable
private fun ModelCardCompact(model: AmigaModel, selected: Boolean, onClick: () -> Unit) {
	val borderColor = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant
	val borderWidth = if (selected) 2.dp else 1.dp
	val bgColor = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant
	Card(
		modifier = Modifier
			.width(130.dp)
			.border(borderWidth, borderColor, RoundedCornerShape(12.dp))
			.clip(RoundedCornerShape(12.dp))
			.clickable { onClick() },
		colors = CardDefaults.cardColors(containerColor = bgColor),
		shape = RoundedCornerShape(12.dp)
	) {
		Column(
			modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 10.dp),
			horizontalAlignment = Alignment.CenterHorizontally
		) {
			Image(
				painter = painterResource(artworkForModel(model)),
				contentDescription = model.displayName,
				contentScale = ContentScale.Fit,
				modifier = Modifier.fillMaxWidth().height(64.dp)
			)
			Spacer(Modifier.height(4.dp))
			Text(
				model.displayName,
				style = MaterialTheme.typography.bodySmall,
				fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
				textAlign = TextAlign.Center,
				maxLines = 1
			)
			Text(
				model.chipset,
				style = MaterialTheme.typography.labelSmall,
				textAlign = TextAlign.Center,
				color = MaterialTheme.colorScheme.onSurfaceVariant,
				maxLines = 1
			)
			if (selected) {
				Spacer(Modifier.height(2.dp))
				Icon(Icons.Default.CheckCircle, contentDescription = "Selected", modifier = Modifier.size(16.dp))
			}
		}
	}
}
